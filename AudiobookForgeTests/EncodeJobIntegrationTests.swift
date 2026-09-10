import AVFoundation
import os
import XCTest
@testable import ForgeCore

/// End-to-end encodes against the real bundled ffmpeg. Tests run outside
/// the app bundle, so `Bundled` is pointed at the repo's Resources/bin
/// (built by scripts/build-ffmpeg.sh — run scripts/bootstrap.sh first).
/// Fixtures are tiny generated sine-wave WAVs; outputs are verified with
/// AVFoundation (duration, chapter markers, book metadata).
final class EncodeJobIntegrationTests: FFmpegTestCase {
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
        let wav = SharedFixtures.tenMinuteTone
        let outDir = tmp.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var spec = makeSpec(
            in: tmp,
            chapters: [chapter(wav, title: "Long", codec: .pcm, duration: 600)],
            bitrate: .k64
        )
        spec.outputURL = outDir.appendingPathComponent("Long.m4b")
        let sawEncoding = OSAllocatedUnfairLock<Bool>(initialState: false)
        let job = EncodeJob(spec: spec) { _, label in
            if label.hasPrefix("Encoding chapter") { sawEncoding.withLock { $0 = true } }
        }

        // Act — start, wait until phase 1 has reported progress, cancel.
        let run = Task { try await job.run() }
        try await waitUntil(timeout: 10) { sawEncoding.withLock { $0 } }
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
