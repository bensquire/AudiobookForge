import Foundation
import ImageIO
import os

/// Value-typed description of one encode job. Decoupling this from the live
/// `AudiobookProject` lets the queue snapshot the user's draft at enqueue
/// time and run it later without worrying about mutation.
public struct EncodeSpec {
    public var chapters: [Chapter]
    public var metadata: BookMetadata
    public var settings: EncodeSettings
    public var outputURL: URL // final on-disk destination (already deduped)

    public var totalDuration: TimeInterval {
        chapters.reduce(0) { $0 + $1.duration }
    }
}

/// Orchestrates a single conversion run. Stateless aside from the cancel
/// token; progress goes out via callback so the caller (live UI or queue
/// item) can decide how to surface it.
@MainActor
public final class EncodeJob {
    public let spec: EncodeSpec
    public let cancelToken = CancelToken()

    /// `frac` is 0…1. `status` is a short human-readable label like
    /// "Encoding chapter 3/12…" or "Remuxing (no re-encode)…".
    public var onProgress: (Double, String) -> Void = { _, _ in }

    public init(spec: EncodeSpec) {
        self.spec = spec
    }

    /// Runs the encode. Returns the URL the file was actually written to
    /// (may differ from `spec.outputURL` if a late collision forced a
    /// rename). Throws on failure or cancellation.
    @discardableResult
    public func run() async throws -> URL {
        onProgress(0, "Preparing…")
        return try await runInner()
    }

