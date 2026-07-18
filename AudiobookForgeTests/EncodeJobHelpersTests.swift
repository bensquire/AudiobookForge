import XCTest
@testable import AudiobookForge

final class EncodeJobHelpersTests: XCTestCase {
    // MARK: - canRemux

    func test_canRemux_falseWhenBitrateIsNotSource() {
        // Arrange — uniform AAC sources but user picked a specific bitrate,
        // which is an explicit request to re-encode at that target.
        let chapters = [aacChapter(), aacChapter()]
        var settings = EncodeSettings()
        settings.bitrate = .k128

        // Act
        let canRemux = EncodeJob.canRemux(chapters: chapters, settings: settings)

        // Assert
        XCTAssertFalse(canRemux)
    }

    func test_canRemux_trueForUniformAACAtSourceBitrate() {
        // Arrange
        let chapters = [aacChapter(), aacChapter()]
        let settings = EncodeSettings() // .source by default

        // Act
        let canRemux = EncodeJob.canRemux(chapters: chapters, settings: settings)

        // Assert
        XCTAssertTrue(canRemux)
    }

    func test_canRemux_falseWhenAnyChapterIsMP3() {
        // Arrange
        let chapters = [aacChapter(), mp3Chapter()]

        // Act
        let canRemux = EncodeJob.canRemux(
            chapters: chapters, settings: EncodeSettings()
        )

        // Assert — MP3 in MP4 is legal but stumbles in some readers, so we
        // route mixed/MP3 inputs through the re-encode path.
        XCTAssertFalse(canRemux)
    }

    func test_canRemux_falseWhenSampleRatesDiffer() {
        // Arrange — both AAC, different sample rates
        var first = aacChapter(); first.sampleRate = 44100
        var second = aacChapter(); second.sampleRate = 48000

        // Act
        let canRemux = EncodeJob.canRemux(
            chapters: [first, second], settings: EncodeSettings()
        )

        // Assert
        XCTAssertFalse(canRemux)
    }

    func test_canRemux_falseWhenChannelCountsDiffer() {
        // Arrange — both AAC, mono vs stereo
        var first = aacChapter(); first.channels = 1
        var second = aacChapter(); second.channels = 2

        // Act
        let canRemux = EncodeJob.canRemux(
            chapters: [first, second], settings: EncodeSettings()
        )

        // Assert
        XCTAssertFalse(canRemux)
    }

    func test_canRemux_falseForEmptyChapterList() {
        // Arrange / Act / Assert
        XCTAssertFalse(EncodeJob.canRemux(chapters: [], settings: EncodeSettings()))
    }

    func test_canRemux_falseForMixedAACProfiles() {
        // Arrange — LC and HE-AAC probe as distinct codecs; their
        // bitstreams can't be joined with `-c:a copy`.
        var he = aacChapter()
        he.codec = .aacHE

        // Act
        let canRemux = EncodeJob.canRemux(
            chapters: [aacChapter(), he], settings: EncodeSettings()
        )

        // Assert
        XCTAssertFalse(canRemux)
    }

    func test_canRemux_trueForUniformHEAAC() {
        // Arrange — all chapters HE-AAC with matching params
        var first = aacChapter(); first.codec = .aacHE
        var second = aacChapter(); second.codec = .aacHE

        // Act
        let canRemux = EncodeJob.canRemux(
            chapters: [first, second], settings: EncodeSettings()
        )

        // Assert — a uniform HE book gets the lossless fast path
        XCTAssertTrue(canRemux)
    }

    // MARK: - estimatedRequiredBytes

    func test_estimatedRequiredBytes_scalesWithDurationAndBitrate() {
        // Arrange — 1000 s at 128 kbps = 16 MB of payload; the re-encode
        // path (forced by the explicit bitrate) doubles that for the
        // intermediates plus container headroom.
        var ch = aacChapter()
        ch.duration = 1000
        var settings = EncodeSettings()
        settings.bitrate = .k128

        // Act
        let bytes = EncodeJob.estimatedRequiredBytes(chapters: [ch], settings: settings)

        // Assert — 16 MB payload; estimate must cover payload×2 but stay
        // within an order of magnitude (it's a preflight, not an invoice).
        XCTAssertGreaterThan(bytes, 32_000_000)
        XCTAssertLessThan(bytes, 64_000_000)
    }

    func test_estimatedRequiredBytes_remuxPathNeedsLessHeadroom() {
        // Arrange — identical chapters; one settings remuxes (source
        // bitrate, no gain), the other re-encodes (explicit bitrate).
        var ch = aacChapter()
        ch.duration = 1000
        ch.sourceBitrate = 128_000
        var reencode = EncodeSettings()
        reencode.bitrate = .k128

        // Act
        let remuxBytes = EncodeJob.estimatedRequiredBytes(
            chapters: [ch], settings: EncodeSettings()
        )
        let reencodeBytes = EncodeJob.estimatedRequiredBytes(
            chapters: [ch], settings: reencode
        )

        // Assert — remux writes the payload once, re-encode twice.
        XCTAssertLessThan(remuxBytes, reencodeBytes)
    }

