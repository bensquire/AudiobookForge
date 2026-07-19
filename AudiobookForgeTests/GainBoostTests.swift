import XCTest
@testable import ForgeCore

/// Tests for the gain/loudness feature: GainBoost model, the
/// canRemux gate, phase1Args integration, the ebur128 measure args,
/// the ebur128 summary parser, and the weighted-loudness combiner.
final class GainBoostTests: XCTestCase {
    // MARK: - GainBoost model

    func test_gainBoost_manualDB_returnsValueForDBCases() {
        // Arrange / Act / Assert
        XCTAssertEqual(EncodeSettings.GainBoost.dB3.manualDB, 3)
        XCTAssertEqual(EncodeSettings.GainBoost.dB6.manualDB, 6)
        XCTAssertEqual(EncodeSettings.GainBoost.dB9.manualDB, 9)
        XCTAssertEqual(EncodeSettings.GainBoost.dB12.manualDB, 12)
        XCTAssertNil(EncodeSettings.GainBoost.off.manualDB)
        XCTAssertNil(EncodeSettings.GainBoost.autoNormalize.manualDB)
    }

    func test_gainBoost_isManual_trueOnlyForDBCases() {
        // Arrange / Act / Assert
        for boost in [EncodeSettings.GainBoost.dB3, .dB6, .dB9, .dB12] {
            XCTAssertTrue(boost.isManual, "\(boost) should report isManual")
        }
        XCTAssertFalse(EncodeSettings.GainBoost.off.isManual)
        XCTAssertFalse(EncodeSettings.GainBoost.autoNormalize.isManual)
    }

    // MARK: - canRemux gate

    func test_canRemux_falseWhenGainIsManual() {
        // Arrange — uniform AAC sources at Match Source bitrate.
        // Normally remux-friendly, but a manual gain forces re-encode.
        let chapters = [aacChapter(), aacChapter()]
        var settings = EncodeSettings()
        settings.gainBoost = .dB6

        // Act / Assert
        XCTAssertFalse(EncodeJob.canRemux(chapters: chapters, settings: settings))
    }

    func test_canRemux_falseWhenGainIsAutoNormalize() {
        // Arrange
        let chapters = [aacChapter(), aacChapter()]
        var settings = EncodeSettings()
        settings.gainBoost = .autoNormalize

        // Act / Assert
        XCTAssertFalse(EncodeJob.canRemux(chapters: chapters, settings: settings))
    }

    func test_canRemux_trueWhenGainIsOff() {
        // Arrange — sanity check: same inputs as the gain tests above
        // but with gain off, remux should re-enable.
        let chapters = [aacChapter(), aacChapter()]
        var settings = EncodeSettings()
        settings.gainBoost = .off

        // Act / Assert
        XCTAssertTrue(EncodeJob.canRemux(chapters: chapters, settings: settings))
    }

    // MARK: - phase1Args gainFilter integration

    func test_phase1Args_omitsAfWhenGainFilterIsNil() {
        // Arrange / Act
        let args = EncodeJob.phase1Args(
            input: URL(fileURLWithPath: "/x.mp3"),
            output: URL(fileURLWithPath: "/y.m4a"),
            bitrate: "64k",
            sampleRate: 44100,
            channels: 2,
            gainFilter: nil
        )

        // Assert
        XCTAssertFalse(args.contains("-af"))
    }

    func test_phase1Args_injectsAfWhenGainFilterPresent() {
        // Arrange / Act — manual +6 dB filter
        let args = EncodeJob.phase1Args(
            input: URL(fileURLWithPath: "/x.mp3"),
            output: URL(fileURLWithPath: "/y.m4a"),
            bitrate: "64k",
            sampleRate: 44100,
            channels: 2,
            gainFilter: "volume=6dB,alimiter=limit=0.97"
        )

        // Assert — appears before the encoder block
        XCTAssertEqual(args[adjacent: "-af"], "volume=6dB,alimiter=limit=0.97")
        // Encoder still pinned
        XCTAssertEqual(args[adjacent: "-c:a"], "libfdk_aac")
    }

    func test_manualGainFilter_includesLimiter() {
        // Arrange / Act / Assert — alimiter is the safety net for boosts
        // pushing already-loud peaks past 0 dBFS.
        XCTAssertEqual(
            EncodeJob.manualGainFilter(dB: 6),
            "volume=6dB,alimiter=limit=0.97"
        )
        XCTAssertEqual(
            EncodeJob.manualGainFilter(dB: 12),
            "volume=12dB,alimiter=limit=0.97"
        )
    }

