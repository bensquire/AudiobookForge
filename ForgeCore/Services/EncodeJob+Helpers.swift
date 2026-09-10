import Foundation
import ImageIO

/// Pure, process-free helpers split out of EncodeJob.swift: ffmpeg
/// argument builders, loudness math, and the enqueue-time resolvers the
/// queue and the CLI call before any job exists. Everything here is
/// `nonisolated` — no `EncodeJob` instance state is touched.
extension EncodeJob {
    // MARK: - Pure arg builders (unit-testable, no Process spawn)

    nonisolated static func remuxArgs(
        concatListURL: URL, metaURL: URL, coverURL: URL?, outputURL: URL
    ) -> [String] {
        concatToMP4Args(
            listURL: concatListURL,
            metaURL: metaURL,
            coverURL: coverURL,
            outputURL: outputURL,
            extraFflags: nil
        )
    }

    nonisolated static func phase1Args(
        input: URL,
        output: URL,
        bitrate: String,
        sampleRate: Int,
        channels: Int,
        gainFilter: String? = nil
    ) -> [String] {
        var args: [String] = [
            "-i", input.path,
            "-vn"
        ]
        if let gainFilter {
            args += ["-af", gainFilter]
        }
        args += [
            "-c:a", "libfdk_aac",
            "-b:a", bitrate,
            "-ar", String(sampleRate),
            "-ac", String(channels),
            "-profile:a", "aac_low",
            "-flags", "+bitexact",
            "-threads", "1",
            "-f", "mp4",
            output.path
        ]
        return args
    }

    /// Convert one chunk's `FFmpegRunner` progress (a 0…1 fraction of
    /// that chunk) into what the phase-1 plumbing needs: seconds of
    /// source audio for `ProgressAggregator`, and a rounded percent for
    /// the per-chunk update gate. Kept separate because the two units
    /// were once confused here and the bar sat at 0% for whole encodes.
    nonisolated static func phase1ChunkProgress(
        fraction: Double, chapterDuration: TimeInterval
    ) -> (seconds: TimeInterval, pct: Int) {
        let clamped = min(1, max(0, fraction))
        return (clamped * chapterDuration, Int(clamped * 100))
    }

    /// Cap per-chapter loudness measurement to this many seconds. EBU
    /// R128's integrated value stabilises within ~30–60s of continuous
    /// speech, so two minutes is comfortably enough for audiobook
    /// chapters (low dynamic range, few gated regions). Worst-case drift
    /// vs. full-file integrated is ~0.3 LU on typical speech content.
    nonisolated static let ebur128MeasureCapSeconds: Int = 120

    /// `ffmpeg` arg list to measure a single chapter's integrated
    /// loudness via the `ebur128` filter. No encoder work, no output —
    /// just decode + meter, capped to `ebur128MeasureCapSeconds`.
    nonisolated static func ebur128MeasureArgs(input: URL) -> [String] {
        [
            "-i", input.path,
            "-t", String(ebur128MeasureCapSeconds),
            "-vn",
            "-map", "0:a",
            "-af", "ebur128",
            "-f", "null", "-"
        ]
    }

    /// Build the `-af` chain for a fixed dB boost. Always followed by
    /// `alimiter` to prevent digital clipping when the boost pushes an
    /// already-loud sample past 0 dBFS. Shared between manual and
    /// auto-normalize paths so the limiter ceiling stays in one place.
    nonisolated static func gainFilter(dB: Double) -> String {
        // Manual cases pass whole-number dB; the auto-normalize path
        // pre-rounds to one decimal. Print without trailing zero noise.
        let asInt = Int(dB)
        let formatted = Double(asInt) == dB ? "\(asInt)" : "\(dB)"
        return "volume=\(formatted)dB,alimiter=limit=0.97"
    }

    /// Deprecated alias — keep the old `Int`-only entry point for the
    /// existing test surface. New code should call `gainFilter(dB:)`.
    nonisolated static func manualGainFilter(dB: Int) -> String {
        gainFilter(dB: Double(dB))
    }

    nonisolated static func phase2Args(
        intermediatesListURL: URL, metaURL: URL, coverURL: URL?, outputURL: URL
    ) -> [String] {
        // `+genpts` smooths the 1-sample concat gap that mp4 intermediates
        // with edit-lists occasionally introduce. Not needed for the
        // remux path (sources have already-good timestamps).
        concatToMP4Args(
            listURL: intermediatesListURL,
            metaURL: metaURL,
            coverURL: coverURL,
            outputURL: outputURL,
            extraFflags: "genpts"
        )
    }