    // MARK: - isDecodableImage

    func test_isDecodableImage_acceptsRealPNG() throws {
        // Arrange — 1×1 red PNG
        let png = try XCTUnwrap(Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg=="
        ))

        // Act / Assert
        XCTAssertTrue(EncodeJob.isDecodableImage(png))
    }

    func test_isDecodableImage_rejectsGarbageBytes() {
        // Arrange — plausible-length junk that is not any image format
        let junk = Data(repeating: 0x42, count: 4096)

        // Act / Assert
        XCTAssertFalse(EncodeJob.isDecodableImage(junk))
        XCTAssertFalse(EncodeJob.isDecodableImage(Data()))
    }

    // MARK: - resolveBitrate

    func test_resolveBitrate_specificValuePassesThrough() {
        // Arrange
        var settings = EncodeSettings()
        settings.bitrate = .k192

        // Act
        let resolved = EncodeJob.resolveBitrate(
            chapters: [aacChapter()], settings: settings
        )

        // Assert
        XCTAssertEqual(resolved, "192k")
    }

    func test_resolveBitrate_sourceMode_snapsToNearestStandardStep() {
        // Arrange — 70 kbps weighted average; nearest standard step is 64k.
        var ch = aacChapter()
        ch.sourceBitrate = 70000
        ch.duration = 60

        // Act
        let resolved = EncodeJob.resolveBitrate(
            chapters: [ch], settings: EncodeSettings()
        ) // source default

        // Assert
        XCTAssertEqual(resolved, "64k")
    }

    func test_resolveBitrate_sourceMode_durationWeightedAverage() {
        // Arrange — short 192 kbps prelude + long 64 kbps body. Weighted
        // average heavily favours the longer file → snap to 64k.
        var short = aacChapter(); short.sourceBitrate = 192_000; short.duration = 1
        var long = aacChapter(); long.sourceBitrate = 64000; long.duration = 100

        // Act
        let resolved = EncodeJob.resolveBitrate(
            chapters: [short, long], settings: EncodeSettings()
        )

        // Assert
        XCTAssertEqual(resolved, "64k")
    }

    func test_resolveBitrate_sourceMode_zeroSourceFallsBackTo64k() {
        // Arrange — chapter with no probed bitrate at all
        var ch = aacChapter()
        ch.sourceBitrate = 0
        ch.duration = 60

        // Act
        let resolved = EncodeJob.resolveBitrate(
            chapters: [ch], settings: EncodeSettings()
        )

        // Assert — sane default rather than 0k or a divide-by-zero
        XCTAssertEqual(resolved, "64k")
    }

    // MARK: - resolveOutputURL

    func test_resolveOutputURL_appliesTemplateTokens() {
        // Arrange
        let base = URL(fileURLWithPath: "/Volumes/Audiobooks")
        var meta = BookMetadata()
        meta.title = "Dune"; meta.author = "Frank Herbert"; meta.year = "1965"

        // Act
        let result = EncodeJob.resolveOutputURL(
            in: base,
            metadata: meta,
            template: "{author}/{year}/{title}.m4b"
        )

        // Assert
        XCTAssertEqual(result.path, "/Volumes/Audiobooks/Frank Herbert/1965/Dune.m4b")
    }

    func test_resolveOutputURL_sanitisesIllegalFilenameCharacters() {
        // Arrange — title contains forward slashes which would otherwise
        // become path separators.
        var meta = BookMetadata()
        meta.title = "A/B: C?"; meta.author = "x"

        // Act
        let result = EncodeJob.resolveOutputURL(
            in: URL(fileURLWithPath: "/out"),
            metadata: meta,
            template: "{title}.m4b"
        )

        // Assert — illegal characters replaced with `_`
        XCTAssertEqual(result.lastPathComponent, "A_B_ C_.m4b")
    }

    // MARK: - helpers

    private func aacChapter() -> Chapter {
        Chapter(
            sourceURL: URL(fileURLWithPath: "/tmp/x.m4a"),
            title: "x",
            duration: 60,
            sourceBitrate: 64000,
            codec: .aac,
            sampleRate: 44100,
            channels: 2
        )
    }

    private func mp3Chapter() -> Chapter {
        Chapter(
            sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
            title: "x",
            duration: 60,
            sourceBitrate: 64000,
            codec: .mp3,
            sampleRate: 44100,
            channels: 2
        )
    }
}
