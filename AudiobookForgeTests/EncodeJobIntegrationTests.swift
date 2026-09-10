import AVFoundation
import os
import XCTest
@testable import ForgeCore

/// End-to-end encodes against the real bundled ffmpeg. Tests run outside
/// the app bundle, so `Bundled` is pointed at the repo's Resources/bin
/// (built by scripts/build-ffmpeg.sh — run scripts/bootstrap.sh first).
/// Fixtures are tiny generated sine-wave WAVs; outputs are verified with
/// AVFoundation (duration, chapter markers, book metadata).
@MainActor
final class EncodeJobIntegrationTests: XCTestCase {
    // nonisolated(unsafe): XCTest's setUp/tearDown are nonisolated even
    // on a @MainActor test class, and the fixture is only touched there
    // and from the (main-actor) test bodies, always serially.
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

    // MARK: - re-encode path

    func test_reencode_wavChaptersProduceChapteredM4B() async throws {
        // Arrange — two 1-second WAV chapters (PCM forces the re-encode
        // path) and full book metadata.
        let wav1 = tmp.appendingPathComponent("ch1.wav")
        let wav2 = tmp.appendingPathComponent("ch2.wav")
        try writeSineWav(to: wav1, seconds: 1.0, frequency: 440)
        try writeSineWav(to: wav2, seconds: 1.0, frequency: 660)
        let spec = makeSpec(
            in: tmp, chapters: [
                chapter(wav1, title: "Opening", codec: .pcm),
                chapter(wav2, title: "Closing", codec: .pcm)
            ],
            bitrate: .k64
        )
        let job = EncodeJob(spec: spec)

        // Act
        let outputURL = try await job.run()

        // Assert — file exists, plays as ~2 s of audio, carries both
        // chapter markers and the book-level tags.
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 2.0, accuracy: 0.3)
        let chapterTitles = try await loadChapterTitles(asset)
        XCTAssertEqual(chapterTitles, ["Opening", "Closing"])
        let title = try await loadCommonTitle(asset)
        XCTAssertEqual(title, "Integration Book")

        // The finished m4b must read back as "already forged" so the
        // import guard keeps it out of the chapter list, while the raw
        // WAV source reads as chapterless and importable.
        async let probedOutput = AudioProbe.probe(outputURL)
        async let probedSource = AudioProbe.probe(wav1)
        let hasChapters = await (probedOutput.hasChapters, probedSource.hasChapters)
        XCTAssertTrue(hasChapters.0)
        XCTAssertFalse(hasChapters.1)