    /// Shared body for remuxArgs/phase2Args. Both run a `-c:a copy`
    /// concat over a list of files plus an ffmetadata chapter file plus
    /// an optional cover image.
    private nonisolated static func concatToMP4Args(
        listURL: URL, metaURL: URL, coverURL: URL?, outputURL: URL, extraFflags: String?
    ) -> [String] {
        let fflags = extraFflags.map { "+fastseek+\($0)" } ?? "+fastseek"
        var args: [String] = [
            "-fflags", fflags,
            "-avoid_negative_ts", "make_zero",
            "-f", "concat", "-safe", "0",
            "-i", listURL.path,
            "-i", metaURL.path
        ]
        if let cover = coverURL { args += ["-i", cover.path] }
        args += ["-map", "0:a", "-map_metadata", "1", "-map_chapters", "1"]
        if coverURL != nil {
            args += coverMappingArgs()
        }
        args += [
            "-c:a", "copy",
            "-threads", "0",
            "-movflags", "+faststart",
            "-f", "mp4",
            outputURL.path
        ]
        return args
    }

    /// Parse the integrated-loudness value from an `ebur128` filter's
    /// summary block. The block ends with lines like:
    ///
    ///     Integrated loudness:
    ///       I:         -18.4 LUFS
    ///       Threshold: -29.3 LUFS
    ///
    /// Returns nil on malformed input or when ffmpeg printed `-inf`
    /// (i.e. silent stream).
    nonisolated static func parseEbur128IntegratedLUFS(_ stderr: String) -> Double? {
        // Find the "Integrated loudness:" section header and then the
        // first `I:   <value> LUFS` line beneath it. We anchor on the
        // header so we don't accidentally pick up the per-frame
        // streaming-style "I: …" lines ffmpeg emits during the run.
        guard let headerRange = stderr.range(of: "Integrated loudness:") else { return nil }
        let tail = stderr[headerRange.upperBound...]
        let pattern = /I:\s*(-?\d+(?:\.\d+)?)\s*LUFS/
        guard let match = tail.firstMatch(of: pattern) else { return nil }
        return Double(match.output.1)
    }

    /// Duration-weighted linear-domain average of per-chapter
    /// integrated loudness values. ebur128's `I` is reported in LUFS
    /// (dBFS-aligned log scale); we exponentiate to linear power, take
    /// the weighted mean, then convert back. Reasonable approximation
    /// of book-level integrated loudness for speech content.
    ///
    /// Returns nil for empty input or when all chapters are silent.
    nonisolated static func combineLoudness(
        chapterIs: [Double],
        durations: [TimeInterval]
    ) -> Double? {
        precondition(chapterIs.count == durations.count,
                     "loudness and duration arrays must have the same length")
        guard !chapterIs.isEmpty else { return nil }

        let totalDuration = durations.reduce(0, +)
        guard totalDuration > 0 else { return nil }

        // LUFS → linear (relative) power. K-weighted reference power is
        // arbitrary for this purpose; only ratios matter.
        var weightedPowerSum = 0.0
        for (lufs, d) in zip(chapterIs, durations) where d > 0 && lufs.isFinite {
            // power = 10^(LUFS/10). The +/- offset constants don't
            // matter; we cancel them out on the inverse.
            let power = pow(10.0, lufs / 10.0)
            weightedPowerSum += power * d
        }
        guard weightedPowerSum > 0 else { return nil }
        let avgPower = weightedPowerSum / totalDuration
        return 10.0 * log10(avgPower)
    }

    /// Target integrated loudness in LUFS. Industry audiobook standard
    /// (Apple Books / Audible). Manual boosts ignore this.
    nonisolated static let autoNormalizeTargetLUFS: Double = -16.0

    /// Bound the auto-normalize gain to a sane range so a wildly-off
    /// measurement (e.g. a silent chapter) can't trash the mix.
    nonisolated static let autoNormalizeGainBounds: ClosedRange<Double> = -6.0 ... 20.0

    private nonisolated static func coverMappingArgs() -> [String] {
        [
            "-map", "2:v",
            "-c:v", "mjpeg",
            "-disposition:v:0", "attached_pic",
            "-metadata:s:v", "title=Album cover",
            "-metadata:s:v", "comment=Cover (front)"
        ]
    }