    func test_gainFilter_double_formatsWholeNumbersWithoutDecimal() {
        // Manual cases pass whole-number dB; output shouldn't have the
        // trailing ".0" noise.
        XCTAssertEqual(EncodeJob.gainFilter(dB: 6.0), "volume=6dB,alimiter=limit=0.97")
        XCTAssertEqual(EncodeJob.gainFilter(dB: -3.0), "volume=-3dB,alimiter=limit=0.97")
    }

    func test_gainFilter_double_keepsOneDecimalForFractionalValues() {
        // Auto-normalize path pre-rounds to one decimal; preserve that.
        XCTAssertEqual(EncodeJob.gainFilter(dB: 3.5), "volume=3.5dB,alimiter=limit=0.97")
        XCTAssertEqual(EncodeJob.gainFilter(dB: -2.3), "volume=-2.3dB,alimiter=limit=0.97")
    }

    // MARK: - GainBoost.suffix (format-summary helper)

    func test_gainBoost_suffix_offIsEmpty() {
        XCTAssertEqual(EncodeSettings.GainBoost.off.suffix, "")
    }

    func test_gainBoost_suffix_manualMatchesLabel() {
        XCTAssertEqual(EncodeSettings.GainBoost.dB6.suffix, "+6 dB")
        XCTAssertEqual(EncodeSettings.GainBoost.dB12.suffix, "+12 dB")
    }

    func test_gainBoost_suffix_autoNormaliseUsesPastTense() {
        XCTAssertEqual(EncodeSettings.GainBoost.autoNormalize.suffix, "auto-normalised")
    }

    // MARK: - gainOffsetDB (auto-normalize math)

    func test_gainOffsetDB_appliesTargetMinusMeasured() {
        // Source measures -22 LUFS, target is -16 → +6 dB boost.
        XCTAssertEqual(EncodeJob.gainOffsetDB(from: -22.0), 6.0, accuracy: 0.001)
    }

    func test_gainOffsetDB_clampsLoudSource() {
        // Source already louder than target (-10 LUFS vs -16 target).
        // Raw offset is -6 dB — clamped to the lower bound of -6 dB.
        XCTAssertEqual(EncodeJob.gainOffsetDB(from: -10.0), -6.0, accuracy: 0.001)
        // And anything louder still: same clamp.
        XCTAssertEqual(EncodeJob.gainOffsetDB(from: -5.0), -6.0, accuracy: 0.001)
    }

    func test_gainOffsetDB_clampsExtremelyQuietSource() {
        // Source at -50 LUFS would want +34 dB; clamp to +20.
        XCTAssertEqual(EncodeJob.gainOffsetDB(from: -50.0), 20.0, accuracy: 0.001)
    }

    func test_gainOffsetDB_roundsToOneDecimal() {
        // Source at -22.37 LUFS → +6.37 raw → +6.4 rounded.
        XCTAssertEqual(EncodeJob.gainOffsetDB(from: -22.37), 6.4, accuracy: 0.001)
    }

    // MARK: - ebur128 measure args

    func test_ebur128MeasureArgs_decodeOnly_noEncoderFlags() {
        // Arrange / Act
        let args = EncodeJob.ebur128MeasureArgs(
            input: URL(fileURLWithPath: "/chapter.mp3")
        )

        // Assert
        XCTAssertEqual(args[adjacent: "-af"], "ebur128")
        XCTAssertEqual(args[adjacent: "-f"], "null")
        XCTAssertTrue(args.contains("-vn"))
        // No `-c:a` — we don't want to encode anything
        XCTAssertNil(args[adjacent: "-c:a"])
        // No bitrate / sample rate / channel pinning either
        XCTAssertNil(args[adjacent: "-b:a"])
        XCTAssertNil(args[adjacent: "-ar"])
        XCTAssertNil(args[adjacent: "-ac"])
    }

    func test_ebur128MeasureArgs_capsMeasurementWindow() {
        // Per-chapter measurement is capped so a 30-chapter book doesn't
        // spend minutes decoding hours of audio just to learn the level.
        // The cap is documented as ~0.3 LU accurate vs full-file for
        // typical speech content.
        let args = EncodeJob.ebur128MeasureArgs(
            input: URL(fileURLWithPath: "/chapter.mp3")
        )
        XCTAssertEqual(args[adjacent: "-t"], String(EncodeJob.ebur128MeasureCapSeconds))
        XCTAssertEqual(EncodeJob.ebur128MeasureCapSeconds, 120)
    }

    // MARK: - parseEbur128IntegratedLUFS

