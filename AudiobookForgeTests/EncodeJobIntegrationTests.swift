import AVFoundation
import XCTest
@testable import ForgeCore

/// End-to-end encodes against the real bundled ffmpeg. Tests run outside
/// the app bundle, so `Bundled` is pointed at the repo's Resources/bin
/// (built by scripts/build-ffmpeg.sh — run scripts/bootstrap.sh first).
/// Fixtures are tiny generated sine-wave WAVs; outputs are verified with
/// AVFoundation (duration, chapter markers, book metadata).
@MainActor
final class EncodeJobIntegrationTests: XCTestCase {
    private var tmp: URL!

    private static let repoBinDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // AudiobookForgeTests/
        .deletingLastPathComponent() // repo root
        .appendingPathComponent("AudiobookForge/Resources/bin")

    override func setUp() {
        super.setUp()
        Bundled.setOverrideDirectory(Self.repoBinDir)
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
            chapters: [
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
        let m4a1 = try await makeAacFixture(name: "a", frequency: 440)
        let m4a2 = try await makeAacFixture(name: "b", frequency: 660)
        let spec = makeSpec(
            chapters: [
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
        let spec = makeSpec(chapters: [chapter(wav, title: "X", codec: .pcm)], bitrate: .k64)
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

    // MARK: - fixture + spec helpers

    /// Minimal 16-bit mono PCM WAV with a sine tone — enough for ffmpeg
    /// to decode and loud enough for loudness filters to see signal.
    private func writeSineWav(
        to url: URL, seconds: Double, frequency: Double, sampleRate: Int = 44100
    ) throws {
        let frames = Int(Double(sampleRate) * seconds)
        var samples = Data(capacity: frames * 2)
        for i in 0 ..< frames {
            let value = Int16(12000 * sin(2 * .pi * frequency * Double(i) / Double(sampleRate)))
            withUnsafeBytes(of: value.littleEndian) { samples.append(contentsOf: $0) }
        }
        var header = Data()
        func append(_ s: String) {
            header.append(contentsOf: s.utf8)
        }
        func append32(_ v: UInt32) {
            withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) }
        }
        func append16(_ v: UInt16) {
            withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) }
        }
        append("RIFF"); append32(UInt32(36 + samples.count)); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1)
        append32(UInt32(sampleRate)); append32(UInt32(sampleRate * 2))
        append16(2); append16(16)
        append("data"); append32(UInt32(samples.count))
        try (header + samples).write(to: url)
    }

    /// Encode a 1 s sine WAV to AAC using the app's own phase-1 arg
    /// builder, so remux fixtures share the exact codec params the app
    /// would produce.
    private func makeAacFixture(name: String, frequency: Double) async throws -> URL {
        let wav = tmp.appendingPathComponent("\(name).wav")
        let m4a = tmp.appendingPathComponent("\(name).m4a")
        try writeSineWav(to: wav, seconds: 1.0, frequency: frequency)
        _ = try await FFmpegRunner.run(
            arguments: EncodeJob.phase1Args(
                input: wav, output: m4a, bitrate: "64k", sampleRate: 44100, channels: 1
            ),
            totalDuration: 1.0,
            onProgress: { _, _ in }
        )
        return m4a
    }

    private func chapter(
        _ url: URL, title: String, codec: ForgeCore.AudioCodec
    ) -> Chapter {
        Chapter(
            sourceURL: url,
            title: title,
            duration: 1.0,
            sourceBitrate: 64000,
            codec: codec,
            sampleRate: 44100,
            channels: 1
        )
    }

    private func makeSpec(chapters: [Chapter], bitrate: EncodeSettings.Bitrate) -> EncodeSpec {
        var metadata = BookMetadata()
        metadata.title = "Integration Book"
        metadata.author = "Test Author"
        var settings = EncodeSettings()
        settings.bitrate = bitrate
        settings.outputDirectory = tmp
        return EncodeSpec(
            chapters: chapters,
            metadata: metadata,
            settings: settings,
            outputURL: tmp.appendingPathComponent("Integration Book.m4b")
        )
    }

    // MARK: - AVFoundation verification helpers

    private func loadChapterTitles(_ asset: AVURLAsset) async throws -> [String] {
        // ffmpeg writes chapter titles with an "und" locale, which a
        // preferred-language lookup won't match — ask the asset what
        // locales it actually has.
        let locales = try await asset.load(.availableChapterLocales)
        guard let locale = locales.first else { return [] }
        let groups = try await asset.loadChapterMetadataGroups(
            withTitleLocale: locale, containingItemsWithCommonKeys: [.commonKeyTitle]
        )
        var titles: [String] = []
        for group in groups {
            let items = AVMetadataItem.metadataItems(
                from: group.items, filteredByIdentifier: .commonIdentifierTitle
            )
            if let first = items.first, let value = try await first.load(.stringValue) {
                titles.append(value)
            }
        }
        return titles
    }

    private func loadCommonTitle(_ asset: AVURLAsset) async throws -> String? {
        let meta = try await asset.load(.commonMetadata)
        let items = AVMetadataItem.metadataItems(
            from: meta, filteredByIdentifier: .commonIdentifierTitle
        )
        guard let first = items.first else { return nil }
        return try await first.load(.stringValue)
    }
}