    private func runInner() async throws -> URL {
        // Don't waste preflight work (disk-space stat, directory
        // creation) on a job that was cancelled while queued.
        if cancelToken.isCancelled { throw FFmpegRunner.RunError.cancelled }

        // Defensive: re-resolve in case another finished item dropped a
        // file at this path between enqueue and now.
        let finalURL = OutputPathResolver.uniqueURL(for: spec.outputURL)
        let parent = finalURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parent, withIntermediateDirectories: true
            )
        } catch {
            throw EncodeError.outputUnavailable(parent.path, error.localizedDescription)
        }

        // Fail fast on a full disk instead of surfacing a cryptic ffmpeg
        // write error 45 minutes into a long encode.
        let required = Self.estimatedRequiredBytes(
            chapters: spec.chapters, settings: spec.settings
        )
        if let available = try? parent.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage,
            available < required
        {
            throw EncodeError.insufficientDiskSpace(required: required, available: available)
        }

        // Encode to a sibling `.partial` then rename — if we crash or get
        // cancelled the user is never left with a stub at the final path.
        let partialURL = parent.appendingPathComponent(
            finalURL.lastPathComponent + ".partial"
        )
        try? FileManager.default.removeItem(at: partialURL)

        let workDir = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: finalURL, create: true
        )
        defer { try? FileManager.default.removeItem(at: workDir) }

        let metaURL = workDir.appendingPathComponent("ffmetadata.txt")
        try ChapterBuilder.ffmetadata(for: spec.chapters, metadata: spec.metadata)
            .write(to: metaURL, atomically: true, encoding: .utf8)

        var coverURL: URL?
        if let coverData = spec.metadata.coverData {
            // The bytes may have come from a remote metadata API. Refuse
            // anything ImageIO can't identify as an image before handing
            // it to ffmpeg's decoders — smaller parsing surface, and the
            // user gets a clear error instead of an ffmpeg stderr dump.
            guard Self.isDecodableImage(coverData) else {
                throw EncodeError.invalidCoverImage
            }
            let url = workDir.appendingPathComponent("cover.jpg")
            try coverData.write(to: url)
            coverURL = url
        }

        do {
            if Self.canRemux(chapters: spec.chapters, settings: spec.settings) {
                onProgress(0, "Remuxing (no re-encode)…")
                try await runRemuxOnePass(
                    workDir: workDir,
                    metaURL: metaURL,
                    coverURL: coverURL,
                    partialURL: partialURL
                )
            } else {
                onProgress(0, "Encoding audio…")
                try await runReencodeParallel(
                    workDir: workDir,
                    metaURL: metaURL,
                    coverURL: coverURL,
                    partialURL: partialURL
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            throw error
        }

        // Re-resolve once more — another finished item may have landed at
        // this path between our enqueue-time resolve and now.
        let destination = OutputPathResolver.uniqueURL(for: finalURL)
        do {
            try FileManager.default.moveItem(at: partialURL, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            throw error
        }

        onProgress(1, "Done")
        return destination
    }

    // MARK: - Remux path (sources already AAC — single ffmpeg with -c:a copy)

    private func runRemuxOnePass(
        workDir: URL, metaURL: URL, coverURL: URL?, partialURL: URL
    ) async throws {
        let concatURL = workDir.appendingPathComponent("concat.txt")
        try ChapterBuilder.concatList(for: spec.chapters)
            .write(to: concatURL, atomically: true, encoding: .utf8)

        let args = Self.remuxArgs(
            concatListURL: concatURL,
            metaURL: metaURL,
            coverURL: coverURL,
            outputURL: partialURL
        )

        var lastPct = -1
        try await FFmpegRunner.run(
            arguments: args,
            totalDuration: spec.totalDuration,
            onProgress: { [weak self] frac, _ in
                let pct = Int(frac * 100)
                guard pct != lastPct else { return }
                lastPct = pct
                Task { @MainActor in
                    self?.onProgress(frac, "Remuxing… \(pct)%")
                }
            },
            cancelToken: cancelToken
        )
    }

    // MARK: - Phase 0 — gain filter resolution

    /// Returns the `-af` filter chain to apply to each chapter, or nil
    /// when `gainBoost == .off`. For `.autoNormalize` runs a parallel
    /// ebur128 measurement pass first.
    private func resolvePhase0GainFilter(
        limiter: ConcurrencyLimiter,
        tokens: [CancelToken]
    ) async throws -> String? {
        switch spec.settings.gainBoost {
        case .off:
            return nil

        case .dB3, .dB6, .dB9, .dB12:
            return Self.gainFilter(dB: Double(spec.settings.gainBoost.manualDB!))

        case .autoNormalize:
            onProgress(0, "Measuring loudness…")
            let totalChapters = spec.chapters.count
            let measurements: [Double?] = try await withThrowingTaskGroup(
                of: (Int, Double?).self
            ) { group in
                for (index, chapter) in spec.chapters.enumerated() {
                    let args = Self.ebur128MeasureArgs(input: chapter.sourceURL)
                    let token = tokens[index]
                    group.addTask { [weak self] in
                        await limiter.acquire()
                        defer { Task { await limiter.release() } }
                        let stderr = await FFmpegRunner.captureStderr(
                            arguments: args, cancelToken: token
                        )
                        let lufs = stderr.flatMap(Self.parseEbur128IntegratedLUFS)
                        await MainActor.run {
                            self?.onProgress(
                                Double(index + 1) / Double(totalChapters) * 0.1,
                                "Measuring loudness — chapter \(index + 1)/\(totalChapters)…"
                            )
                        }
                        if token.isCancelled { throw FFmpegRunner.RunError.cancelled }
                        return (index, lufs)
                    }
                }
                var slots = [Double?](repeating: nil, count: totalChapters)
                for try await (index, lufs) in group {
                    slots[index] = lufs
                }
                return slots
            }

            let valid = zip(measurements, spec.chapters).compactMap { pair -> (Double, TimeInterval)? in
                guard let lufs = pair.0 else { return nil }
                return (lufs, pair.1.duration)
            }
            guard !valid.isEmpty,
                  let bookI = Self.combineLoudness(
                      chapterIs: valid.map(\.0),
                      durations: valid.map(\.1)
                  )
            else {
                // Couldn't measure — bail to "no gain" rather than guess.
                return nil
            }

            return Self.gainFilter(dB: Self.gainOffsetDB(from: bookI))
        }
    }

    /// Compute the per-book gain in dB needed to bring `bookLUFS` to the
    /// auto-normalize target, clamped to a sane range and rounded to one
    /// decimal place for clean ffmpeg arg readability.
    nonisolated static func gainOffsetDB(from bookLUFS: Double) -> Double {
        let raw = autoNormalizeTargetLUFS - bookLUFS
        let clamped = max(
            autoNormalizeGainBounds.lowerBound,
            min(autoNormalizeGainBounds.upperBound, raw)
        )
        return (clamped * 10).rounded() / 10
    }

    // MARK: - Re-encode path (parallel chapter encode + lossless concat)

    private func runReencodeParallel(
        workDir: URL, metaURL: URL, coverURL: URL?, partialURL: URL
    ) async throws {
        let intermediatesDir = workDir.appendingPathComponent(
            "intermediates", isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: intermediatesDir, withIntermediateDirectories: true
        )

        // Pin every chunk to the same codec params so the final
        // `-c:a copy` concat is bitstream-identical at boundaries.
        let pivot = spec.chapters[0]
        let sampleRate = pivot.sampleRate > 0 ? Int(pivot.sampleRate) : 44100
        let channels = pivot.channels > 0 ? pivot.channels : 2
        let bitrate = Self.resolveBitrate(chapters: spec.chapters, settings: spec.settings)

        let totalChapters = spec.chapters.count
        let cap = min(totalChapters, max(2, ProcessInfo.processInfo.activeProcessorCount), 12)
        let limiter = ConcurrencyLimiter(max: cap)
        let aggregator = ProgressAggregator(
            chunkDurations: spec.chapters.map(\.duration)
        )

        // Pre-allocate per-chunk tokens so cancel() lands even if a task
        // hasn't started yet (it'll throw .cancelled on first acquire()).
        // makeChild ties each to the parent at birth — a child created
        // after the parent was cancelled is born cancelled.
        let tokens = (0 ..< totalChapters).map { _ in cancelToken.makeChild() }

        // Phase 0 — resolve the gain filter for this encode. Manual
        // boost is a simple synthesis from the picked dB value; auto-
        // normalize parallel-measures every chapter's integrated
        // loudness, combines, and computes the offset to the target.
        let gainFilter = try await resolvePhase0GainFilter(limiter: limiter, tokens: tokens)

        let intermediateURLs: [URL] = try await withThrowingTaskGroup(
            of: (Int, URL).self
        ) { group in
            for (index, chapter) in spec.chapters.enumerated() {
                let intermediate = intermediatesDir.appendingPathComponent(
                    String(format: "chapter-%05d.m4a", index)
                )
                let args = Self.phase1Args(
                    input: chapter.sourceURL,
                    output: intermediate,
                    bitrate: bitrate,
                    sampleRate: sampleRate,
                    channels: channels,
                    gainFilter: gainFilter
                )
                let chapterDuration = chapter.duration
                let token = tokens[index]
                // Per-chunk rounded-percent gate. ffmpeg emits progress
                // ~10 Hz; the UI only cares about integer-percent steps.
                // Bailing here avoids ~99% of Task spawns and actor hops
                // for what would have been no-op UI updates.
                let lastPct = OSAllocatedUnfairLock<Int>(initialState: -1)

                group.addTask { [weak self] in
                    await limiter.acquire()
                    defer { Task { await limiter.release() } }

                    try await FFmpegRunner.run(
                        arguments: args,
                        totalDuration: chapterDuration,
                        onProgress: { secs, _ in
                            let pct = chapterDuration > 0
                                ? Int((secs / chapterDuration) * 100)
                                : 0
                            let changed = lastPct.withLock { current -> Bool in
                                guard pct != current else { return false }
                                current = pct
                                return true
                            }
                            guard changed else { return }
                            Task {
                                await aggregator.report(chunk: index, seconds: secs)
                                let frac = await aggregator.phase1Fraction
                                await MainActor.run {
                                    self?.onProgress(
                                        frac,
                                        "Encoding chapter \(index + 1)/\(totalChapters)…"
                                    )
                                }
                            }
                        },
                        cancelToken: token
                    )
                    return (index, intermediate)
                }
            }

            var slots = [URL?](repeating: nil, count: totalChapters)
            for try await (index, url) in group {
                slots[index] = url
            }
            return slots.compactMap { $0 }
        }

        // Phase 2 — concat-copy the intermediates into the final .m4b
        onProgress(0.96, "Finalising…")
        let intermediatesListURL = workDir.appendingPathComponent("intermediates.txt")
        try ChapterBuilder.concatList(forIntermediates: intermediateURLs)
            .write(to: intermediatesListURL, atomically: true, encoding: .utf8)

        let args = Self.phase2Args(
            intermediatesListURL: intermediatesListURL,
            metaURL: metaURL,
            coverURL: coverURL,
            outputURL: partialURL
        )
        try await FFmpegRunner.run(
            arguments: args,
            totalDuration: 0,
            onProgress: { _, _ in },
            cancelToken: cancelToken
        )
    }

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

    private nonisolated static func sanitize(_ s: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return s.components(separatedBy: illegal).joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
    }
}