    func test_parseEbur128_extractsIntegratedLUFS_fromRealOutput() {
        // Arrange — actual stderr from ffmpeg 7.1 ebur128 on a real
        // audiobook chapter (Stephen Baxter, Evolution Chapter 1).
        // This is the load-bearing format-pin test.
        let stderr = """
        [Parsed_ebur128_0 @ 0xa3c024f80] t: 4.999977   TARGET:-23 LUFS    M: -41.8 S: -21.3     I: -19.7 LUFS       LRA:   1.3 LU
        [Parsed_ebur128_0 @ 0xa3c024f80] Summary:

          Integrated loudness:
            I:         -19.7 LUFS
            Threshold: -31.8 LUFS

          Loudness range:
            LRA:         1.3 LU
            Threshold: -40.4 LUFS
            LRA low:   -21.2 LUFS
            LRA high:  -19.9 LUFS
        """

        // Act
        let result = EncodeJob.parseEbur128IntegratedLUFS(stderr)

        // Assert — the value from the *summary block*, not the per-
        // frame streaming lines above.
        XCTAssertEqual(result ?? .nan, -19.7, accuracy: 0.001)
    }

    func test_parseEbur128_picksSummaryNotStreamingLine() {
        // Arrange — streaming line says I: -19.7 (the running estimate
        // partway through), but the actual integrated value at end of
        // stream is -22.1. Parser must return -22.1.
        let stderr = """
        [Parsed_ebur128_0 @ 0x1] t: 0.5  M: -25 S: -22   I: -19.7 LUFS
        [Parsed_ebur128_0 @ 0x1] t: 1.0  M: -28 S: -23   I: -19.9 LUFS
        [Parsed_ebur128_0 @ 0x1] Summary:

          Integrated loudness:
            I:         -22.1 LUFS
            Threshold: -33.4 LUFS
        """

        // Act / Assert
        XCTAssertEqual(EncodeJob.parseEbur128IntegratedLUFS(stderr) ?? .nan, -22.1, accuracy: 0.001)
    }

    func test_parseEbur128_returnsNilOnMissingSummary() {
        // Arrange — error case, ebur128 didn't print a summary
        let stderr = "ffmpeg version 7.1 …\nSome error happened"

        // Act / Assert
        XCTAssertNil(EncodeJob.parseEbur128IntegratedLUFS(stderr))
    }

    func test_parseEbur128_returnsNilOnEmpty() {
        XCTAssertNil(EncodeJob.parseEbur128IntegratedLUFS(""))
    }

    // MARK: - combineLoudness (duration-weighted average)

    func test_combineLoudness_identity_whenAllChaptersSameLUFS() {
        // Arrange — every chapter at -20 LUFS, varying durations
        let result = EncodeJob.combineLoudness(
            chapterIs: [-20.0, -20.0, -20.0],
            durations: [60, 120, 240]
        )

        // Assert — answer is -20 LUFS regardless of durations
        XCTAssertEqual(result ?? .nan, -20.0, accuracy: 0.001)
    }

    func test_combineLoudness_weightedTowardLongerChapter() throws {
        // Arrange — one short loud chapter, one long quiet chapter.
        // The combined value should be much closer to the quiet one.
        let result = EncodeJob.combineLoudness(
            chapterIs: [-10.0, -30.0],
            durations: [1, 99] // 1s loud, 99s quiet
        )

        // Assert — closer to -30 than to -10
        XCTAssertNotNil(result)
        let r = try XCTUnwrap(result)
        XCTAssertLessThan(r, -25.0, "expected to be pulled toward the long quiet chapter")
    }

    func test_combineLoudness_nilOnEmptyInput() {
        // Arrange / Act / Assert
        XCTAssertNil(EncodeJob.combineLoudness(chapterIs: [], durations: []))
    }

    func test_combineLoudness_nilWhenAllChaptersSilent() {
        // Arrange — ebur128 prints `-inf` for silent streams; we parse
        // that as a non-finite Double. All-silent input should yield nil
        // rather than crash or return -inf.
        let result = EncodeJob.combineLoudness(
            chapterIs: [-.infinity, -.infinity, .nan],
            durations: [60, 90, 30]
        )
        XCTAssertNil(result)
    }

    func test_combineLoudness_skipsZeroDurationChapters() {
        // Arrange — one zero-duration chapter shouldn't influence the
        // average (it has no audio).
        let result = EncodeJob.combineLoudness(
            chapterIs: [-20.0, -100.0],
            durations: [60, 0] // -100 LUFS but zero duration → ignored
        )

        // Assert
        XCTAssertEqual(result ?? .nan, -20.0, accuracy: 0.001)
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
}

/// Shared with ParallelEncodeTests; redeclared here as fileprivate so we
/// don't need to alter visibility in the existing test file.
private extension [String] {
    subscript(adjacent key: String) -> String? {
        guard let i = firstIndex(of: key), i + 1 < count else { return nil }
        return self[i + 1]
    }
}