        // Chapters must ship in BOTH container formats: the QuickTime
        // chap track (Apple players — proven above via AVFoundation)
        // and the Nero chpl atom (ffmpeg-lineage players). ffmpeg's mov
        // muxer writes both by default; a future flag change or ffmpeg
        // bump silently dropping one would shrink player compatibility.
        let bytes = try Data(contentsOf: outputURL)
        XCTAssertTrue(bytes.contains(Data("chpl".utf8)),
                      "output m4b lost its Nero chpl chapter atom")
    }

    // MARK: - remux path

    func test_remux_uniformAACChaptersProduceM4BWithoutReencode() async throws {
        // Arrange — pre-encode two WAVs to uniform AAC with the same
        // pipeline the app uses, then feed them back as chapters set to
        // "Match source" bitrate (the remux trigger).
        let m4a1 = try await makeAacFixture(in: tmp, name: "a", frequency: 440)
        let m4a2 = try await makeAacFixture(in: tmp, name: "b", frequency: 660)
        let spec = makeSpec(
            in: tmp, chapters: [
                chapter(m4a1, title: "One", codec: .aac),
                chapter(m4a2, title: "Two", codec: .aac)
            ],
            bitrate: .source
        )
        XCTAssertTrue(
            EncodeJob.canRemux(chapters: spec.chapters, settings: spec.settings),
            "precondition: this spec must take the remux path"
        )
        let job = EncodeJob(spec: spec)

        // Act
        let outputURL = try await job.run()

        // Assert
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 2.0, accuracy: 0.3)
        let chapterTitles = try await loadChapterTitles(asset)
        XCTAssertEqual(chapterTitles, ["One", "Two"])
        // Both chapter styles on the remux path too — output format is a
        // property of the writer, never of what the sources carried.
        let bytes = try Data(contentsOf: outputURL)
        XCTAssertTrue(bytes.contains(Data("chpl".utf8)),
                      "remuxed m4b lost its Nero chpl chapter atom")
    }

    // MARK: - cancellation regressions

    func test_cancelBeforeRun_throwsCancelledWithoutCrashOrOutput() async throws {
        // Arrange — the crash regression: a cancel that lands before any
        // ffmpeg has launched used to fire terminate() on an unlaunched
        // Process (ObjC exception) or be silently lost by the child-token
        // fan-out. Now it must surface as a clean .cancelled.
        let wav = tmp.appendingPathComponent("ch.wav")
        try writeSineWav(to: wav, seconds: 1.0, frequency: 440)
        let spec = makeSpec(in: tmp, chapters: [chapter(wav, title: "X", codec: .pcm)], bitrate: .k64)
        let job = EncodeJob(spec: spec)
        job.cancelToken.cancel()

        // Act / Assert
        do {
            _ = try await job.run()
            XCTFail("expected .cancelled to be thrown")
        } catch let e as FFmpegRunner.RunError {
            guard case .cancelled = e else {
                return XCTFail("expected .cancelled, got \(e)")
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: spec.outputURL.path),
            "a cancelled job must not leave an output file"
        )
    }

    func test_ffmpegRunner_cancelledTokenSkipsSpawnEntirely() async {
        // Arrange
        let token = CancelToken()
        token.cancel()

        // Act / Assert — pre-cancelled token means no child is spawned
        // and .cancelled comes back immediately.
        do {
            _ = try await FFmpegRunner.run(
                arguments: ["-i", "/nonexistent", "-f", "null", "-"],
                totalDuration: 0,
                onProgress: { _, _ in },
                cancelToken: token
            )
            XCTFail("expected .cancelled to be thrown")
        } catch let e as FFmpegRunner.RunError {
            if case .cancelled = e {} else { XCTFail("expected .cancelled, got \(e)") }
        } catch {
            XCTFail("expected RunError.cancelled, got \(error)")
        }
    }

    func test_ffmpegRunner_badInputSurfacesNonZeroExitWithStderrTail() async {
        // Arrange — a file ffmpeg cannot open
        let missing = tmp.appendingPathComponent("missing.mp3").path

        // Act / Assert
        do {
            _ = try await FFmpegRunner.run(
                arguments: ["-i", missing, "-f", "null", "-"],
                totalDuration: 0,
                onProgress: { _, _ in }
            )
            XCTFail("expected .nonZeroExit to be thrown")
        } catch let e as FFmpegRunner.RunError {
            guard case let .nonZeroExit(code, tail) = e else {
                return XCTFail("expected .nonZeroExit, got \(e)")
            }
            XCTAssertNotEqual(code, 0)
            XCTAssertTrue(
                tail.localizedCaseInsensitiveContains("no such file"),
                "stderr tail should explain the failure, got: \(tail)"
            )
        } catch {
            XCTFail("expected RunError.nonZeroExit, got \(error)")
        }
    }

    // MARK: - auto-normalize

    func test_autoNormalize_measuresAndBringsBookToTarget() async throws {
        // Arrange — two loud-ish sine chapters (≈ -12 LUFS) with
        // auto-normalize on. The pass must measure them, compute one
        // book-wide offset, and re-encode through a volume filter.
        let wav1 = tmp.appendingPathComponent("n1.wav")
        let wav2 = tmp.appendingPathComponent("n2.wav")
        try writeSineWav(to: wav1, seconds: 3.0, frequency: 440)
        try writeSineWav(to: wav2, seconds: 3.0, frequency: 660)
        var spec = makeSpec(
            in: tmp, chapters: [
                chapter(wav1, title: "One", codec: .pcm),
                chapter(wav2, title: "Two", codec: .pcm)
            ],
            bitrate: .k64
        )
        spec.settings.gainBoost = .autoNormalize
        let labels = OSAllocatedUnfairLock<[String]>(initialState: [])
        let job = EncodeJob(spec: spec) { _, label in labels.withLock { $0.append(label) } }

        // Act
        let outputURL = try await job.run()

        // Assert — the measurement phase ran, and the output's integrated
        // loudness sits at the target (± what a 6 s tone can hit).
        XCTAssertTrue(labels.withLock { $0 }.contains { $0.hasPrefix("Measuring loudness") })
        let lufs = try await integratedLoudness(of: outputURL)
        XCTAssertEqual(lufs, EncodeJob.autoNormalizeTargetLUFS, accuracy: 1.5)
    }

    func test_autoIfQuiet_liftsAQuietBookToTarget() async throws {
        // Arrange — a quiet tone (≈ -28 LUFS), well below the -16 target.
        let wav = tmp.appendingPathComponent("quiet.wav")
        try writeSineWav(to: wav, seconds: 4.0, frequency: 440, amplitude: 2000)
        var spec = makeSpec(in: tmp, chapters: [chapter(wav, title: "Quiet", codec: .pcm)], bitrate: .k64)
        spec.settings.gainBoost = .autoIfQuiet
        let job = EncodeJob(spec: spec)

        // Act
        let outputURL = try await job.run()

        // Assert
        let lufs = try await integratedLoudness(of: outputURL)
        XCTAssertEqual(lufs, EncodeJob.autoNormalizeTargetLUFS, accuracy: 1.5)
    }

    func test_autoIfQuiet_leavesALoudBookUntouched() async throws {
        // Arrange — a loud tone (≈ -12 LUFS), above target. Auto-normalize
        // would pull this down by ~4 dB; lift-only must not.
        let wav = tmp.appendingPathComponent("loud.wav")
        try writeSineWav(to: wav, seconds: 4.0, frequency: 440)
        let sourceLUFS = try await integratedLoudness(of: wav)
        XCTAssertGreaterThan(sourceLUFS, EncodeJob.autoNormalizeTargetLUFS, "fixture isn't loud")
        var spec = makeSpec(in: tmp, chapters: [chapter(wav, title: "Loud", codec: .pcm)], bitrate: .k64)
        spec.settings.gainBoost = .autoIfQuiet
        let job = EncodeJob(spec: spec)

        // Act
        let outputURL = try await job.run()

        // Assert — output loudness matches the source, not the target.
        let lufs = try await integratedLoudness(of: outputURL)
        XCTAssertEqual(lufs, sourceLUFS, accuracy: 1.0)
    }

    func test_autoNormalize_failsLoudlyWhenNothingCanBeMeasured() async throws {
        // Arrange — a "chapter" whose file isn't audio at all, so ebur128
        // has nothing to report. Encoding it unnormalized and saying
        // Done would be worse than failing.
        let junk = tmp.appendingPathComponent("junk.wav")
        try Data("not a wav".utf8).write(to: junk)
        var spec = makeSpec(in: tmp, chapters: [chapter(junk, title: "Junk", codec: .pcm)], bitrate: .k64)
        spec.settings.gainBoost = .autoNormalize
        let job = EncodeJob(spec: spec)

        // Act / Assert
        do {
            _ = try await job.run()
            XCTFail("expected loudnessMeasurementFailed")
        } catch let error as EncodeError {
            guard case .loudnessMeasurementFailed = error else {
                return XCTFail("expected loudnessMeasurementFailed, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: spec.outputURL.path))
    }

    // MARK: - mid-run cancellation

    func test_cancelMidRun_terminatesFFmpegAndLeavesNoPartialOutput() async throws {
        // Arrange — a long enough re-encode that a cancel can land while
        // ffmpeg is genuinely running, into an output dir of its own so
        // "nothing was written" is checkable.
        let wav = tmp.appendingPathComponent("long.wav")
        try writeSineWav(to: wav, seconds: 600, frequency: 440)
        let outDir = tmp.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var spec = makeSpec(in: tmp, chapters: [chapter(wav, title: "Long", codec: .pcm)], bitrate: .k64)
        spec.outputURL = outDir.appendingPathComponent("Long.m4b")
        let sawEncoding = OSAllocatedUnfairLock<Bool>(initialState: false)
        let job = EncodeJob(spec: spec) { _, label in
            if label.hasPrefix("Encoding chapter") { sawEncoding.withLock { $0 = true } }
        }

        // Act — start, wait until phase 1 has reported progress, cancel.
        let run = Task { try await job.run() }
        let deadline = Date().addingTimeInterval(10)
        while !sawEncoding.withLock({ $0 }), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(sawEncoding.withLock { $0 }, "encode never reported progress")
        job.cancelToken.cancel()

        // Assert — surfaces as .cancelled, promptly, and the output
        // directory holds neither a .partial nor a finished file.
        do {
            _ = try await run.value
            XCTFail("expected RunError.cancelled")
        } catch let error as FFmpegRunner.RunError {
            guard case .cancelled = error else { return XCTFail("expected .cancelled, got \(error)") }
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: outDir.path)
        XCTAssertEqual(leftovers, [], "cancel left files behind: \(leftovers)")
    }
}
