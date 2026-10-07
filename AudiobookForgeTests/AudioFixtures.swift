import AVFoundation
import Foundation
import XCTest
@testable import ForgeCore

// Shared fixtures and probes for the integration tests that run the real
// bundled ffmpeg. Everything here is synthetic on purpose: a sine tone is
// cheap to generate at any length, has a known frequency (so chapter
// order and boundaries can be checked from the decoded audio, not just
// from metadata), and has a predictable loudness (so gain modes can be
// checked against measured LUFS).

/// Committed audio fixtures (real MP3s made with LAME; see the README in
/// that directory for how they were produced).
let fixturesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures")

/// The repo's `AudiobookForge/Resources/bin`, where `scripts/build-ffmpeg.sh`
/// drops the bundled ffmpeg. Tests run outside the app bundle, so anything
/// that spawns ffmpeg points `Bundled` here first.
let repoBinDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // AudiobookForgeTests/
    .deletingLastPathComponent() // repo root
    .appendingPathComponent("AudiobookForge/Resources/bin")

// MARK: - Fixture generation

/// Write a 16-bit mono PCM sine-wave WAV. PCM sources force EncodeJob
/// down the re-encode path. `amplitude` is in sample units (max 32767);
/// the default lands around -12 LUFS, 3000 around -24 LUFS.
func writeSineWav(
    to url: URL, seconds: Double, frequency: Double, sampleRate: Int = 44100,
    amplitude: Double = 12000
) throws {
    let frames = Int(Double(sampleRate) * seconds)
    var samples = [Int16](repeating: 0, count: frames)
    let step = 2 * Double.pi * frequency / Double(sampleRate)
    for i in 0 ..< frames {
        samples[i] = Int16(amplitude * sin(step * Double(i)))
    }
    var data = Data(capacity: 44 + frames * 2)
    func append(_ s: String) {
        data.append(contentsOf: s.utf8)
    }
    func append32(_ v: UInt32) {
        withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
    }
    func append16(_ v: UInt16) {
        withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
    }
    append("RIFF"); append32(UInt32(36 + frames * 2)); append("WAVE")
    append("fmt "); append32(16); append16(1); append16(1)
    append32(UInt32(sampleRate)); append32(UInt32(sampleRate * 2))
    append16(2); append16(16)
    append("data"); append32(UInt32(frames * 2))
    samples.withUnsafeBufferPointer { data.append($0) } // arm64 is little-endian
    try data.write(to: url)
}

/// Fixtures that are expensive enough to build once per test process.
enum SharedFixtures {
    /// Ten minutes of tone. Cancel-mid-run tests need an encode that is
    /// still in flight when the cancel lands, and ffmpeg encodes ~500×
    /// realtime here, so nothing shorter leaves a window. Written at
    /// 8 kHz to keep generation cheap — the encoder resamples to the
    /// chapter's declared 44.1 kHz, so the encode itself is unchanged.
    static let tenMinuteTone: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudiobookForgeTests-\(ProcessInfo.processInfo.processIdentifier)")
        let url = dir.appendingPathComponent("ten-minute-tone.wav")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! writeSineWav(to: url, seconds: 600, frequency: 440, sampleRate: 8000)
        return url
    }()
}

/// Base for tests that run the real bundled ffmpeg: a throwaway
/// directory per test, `Bundled` pointed at the repo's build, and a skip
/// (not a failure) when `scripts/build-ffmpeg.sh` hasn't run.
class FFmpegTestCase: XCTestCase {
    var tmp: URL!

    override func setUp() async throws {
        try await super.setUp()
        Bundled.setOverrideDirectory(repoBinDir)
        try XCTSkipIf(Bundled.binary("ffmpeg") == nil, "bundled ffmpeg not built")
        tmp = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
            create: true
        )
    }

    override func tearDown() async throws {
        Bundled.setOverrideDirectory(nil)
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
        try await super.tearDown()
    }
}

/// Poll `condition` until it holds or `timeout` elapses (then throw, so
/// a hung queue fails the test instead of skipping it).
@MainActor
func waitUntil(
    timeout: TimeInterval = 15,
    _ condition: @MainActor () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else { throw TimedOut() }
        try await Task.sleep(for: .milliseconds(20))
    }
}

struct TimedOut: Error {}

/// Encode a sine WAV to AAC using the app's own phase-1 arg builder, so
/// remux fixtures share the exact codec params the app would produce.
func makeAacFixture(
    in dir: URL, name: String, frequency: Double, seconds: Double = 1.0
) async throws -> URL {
    let wav = dir.appendingPathComponent("\(name).wav")
    let m4a = dir.appendingPathComponent("\(name).m4a")
    try writeSineWav(to: wav, seconds: seconds, frequency: frequency)
    _ = try await FFmpegRunner.run(
        arguments: EncodeJob.phase1Args(
            input: wav, output: m4a, bitrate: "64k", sampleRate: 44100, channels: 1
        ),
        totalDuration: seconds,
        onProgress: { _, _ in }
    )
    return m4a
}

