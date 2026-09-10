import AVFoundation
import XCTest
@testable import ForgeCore

/// End-to-end checks on the two things the encoder must get right with
/// real audio: stitching chapters into one file (order, boundaries, and
/// the actual audio content at each boundary) and gain handling (what
/// the listener hears, measured in LUFS). Every fixture is a generated
/// sine tone with a distinct frequency and known loudness, so both can be
/// verified from the decoded output rather than trusted from metadata.
/// Total runtime is a few seconds — the audio is short by design.
final class AudioPipelineTests: XCTestCase {
    private nonisolated(unsafe) var tmp: URL!

    override func setUp() {
        super.setUp()
        Bundled.setOverrideDirectory(repoBinDir)
        // swiftlint:disable:next force_try
        tmp = try! FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
            create: true
        )
    }

    override func tearDown() {
        Bundled.setOverrideDirectory(nil)
        try? FileManager.default.removeItem(at: tmp)
        super.tearDown()
    }

    // MARK: - Stitching

    /// Three chapters of different lengths and tones, re-encoded. The
    /// output must be one file whose chapter markers sit at the cumulative
    /// durations and whose audio at each marker is that chapter's tone.
    func test_stitch_reencode_ordersChaptersAtCorrectBoundariesWithCorrectAudio() async throws {
        // Arrange
        let plan: [(name: String, seconds: Double, hz: Double)] = [
            ("One", 2.0, 300), ("Two", 3.0, 600), ("Three", 1.5, 1200)
        ]
        var chapters: [Chapter] = []
        for p in plan {
            let wav = tmp.appendingPathComponent("\(p.name).wav")
            try writeSineWav(to: wav, seconds: p.seconds, frequency: p.hz)
            chapters.append(chapter(wav, title: p.name, codec: .pcm, duration: p.seconds))
        }
        let job = EncodeJob(spec: makeSpec(in: tmp, chapters: chapters, bitrate: .k64))

        // Act
        let out = try await job.run()

        // Assert
        try await assertStitched(out, plan: plan)
    }

    /// Same shape through the lossless remux path (AAC sources, "Match
    /// source" bitrate): concat with `-c:a copy` must not shift or
    /// reorder anything either.
    func test_stitch_remux_ordersChaptersAtCorrectBoundariesWithCorrectAudio() async throws {
        // Arrange
        let plan: [(name: String, seconds: Double, hz: Double)] = [
            ("One", 2.0, 300), ("Two", 1.5, 600), ("Three", 1.0, 1200)
        ]
        var chapters: [Chapter] = []
        for p in plan {
            let m4a = try await makeAacFixture(in: tmp, name: p.name, frequency: p.hz, seconds: p.seconds)
            chapters.append(chapter(m4a, title: p.name, codec: .aac, duration: p.seconds))
        }
        let spec = makeSpec(in: tmp, chapters: chapters, bitrate: .source)
        XCTAssertTrue(EncodeJob.canRemux(chapters: chapters, settings: spec.settings), "fixture should remux")
        let job = EncodeJob(spec: spec)

        // Act
        let out = try await job.run()

        // Assert
        try await assertStitched(out, plan: plan)
    }

    /// More chapters than the parallel-encode cap, so several must queue
    /// behind the limiter and finish out of order — the concat still has
    /// to be in chapter order.
    func test_stitch_moreChaptersThanParallelCap_keepsOrder() async throws {
        // Arrange — 16 half-second chapters alternating between two tones.
        let count = 16
        var chapters: [Chapter] = []
        var plan: [(name: String, seconds: Double, hz: Double)] = []
        for i in 0 ..< count {
            let hz: Double = i.isMultiple(of: 2) ? 400 : 1000
            let wav = tmp.appendingPathComponent("c\(i).wav")
            try writeSineWav(to: wav, seconds: 0.5, frequency: hz)
            chapters.append(chapter(wav, title: "Ch \(i + 1)", codec: .pcm, duration: 0.5))
            plan.append(("Ch \(i + 1)", 0.5, hz))
        }
        XCTAssertGreaterThan(count, 12, "must exceed the ConcurrencyLimiter cap to mean anything")
        let job = EncodeJob(spec: makeSpec(in: tmp, chapters: chapters, bitrate: .k64))

        // Act
        let out = try await job.run()

        // Assert — markers only (0.5 s windows are too short for a
        // reliable frequency read at the boundaries), plus a spot check
        // of the audio in the middle of the first, ninth and last chapter.
        let markers = try await loadChapters(AVURLAsset(url: out))
        XCTAssertEqual(markers.map(\.title), plan.map(\.name))
        for (i, marker) in markers.enumerated() {
            XCTAssertEqual(marker.start, Double(i) * 0.5, accuracy: 0.1, "chapter \(i + 1) start")
        }
        for i in [0, 8, 15] {
            let hz = try await dominantFrequency(of: out, start: Double(i) * 0.5 + 0.1, duration: 0.3)
            XCTAssertEqual(hz, plan[i].hz, accuracy: plan[i].hz * 0.05, "audio in chapter \(i + 1)")
        }
    }

    // MARK: - Gain

    func test_gain_off_preservesSourceLoudness() async throws {
        // Arrange
        let wav = tmp.appendingPathComponent("src.wav")
        try writeSineWav(to: wav, seconds: 4.0, frequency: 440, amplitude: 6000)
        let source = try await integratedLoudness(of: wav)
        let job = EncodeJob(spec: makeSpec(
            in: tmp,
            chapters: [chapter(wav, title: "A", codec: .pcm, duration: 4)],
            bitrate: .k64
        ))

        // Act
        let out = try await job.run()

        // Assert — AAC at 64k of a single tone is loudness-transparent.
        let result = try await integratedLoudness(of: out)
        XCTAssertEqual(result, source, accuracy: 0.5)
    }

    func test_gain_manualBoost_raisesLoudnessByExactlyThatMuch() async throws {
        // Arrange — quiet enough (≈ -24 LUFS) that +6 dB stays clear of
        // the limiter, so the delta is the boost and nothing else.
        let wav = tmp.appendingPathComponent("quiet.wav")
        try writeSineWav(to: wav, seconds: 4.0, frequency: 440, amplitude: 3000)
        let source = try await integratedLoudness(of: wav)
        var spec = makeSpec(
            in: tmp,
            chapters: [chapter(wav, title: "A", codec: .pcm, duration: 4)],
            bitrate: .k64
        )
        spec.settings.gainBoost = .dB6
        let job = EncodeJob(spec: spec)

        // Act
        let out = try await job.run()

        // Assert
        let result = try await integratedLoudness(of: out)
        XCTAssertEqual(result, source + 6, accuracy: 0.75)
    }

    func test_gain_manualBoost_limiterStopsClippingOnLoudSource() async throws {
        // Arrange — already loud (≈ -12 LUFS); +12 dB would clip without
        // the limiter. The output must be louder than the source but
        // must not exceed the limiter's ceiling.
        let wav = tmp.appendingPathComponent("loud.wav")
        try writeSineWav(to: wav, seconds: 4.0, frequency: 440)
        let source = try await integratedLoudness(of: wav)
        var spec = makeSpec(
            in: tmp,
            chapters: [chapter(wav, title: "A", codec: .pcm, duration: 4)],
            bitrate: .k64
        )
        spec.settings.gainBoost = .dB12
        let job = EncodeJob(spec: spec)

        // Act
        let out = try await job.run()

        // Assert — a full-scale 440 Hz sine measures around -3 LUFS; the
        // limiter at 0.97 keeps it a hair under that.
        let result = try await integratedLoudness(of: out)
        XCTAssertGreaterThan(result, source + 3)
        XCTAssertLessThan(result, -2.5)
    }

    /// Auto-normalize is a *book-wide* gain, not per chapter: the loud and
    /// quiet chapters must keep their relative levels while the book as a
    /// whole lands on target.
    func test_gain_autoNormalize_appliesOneGainAcrossMixedLoudnessChapters() async throws {
        // Arrange — chapter 1 ≈ -12 LUFS, chapter 2 ≈ -24 LUFS.
        let loud = tmp.appendingPathComponent("loud.wav")
        let quiet = tmp.appendingPathComponent("quiet.wav")
        try writeSineWav(to: loud, seconds: 3.0, frequency: 440, amplitude: 12000)
        try writeSineWav(to: quiet, seconds: 3.0, frequency: 440, amplitude: 3000)
        let loudSource = try await integratedLoudness(of: loud)
        let quietSource = try await integratedLoudness(of: quiet)
        let sourceDelta = loudSource - quietSource
        XCTAssertGreaterThan(sourceDelta, 8, "fixtures should differ by ~12 dB")
        var spec = makeSpec(
            in: tmp,
            chapters: [
                chapter(loud, title: "Loud", codec: .pcm, duration: 3),
                chapter(quiet, title: "Quiet", codec: .pcm, duration: 3)
            ],
            bitrate: .k64
        )
        spec.settings.gainBoost = .autoNormalize
        let job = EncodeJob(spec: spec)

        // Act
        let out = try await job.run()

        // Assert — book on target; chapters still ~12 dB apart.
        let book = try await integratedLoudness(of: out)
        XCTAssertEqual(book, EncodeJob.autoNormalizeTargetLUFS, accuracy: 1.5)
        let outLoud = try await integratedLoudness(of: out, start: 0, duration: 3)
        let outQuiet = try await integratedLoudness(of: out, start: 3, duration: 3)
        XCTAssertEqual(outLoud - outQuiet, sourceDelta, accuracy: 1.0)
    }

    func test_gain_autoIfQuiet_liftsQuietBookButNotLoudOne() async throws {
        // Arrange — two single-chapter books, one each side of the target.
        let quiet = tmp.appendingPathComponent("quiet.wav")
        let loud = tmp.appendingPathComponent("loud.wav")
        try writeSineWav(to: quiet, seconds: 3.0, frequency: 440, amplitude: 2000)
        try writeSineWav(to: loud, seconds: 3.0, frequency: 440, amplitude: 12000)
        let loudSource = try await integratedLoudness(of: loud)
        var quietSpec = makeSpec(
            in: tmp,
            chapters: [chapter(quiet, title: "Q", codec: .pcm, duration: 3)],
            bitrate: .k64,
            title: "Quiet Book"
        )
        var loudSpec = makeSpec(
            in: tmp,
            chapters: [chapter(loud, title: "L", codec: .pcm, duration: 3)],
            bitrate: .k64,
            title: "Loud Book"
        )
        quietSpec.settings.gainBoost = .autoIfQuiet
        loudSpec.settings.gainBoost = .autoIfQuiet

        // Act
        let quietOut = try await EncodeJob(spec: quietSpec).run()
        let loudOut = try await EncodeJob(spec: loudSpec).run()

        // Assert
        let quietResult = try await integratedLoudness(of: quietOut)
        let loudResult = try await integratedLoudness(of: loudOut)
        XCTAssertEqual(quietResult, EncodeJob.autoNormalizeTargetLUFS, accuracy: 1.5)
        XCTAssertEqual(loudResult, loudSource, accuracy: 0.75)
    }

    // MARK: - Real MP3 input (the app's bread and butter)

    /// Committed LAME-encoded MP3s with ID3 tags, run through the same
    /// probe the drag-drop import uses and then stitched. Checks that the
    /// MP3 decoder in the bundled ffmpeg, tag reading, bitrate detection,
    /// and the re-encode path all line up on a real-world input format.
    func test_mp3Chapters_probeAndStitch() async throws {
        // Arrange — tones and durations must match Fixtures/README.md.
        let plan: [(name: String, seconds: Double, hz: Double)] = [
            ("Chapter One", 2.0, 300), ("Chapter Two", 2.0, 600), ("Chapter Three", 2.0, 1200)
        ]
        var chapters: [Chapter] = []
        for (i, p) in plan.enumerated() {
            let url = fixturesDir.appendingPathComponent("mp3/chapter\(i + 1).mp3")
            let probed = await AudioProbe.probe(url)
            XCTAssertEqual(probed.codec, .mp3, "codec of \(url.lastPathComponent)")
            XCTAssertEqual(probed.duration, p.seconds, accuracy: 0.15, "duration of \(url.lastPathComponent)")
            XCTAssertEqual(probed.title, p.name, "ID3 title of \(url.lastPathComponent)")
            XCTAssertEqual(probed.album, "Fixture Book")
            XCTAssertEqual(probed.artist, "Fixture Author")
            XCTAssertEqual(probed.bitrate, 64000, accuracy: 4000, "bitrate of \(url.lastPathComponent)")
            XCTAssertFalse(probed.hasChapters)
            chapters.append(Chapter(
                sourceURL: url, title: probed.title ?? "", duration: probed.duration,
                sourceBitrate: probed.bitrate, codec: probed.codec,
                sampleRate: probed.sampleRate, channels: probed.channels
            ))
        }
        let job = EncodeJob(spec: makeSpec(in: tmp, chapters: chapters, bitrate: .source))

        // Act
        let out = try await job.run()

        // Assert
        try await assertStitched(out, plan: plan)
    }

    // MARK: - helpers

    /// Shared stitching assertions: total duration, marker titles and
    /// start times at the cumulative durations, and the tone heard in the
    /// middle of each chapter.
    private func assertStitched(
        _ out: URL, plan: [(name: String, seconds: Double, hz: Double)],
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let asset = AVURLAsset(url: out)
        let total = plan.reduce(0) { $0 + $1.seconds }
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, total, accuracy: 0.3, "total duration", file: file, line: line)

        let markers = try await loadChapters(asset)
        XCTAssertEqual(markers.map(\.title), plan.map(\.name), "chapter order", file: file, line: line)
        var expectedStart = 0.0
        for (i, p) in plan.enumerated() where i < markers.count {
            XCTAssertEqual(
                markers[i].start,
                expectedStart,
                accuracy: 0.15,
                "start of \(p.name)",
                file: file,
                line: line
            )
            // Read a window from the middle of the chapter, well clear of
            // both boundaries and the AAC priming samples.
            let window = min(1.0, p.seconds * 0.5)
            let mid = expectedStart + p.seconds / 2 - window / 2
            let hz = try await dominantFrequency(of: out, start: mid, duration: window)
            XCTAssertEqual(hz, p.hz, accuracy: p.hz * 0.05, "audio inside \(p.name)", file: file, line: line)
            expectedStart += p.seconds
        }
    }
}
