import XCTest
@testable import ForgeCore

/// Tests for the pure helpers that drive the parallel-encode pipeline:
/// concat-list-of-intermediates, the two arg builders, the
/// `ProgressAggregator` actor, and the `ConcurrencyLimiter` actor.
final class ParallelEncodeTests: XCTestCase {
    // MARK: - ChapterBuilder.concatList(forIntermediates:)

    func test_concatListForIntermediates_emitsOneFilePerURL() {
        // Arrange
        let urls = [
            URL(fileURLWithPath: "/tmp/intermediates/chapter-00000.m4a"),
            URL(fileURLWithPath: "/tmp/intermediates/chapter-00001.m4a")
        ]

        // Act
        let list = ChapterBuilder.concatList(forIntermediates: urls)

        // Assert
        XCTAssertEqual(
            list,
            "file '/tmp/intermediates/chapter-00000.m4a'\nfile '/tmp/intermediates/chapter-00001.m4a'\n"
        )
    }

    func test_concatListForIntermediates_escapesSingleQuotes() {
        // Arrange — workspace path with an apostrophe (the only ffmpeg
        // concat-demuxer quoting hazard).
        let urls = [URL(fileURLWithPath: "/Users/Don't/intermediates/chapter-00000.m4a")]

        // Act
        let list = ChapterBuilder.concatList(forIntermediates: urls)

        // Assert
        XCTAssertEqual(list, "file '/Users/Don'\\''t/intermediates/chapter-00000.m4a'\n")
    }

    // MARK: - phase1Args

    func test_phase1Args_pinsCodecAndStreamLayout() {
        // Arrange
        let input = URL(fileURLWithPath: "/src/chapter.mp3")
        let output = URL(fileURLWithPath: "/work/intermediates/chapter-00000.m4a")

        // Act
        let args = EncodeJob.phase1Args(
            input: input,
            output: output,
            bitrate: "64k",
            sampleRate: 44100,
            channels: 2
        )

        // Assert — codec, bitrate, sample rate and channel count are all
        // explicit so every intermediate has byte-compatible streams.
        XCTAssertTrue(args.contains("-vn"))
        XCTAssertEqual(args[adjacent: "-c:a"], "libfdk_aac")
        XCTAssertEqual(args[adjacent: "-b:a"], "64k")
        XCTAssertEqual(args[adjacent: "-ar"], "44100")
        XCTAssertEqual(args[adjacent: "-ac"], "2")
        XCTAssertEqual(args[adjacent: "-profile:a"], "aac_low")
        XCTAssertEqual(args[adjacent: "-f"], "mp4")
        XCTAssertEqual(args.last, output.path)
    }

    func test_phase1Args_capsPerProcessThreadsToOne() {
        // Arrange / Act — per-chunk encoders use one thread each: `-threads
        // 0` would make every ffmpeg grab every core and fight the
        // chapter fan-out.
        let args = EncodeJob.phase1Args(
            input: URL(fileURLWithPath: "/x.mp3"),
            output: URL(fileURLWithPath: "/y.m4a"),
            bitrate: "64k",
            sampleRate: 44100,
            channels: 2
        )

        // Assert
        XCTAssertEqual(args[adjacent: "-threads"], "1")
    }

    // MARK: - phase2Args

    func test_phase2Args_usesCopyCodecAndPicksUpChaptersAndCover() {
        // Arrange
        let intermediates = URL(fileURLWithPath: "/work/intermediates.txt")
        let meta = URL(fileURLWithPath: "/work/ffmetadata.txt")
        let cover = URL(fileURLWithPath: "/work/cover.jpg")
        let out = URL(fileURLWithPath: "/work/out.m4b.partial")

        // Act
        let args = EncodeJob.phase2Args(
            intermediatesListURL: intermediates,
            metaURL: meta,
            coverURL: cover,
            outputURL: out
        )

        // Assert — no re-encode in phase 2
        XCTAssertEqual(args[adjacent: "-c:a"], "copy")
        // Chapters from the ffmetadata input
        XCTAssertEqual(args[adjacent: "-map_chapters"], "1")
        // Cover muxed as attached_pic
        XCTAssertEqual(args[adjacent: "-disposition:v:0"], "attached_pic")
        // genpts guards against 1-sample concat gaps at intermediate joins
        XCTAssertEqual(args[adjacent: "-fflags"], "+fastseek+genpts")
    }

    func test_phase2Args_omitsCoverMappingWhenAbsent() {
        // Arrange / Act — no cover
        let args = EncodeJob.phase2Args(
            intermediatesListURL: URL(fileURLWithPath: "/work/intermediates.txt"),
            metaURL: URL(fileURLWithPath: "/work/ffmetadata.txt"),
            coverURL: nil,
            outputURL: URL(fileURLWithPath: "/work/out.m4b.partial")
        )

        // Assert — no video stream mapping when there's no cover input
        XCTAssertFalse(args.contains("attached_pic"))
        XCTAssertFalse(args.contains("mjpeg"))
        // The audio map is still there
        XCTAssertTrue(args.contains("0:a"))
    }

