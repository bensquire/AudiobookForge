import Foundation
import ImageIO
import os

/// Value-typed description of one encode job. Decoupling this from the live
/// `AudiobookProject` lets the queue snapshot the user's draft at enqueue
/// time and run it later without worrying about mutation.
public struct EncodeSpec: Sendable {
    public var chapters: [Chapter]
    public var metadata: BookMetadata
    public var settings: EncodeSettings
    public var outputURL: URL // final on-disk destination (already deduped)

    public var totalDuration: TimeInterval {
        chapters.reduce(0) { $0 + $1.duration }
    }
}

/// Orchestrates a single conversion run. Immutable aside from the cancel
/// token; progress goes out via a `@Sendable` callback so the caller
/// (live UI or queue item) decides where to surface it. Not actor-bound:
/// it's shared with the CLI, and its file I/O (including the `defer`
/// cleanup of every intermediate) has no business on the main thread.
public final class EncodeJob: Sendable {
    public let spec: EncodeSpec
    public let cancelToken = CancelToken()

    /// `frac` is 0…1. `status` is a short human-readable label like
    /// "Encoding chapter 3/12…" or "Remuxing (no re-encode)…". Called
    /// from whatever thread produced the progress — hop to the main
    /// actor yourself if you're driving UI.
    private let onProgress: @Sendable (Double, String) -> Void

    public init(
        spec: EncodeSpec,
        onProgress: @escaping @Sendable (Double, String) -> Void = { _, _ in }
    ) {
        self.spec = spec
        self.onProgress = onProgress
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
        // The GUI can't enqueue an empty draft, but `EncodeJob` is public
        // and the CLI builds specs itself; `spec.chapters[0]` below would
        // trap on an empty one.
        guard !spec.chapters.isEmpty else { throw EncodeError.noChapters }

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

        // The callback runs on the pipe-reader queue; a plain captured
        // `var` there is a data race under strict concurrency.
        let lastPct = OSAllocatedUnfairLock<Int>(initialState: -1)
        try await FFmpegRunner.run(
            arguments: args,
            totalDuration: spec.totalDuration,
            onProgress: { frac, _ in
                let pct = Int(frac * 100)
                let changed = lastPct.withLock { current -> Bool in
                    guard pct != current else { return false }
                    current = pct
                    return true
                }
                guard changed else { return }
                self.onProgress(frac, "Remuxing… \(pct)%")
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
            // Chapters finish out of order under the limiter; count
            // completions rather than reporting `index + 1`, which
            // would make the bar jump backwards.
            let measured = OSAllocatedUnfairLock<Int>(initialState: 0)
            let measurements: [Double?] = try await withThrowingTaskGroup(
                of: (Int, Double?).self
            ) { group in
                for (index, chapter) in spec.chapters.enumerated() {
                    let args = Self.ebur128MeasureArgs(input: chapter.sourceURL)
                    let token = tokens[index]
                    group.addTask {
                        await limiter.acquire()
                        defer { Task { await limiter.release() } }
                        let stderr = await FFmpegRunner.captureStderr(
                            arguments: args, cancelToken: token
                        )
                        let lufs = stderr.flatMap(Self.parseEbur128IntegratedLUFS)
                        let done = measured.withLock { count -> Int in
                            count += 1
                            return count
                        }
                        self.onProgress(
                            Double(done) / Double(totalChapters) * 0.1,
                            "Measuring loudness — \(done)/\(totalChapters) chapters…"
                        )
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
                // Nothing measurable (ffmpeg missing, every chapter
                // silent/undecodable). Encoding anyway would report
                // "Done" on a book that was never normalized — the user
                // asked for a specific loudness, so fail loudly instead.
                throw EncodeError.loudnessMeasurementFailed
            }

            return Self.gainFilter(dB: Self.gainOffsetDB(from: bookI))
        }
    }

    /// Compute the per-book gain in dB needed to bring `bookLUFS` to the
    /// auto-normalize target, clamped to a sane range and rounded to one
    /// decimal place for clean ffmpeg arg readability.
    static func gainOffsetDB(from bookLUFS: Double) -> Double {
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

                group.addTask {
                    await limiter.acquire()
                    defer { Task { await limiter.release() } }

                    try await FFmpegRunner.run(
                        arguments: args,
                        totalDuration: chapterDuration,
                        onProgress: { frac, _ in
                            let (secs, pct) = Self.phase1ChunkProgress(
                                fraction: frac, chapterDuration: chapterDuration
                            )
                            let changed = lastPct.withLock { current -> Bool in
                                guard pct != current else { return false }
                                current = pct
                                return true
                            }
                            guard changed else { return }
                            Task {
                                await aggregator.report(chunk: index, seconds: secs)
                                let frac = await aggregator.phase1Fraction
                                self.onProgress(
                                    frac,
                                    "Encoding chapter \(index + 1)/\(totalChapters)…"
                                )
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
            return slots.compactMap(\.self)
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
}