    // MARK: - Static helpers (used at enqueue time, before any job exists)

    /// True when every source file already uses a codec/sample-rate/channel
    /// layout that MP4 supports natively and the user hasn't asked for a
    /// specific output bitrate.
    public nonisolated static func canRemux(chapters: [Chapter], settings: EncodeSettings) -> Bool {
        guard settings.bitrate == .source else { return false }
        // Any gain adjustment requires re-encoding — you can't alter
        // samples and `-c:a copy` at the same time.
        guard settings.gainBoost == .off else { return false }
        guard let first = chapters.first, first.codec.isMP4RemuxFriendly else { return false }
        // Codec equality also covers AAC profile: CoreMedia reports LC,
        // HE, and HEv2 as distinct FourCCs, so a mixed-profile book can
        // never sneak through as "uniform AAC".
        return chapters.dropFirst().allSatisfy {
            $0.codec == first.codec
                && $0.sampleRate == first.sampleRate
                && $0.channels == first.channels
        }
    }

    /// True when ImageIO can identify `data` as an image with at least
    /// one frame. Used to vet remote cover bytes before ffmpeg sees them.
    public nonisolated static func isDecodableImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }

    /// Rough upper bound on the bytes an encode will write. The re-encode
    /// path stores per-chapter intermediates AND the final concat before
    /// the partial-file rename, so it needs ~2× the payload; remux writes
    /// the payload once. Both get headroom for container overhead.
    public nonisolated static func estimatedRequiredBytes(
        chapters: [Chapter], settings: EncodeSettings
    ) -> Int64 {
        let kbps = resolveBitrateKbps(chapters: chapters, settings: settings)
        let totalSeconds = chapters.reduce(0.0) { $0 + $1.duration }
        let payloadBytes = totalSeconds * Double(kbps) * 1000 / 8
        let factor = canRemux(chapters: chapters, settings: settings) ? 1.2 : 2.4
        return Int64((payloadBytes * factor).rounded(.up))
    }

    public nonisolated static func resolveBitrate(chapters: [Chapter], settings: EncodeSettings) -> String {
        "\(resolveBitrateKbps(chapters: chapters, settings: settings))k"
    }

    /// The typed value behind `resolveBitrate` — ffmpeg's "64k" spelling
    /// is applied only at the argument boundary so numeric consumers
    /// (disk-space estimate) don't have to reverse-parse it.
    public nonisolated static func resolveBitrateKbps(chapters: [Chapter], settings: EncodeSettings) -> Int {
        if let fixed = settings.bitrate.kbps { return fixed }
        let total = chapters.reduce(0.0) { $0 + $1.duration }
        let weighted = chapters.reduce(0.0) {
            $0 + Double($1.sourceBitrate) * $1.duration
        }
        guard total > 0, weighted > 0 else { return 64 }
        let avgKbps = Int((weighted / total / 1000).rounded())
        let steps = [32, 48, 64, 80, 96, 112, 128, 160, 192, 256, 320]
        return steps.min(by: { abs($0 - avgKbps) < abs($1 - avgKbps) }) ?? 64
    }

    /// Apply the user's `filenameTemplate` to a base directory and metadata.
    /// Used at enqueue time to compute `plannedOutputURL` before any encode
    /// has run — this is what we surface in the queue UI.
    public nonisolated static func resolveOutputURL(in base: URL, metadata: BookMetadata,
                                                    template: String) -> URL
    {
        var path = template
        let tokens: [(String, String)] = [
            ("{title}", metadata.title),
            ("{author}", metadata.author),
            ("{series}", metadata.series),
            ("{year}", metadata.year)
        ]
        for (token, value) in tokens {
            path = path.replacingOccurrences(of: token, with: sanitize(value))
        }
        return base.appendingPathComponent(path)
    }

    /// Make a metadata value safe as one path component. Besides the
    /// usual illegal characters, `.` / `..` are directory references and
    /// a leading dot hides the file — an author of `..` would otherwise
    /// resolve to `base/../Title/Title.m4b` and escape the chosen root.
    nonisolated static func sanitize(_ s: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var cleaned = s.components(separatedBy: illegal).joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
        if cleaned == "." || cleaned == ".." { return "_" }
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}