    // MARK: - ProgressAggregator

    func test_progressAggregator_sumsAcrossChunks() async {
        // Arrange — three 60s chunks totalling 180s
        let aggregator = ProgressAggregator(chunkDurations: [60, 60, 60])

        // Act — report partial progress on each
        await aggregator.report(chunk: 0, seconds: 30)
        await aggregator.report(chunk: 1, seconds: 30)

        // Assert — 60 of 180 done; phase1 caps the bar at 0.95
        let frac = await aggregator.phase1Fraction
        XCTAssertEqual(frac, (60.0 / 180.0) * 0.95, accuracy: 0.001)
    }

    func test_progressAggregator_ignoresOutOfRangeChunkIndex() async {
        // Arrange — only one chunk registered, but a stale report claims
        // a chunk index that doesn't exist.
        let aggregator = ProgressAggregator(chunkDurations: [10])

        // Act
        await aggregator.report(chunk: 5, seconds: 5)

        // Assert — out-of-range silently ignored; nothing added.
        let frac = await aggregator.phase1Fraction
        XCTAssertEqual(frac, 0)
    }

    func test_progressAggregator_clampsPerChunkAndCapsPhase1Ceiling() async {
        // Arrange — one chunk wildly over-reports, another only partially
        // done. The over-reporter must clamp to its own duration (10s),
        // not pull the bar over 100%. And the aggregate stays ≤ 0.95.
        let aggregator = ProgressAggregator(chunkDurations: [10, 10, 10])

        // Act
        await aggregator.report(chunk: 0, seconds: 9999) // way over its 10s
        await aggregator.report(chunk: 1, seconds: 5) // half done
        // chunk 2 not reported

        // Assert — clamped sum = 10 + 5 = 15 out of 30 total = 0.5,
        // scaled by phase-1 ceiling 0.95 = 0.475.
        let frac = await aggregator.phase1Fraction
        XCTAssertEqual(frac, (15.0 / 30.0) * 0.95, accuracy: 0.001)
    }

    func test_progressAggregator_neverExceedsPhase1Ceiling_whenAllOverReport() async {
        // Arrange — every chunk over-reports
        let aggregator = ProgressAggregator(chunkDurations: [30, 30, 30])

        // Act
        await aggregator.report(chunk: 0, seconds: 1000)
        await aggregator.report(chunk: 1, seconds: 1000)
        await aggregator.report(chunk: 2, seconds: 1000)

        // Assert
        let frac = await aggregator.phase1Fraction
        XCTAssertEqual(frac, 0.95, accuracy: 0.001)
    }

    func test_progressAggregator_keepsMaxOfRepeatedReports() async {
        // Arrange — ffmpeg can report time= going backwards briefly when
        // a B-frame batch flushes. Aggregator keeps the max so the bar
        // is monotonic.
        let aggregator = ProgressAggregator(chunkDurations: [60])

        // Act
        await aggregator.report(chunk: 0, seconds: 40)
        await aggregator.report(chunk: 0, seconds: 30) // older / smaller
        await aggregator.report(chunk: 0, seconds: 50) // newer / bigger

        // Assert
        let frac = await aggregator.phase1Fraction
        XCTAssertEqual(frac, (50.0 / 60.0) * 0.95, accuracy: 0.001)
    }

    // MARK: - ConcurrencyLimiter

    func test_concurrencyLimiter_neverExceedsCap() async {
        // Arrange — cap of 4, fire 20 tasks that hold the slot briefly.
        // The test observes concurrency by inc/dec'ing its own counter
        // inside the held region, so ConcurrencyLimiter doesn't need to
        // expose any in-flight count purely for tests.
        let limiter = ConcurrencyLimiter(max: 4)
        let watcher = ConcurrencyWatcher()

        // Act
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 20 {
                group.addTask {
                    await limiter.acquire()
                    await watcher.entered()
                    try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
                    await watcher.left()
                    await limiter.release()
                }
            }
        }

        // Assert — never more than the cap simultaneously
        let observed = await watcher.maxConcurrent
        XCTAssertLessThanOrEqual(observed, 4, "\(observed) tasks held the limiter at once with a cap of 4")
        XCTAssertGreaterThan(observed, 0, "no task ever acquired the limiter")
    }
}

/// Test-side counter for the cap invariant. Each task `entered`s on
/// acquire and `left`s on release; `maxConcurrent` records the peak.
private actor ConcurrencyWatcher {
    private var current: Int = 0
    private(set) var maxConcurrent: Int = 0

    func entered() {
        current += 1
        if current > maxConcurrent { maxConcurrent = current }
    }

    func left() {
        current -= 1
    }
}
