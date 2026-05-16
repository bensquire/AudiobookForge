import Foundation

/// Value-typed description of one encode job. Decoupling this from the live
/// `AudiobookProject` lets the queue snapshot the user's draft at enqueue
/// time and run it later without worrying about mutation.
struct EncodeSpec {
    var chapters: [Chapter]
    var metadata: BookMetadata
    var settings: EncodeSettings
    var outputURL: URL // final on-disk destination (already deduped)

    var totalDuration: TimeInterval {
        chapters.reduce(0) { $0 + $1.duration }
    }
}

/// Orchestrates a single conversion run. Stateless aside from the cancel
/// token; progress goes out via callback so the caller (live UI or queue
/// item) can decide how to surface it.
@MainActor
final class EncodeJob {
    let spec: EncodeSpec
    let cancelToken = CancelToken()

    /// `frac` is 0…1. `status` is a short human-readable label like
    /// "Encoding… 42%" or "Remuxing (no re-encode)…".
    var onProgress: (Double, String) -> Void = { _, _ in }

    init(spec: EncodeSpec) {
        self.spec = spec
    }

    /// Runs the encode. Returns the URL the file was actually written to
    /// (may differ from `spec.outputURL` if a late collision forced a
    /// rename). Throws on failure or cancellation.
    @discardableResult
    func run() async throws -> URL {
        onProgress(0, "Preparing…")
        return try await runInner()
    }

    private func runInner() async throws -> URL {
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

        let concatURL = workDir.appendingPathComponent("concat.txt")
        let metaURL = workDir.appendingPathComponent("ffmetadata.txt")

        try ChapterBuilder.concatList(for: spec.chapters)
            .write(to: concatURL, atomically: true, encoding: .utf8)
        try ChapterBuilder.ffmetadata(for: spec.chapters, metadata: spec.metadata)
            .write(to: metaURL, atomically: true, encoding: .utf8)

        var coverURL: URL?
        if let coverData = spec.metadata.coverData {
            let url = workDir.appendingPathComponent("cover.jpg")
            try coverData.write(to: url)
            coverURL = url
        }

        let remux = Self.canRemux(chapters: spec.chapters, settings: spec.settings)
        let startStatus = remux ? "Remuxing (no re-encode)…" : "Encoding audio…"
        onProgress(0, startStatus)

        let bitrate = Self.resolveBitrate(chapters: spec.chapters, settings: spec.settings)

        var args: [String] = [
            "-fflags", "+fastseek",
            "-avoid_negative_ts", "make_zero",
            "-f", "concat",
            "-safe", "0",
            "-i", concatURL.path,
            "-i", metaURL.path
        ]
        if let cover = coverURL { args += ["-i", cover.path] }
        args += ["-map", "0:a", "-map_metadata", "1", "-map_chapters", "1"]
        if coverURL != nil {
            args += [
                "-map", "2:v",
                "-c:v", "mjpeg",
                "-disposition:v:0", "attached_pic",
                "-metadata:s:v", "title=Album cover",
                "-metadata:s:v", "comment=Cover (front)"
            ]
        }
        if remux {
            args += ["-c:a", "copy"]
        } else {
            args += [
                "-c:a", spec.settings.codec.rawValue,
                "-b:a", bitrate
            ]
        }
        args += [
            "-threads", "0",
            "-movflags", "+faststart",
            "-f", "mp4",
            partialURL.path
        ]

        do {
            var lastPct = -1
            try await FFmpegRunner.run(
                arguments: args,
                totalDuration: spec.totalDuration,
                onProgress: { [weak self] frac, _ in
                    let pct = Int(frac * 100)
                    guard pct != lastPct else { return }
                    lastPct = pct
                    Task { @MainActor in
                        self?.onProgress(frac, "Encoding… \(pct)%")
                    }
                },
                cancelToken: cancelToken
            )
        } catch {
            // Clean up the partial file on any failure / cancel so we don't
            // leave half-written `.m4b.partial` artifacts littering the
            // user's output folder.
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

    // MARK: - Static helpers (used at enqueue time, before any job exists)

    /// True when every source file already uses a codec/sample-rate/channel
    /// layout that MP4 supports natively and the user hasn't asked for a
    /// specific output bitrate.
    nonisolated static func canRemux(chapters: [Chapter], settings: EncodeSettings) -> Bool {
        guard settings.bitrate == .source else { return false }
        guard let first = chapters.first, first.codec.isMP4RemuxFriendly else { return false }
        return chapters.dropFirst().allSatisfy {
            $0.codec == first.codec
                && $0.sampleRate == first.sampleRate
                && $0.channels == first.channels
        }
    }

    nonisolated static func resolveBitrate(chapters: [Chapter], settings: EncodeSettings) -> String {
        switch settings.bitrate {
        case .source:
            let total = chapters.reduce(0.0) { $0 + $1.duration }
            let weighted = chapters.reduce(0.0) {
                $0 + Double($1.sourceBitrate) * $1.duration
            }
            guard total > 0, weighted > 0 else { return "64k" }
            let avgKbps = Int((weighted / total / 1000).rounded())
            let steps = [32, 48, 64, 80, 96, 112, 128, 160, 192, 256, 320]
            let snapped = steps.min(by: { abs($0 - avgKbps) < abs($1 - avgKbps) }) ?? 64
            return "\(snapped)k"
        default:
            return settings.bitrate.rawValue
        }
    }

    /// Apply the user's `filenameTemplate` to a base directory and metadata.
    /// Used at enqueue time to compute `plannedOutputURL` before any encode
    /// has run — this is what we surface in the queue UI.
    nonisolated static func resolveOutputURL(in base: URL, metadata: BookMetadata,
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

enum EncodeError: LocalizedError {
    case missingSourceFile(URL)
    case sourceChanged(URL)
    case outputUnavailable(String, String)
    case noOutputDir

    var errorDescription: String? {
        switch self {
        case let .missingSourceFile(url):
            "Source file no longer found: \(url.lastPathComponent). "
                + "Move it back to \(url.deletingLastPathComponent().path) or remove this queue item."
        case let .sourceChanged(url):
            "Source file changed since it was queued: \(url.lastPathComponent). Remove and re-add this item to refresh it."
        case let .outputUnavailable(path, why):
            "Output folder is no longer available (\(path)): \(why). Choose a new output folder and retry."
        case .noOutputDir:
            "No output folder selected."
        }
    }
}