func chapter(
    _ url: URL, title: String, codec: ForgeCore.AudioCodec, duration: TimeInterval = 1.0
) -> Chapter {
    Chapter(
        sourceURL: url,
        title: title,
        duration: duration,
        sourceBitrate: 64000,
        codec: codec,
        sampleRate: 44100,
        channels: 1
    )
}

func makeSpec(
    in dir: URL, chapters: [Chapter], bitrate: EncodeSettings.Bitrate,
    title: String = "Integration Book"
) -> EncodeSpec {
    var metadata = BookMetadata()
    metadata.title = title
    metadata.author = "Test Author"
    var settings = EncodeSettings()
    settings.bitrate = bitrate
    settings.outputDirectory = dir
    return EncodeSpec(
        chapters: chapters,
        metadata: metadata,
        settings: settings,
        outputURL: dir.appendingPathComponent("\(title).m4b")
    )
}

// MARK: - AVFoundation metadata probes

struct ChapterMarker: Equatable {
    let title: String
    let start: TimeInterval
}

/// Chapter markers as Apple players see them (the QuickTime chapter
/// track), in file order.
func loadChapters(_ asset: AVURLAsset) async throws -> [ChapterMarker] {
    // ffmpeg writes chapter titles with an "und" locale, which a
    // preferred-language lookup won't match — ask the asset what
    // locales it actually has.
    let locales = try await asset.load(.availableChapterLocales)
    guard let locale = locales.first else { return [] }
    let groups = try await asset.loadChapterMetadataGroups(
        withTitleLocale: locale, containingItemsWithCommonKeys: [.commonKeyTitle]
    )
    var markers: [ChapterMarker] = []
    for group in groups {
        let items = AVMetadataItem.metadataItems(
            from: group.items, filteredByIdentifier: .commonIdentifierTitle
        )
        if let first = items.first, let value = try await first.load(.stringValue) {
            markers.append(ChapterMarker(title: value, start: group.timeRange.start.seconds))
        }
    }
    return markers
}

func loadChapterTitles(_ asset: AVURLAsset) async throws -> [String] {
    try await loadChapters(asset).map(\.title)
}

func loadCommonTitle(_ asset: AVURLAsset) async throws -> String? {
    let meta = try await asset.load(.commonMetadata)
    let items = AVMetadataItem.metadataItems(
        from: meta, filteredByIdentifier: .commonIdentifierTitle
    )
    guard let first = items.first else { return nil }
    return try await first.load(.stringValue)
}

// MARK: - Audio content probes (via the bundled ffmpeg)

/// Integrated loudness (LUFS) of a window of `url`, measured with the
/// same ebur128 pass the encoder uses. Whole file when `start`/`duration`
/// are nil.
func integratedLoudness(
    of url: URL, start: TimeInterval? = nil, duration: TimeInterval? = nil,
    file: StaticString = #filePath, line: UInt = #line
) async throws -> Double {
    let args = EncodeJob.ebur128MeasureArgs(input: url, start: start, duration: duration)
    let captured = await FFmpegRunner.captureStderr(arguments: args)
    let stderr = try XCTUnwrap(
        captured,
        "ffmpeg produced no stderr measuring \(url.lastPathComponent)",
        file: file,
        line: line
    )
    return try XCTUnwrap(
        EncodeJob.parseEbur128IntegratedLUFS(stderr), "no ebur128 summary in:\n\(stderr)", file: file,
        line: line
    )
}

/// Estimate the dominant frequency of a window of `url` by decoding it
/// to mono 16-bit PCM (via AVFoundation — the same decoder Apple players
/// use) and counting zero crossings. Exact enough for a single sine tone
/// (within ~2%), which is all the fixtures contain — and enough to prove
/// which chapter's audio landed where.
func dominantFrequency(
    of url: URL, start: TimeInterval, duration: TimeInterval,
    file: StaticString = #filePath, line: UInt = #line
) async throws -> Double {
    let asset = AVURLAsset(url: url)
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    let track = try XCTUnwrap(
        tracks.first,
        "no audio track in \(url.lastPathComponent)",
        file: file,
        line: line
    )
    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = CMTimeRange(
        start: CMTime(seconds: start, preferredTimescale: 44100),
        duration: CMTime(seconds: duration, preferredTimescale: 44100)
    )
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
        AVNumberOfChannelsKey: 1,
        AVSampleRateKey: 44100
    ])
    reader.add(output)
    XCTAssertTrue(
        reader.startReading(), "AVAssetReader failed to start: \(String(describing: reader.error))",
        file: file, line: line
    )

    var samples: [Int16] = []
    while let buffer = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
        let length = CMBlockBufferGetDataLength(block)
        var bytes = Data(count: length)
        bytes.withUnsafeMutableBytes { raw in
            _ = CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: length, destination: raw.baseAddress!
            )
        }
        samples += bytes.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
    }
    guard samples.count > 4410 else {
        XCTFail(
            "decoded window is too short: \(samples.count) samples (reader: \(reader.status.rawValue))",
            file: file,
            line: line
        )
        return 0
    }
    var crossings = 0
    for i in 1 ..< samples.count where (samples[i - 1] < 0) != (samples[i] < 0) {
        crossings += 1
    }
    let seconds = Double(samples.count) / 44100
    return Double(crossings) / (2 * seconds)
}
