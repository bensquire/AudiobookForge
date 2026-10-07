import XCTest
@testable import ForgeCore

/// The human spellings `forge.yml` accepts for bitrate and gain. Strict
/// on purpose: anything not listed is nil so the config loader can
/// reject it up front instead of encoding with a silent default.
final class EncodeSettingsParsingTests: XCTestCase {
    // MARK: - Bitrate

    func test_bitrate_acceptsSourceSpellings() {
        // Arrange / Act / Assert
        XCTAssertEqual(EncodeSettings.Bitrate(userSpelling: "source"), .source)
        XCTAssertEqual(EncodeSettings.Bitrate(userSpelling: "Match source"), .source)
    }

    func test_bitrate_acceptsNumberWithOrWithoutUnit() {
        // Arrange / Act / Assert
        XCTAssertEqual(EncodeSettings.Bitrate(userSpelling: "64k"), .k64)
        XCTAssertEqual(EncodeSettings.Bitrate(userSpelling: "64"), .k64)
        XCTAssertEqual(EncodeSettings.Bitrate(userSpelling: "128 kbps"), .k128)
        XCTAssertEqual(EncodeSettings.Bitrate(userSpelling: "192K"), .k192)
    }

    func test_bitrate_rejectsUnsupportedValues() {
        // Arrange / Act / Assert
        XCTAssertNil(EncodeSettings.Bitrate(userSpelling: "48k"))
        XCTAssertNil(EncodeSettings.Bitrate(userSpelling: "64m"))
        XCTAssertNil(EncodeSettings.Bitrate(userSpelling: ""))
        XCTAssertNil(EncodeSettings.Bitrate(userSpelling: "high"))
    }

    // MARK: - GainBoost

    func test_gain_acceptsOffAndAutoSpellings() {
        // Arrange / Act / Assert
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "off"), .off)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "none"), .off)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "auto"), .autoNormalize)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "auto-normalize"), .autoNormalize)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "Normalise"), .autoNormalize)
    }

    func test_gain_acceptsAutoIfQuietSpellings() {
        // Arrange / Act / Assert
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "auto-if-quiet"), .autoIfQuiet)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "Auto If Quiet"), .autoIfQuiet)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "lift-if-quiet"), .autoIfQuiet)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "auto_if_quiet"), .autoIfQuiet)
    }

    func test_gain_acceptsFixedStepsWithOptionalSignAndUnit() {
        // Arrange / Act / Assert
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "3"), .dB3)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "+6"), .dB6)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "9dB"), .dB9)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "+12 dB"), .dB12)
    }

    func test_gain_rejectsStepsTheAppDoesNotOffer() {
        // Arrange / Act / Assert
        XCTAssertNil(EncodeSettings.GainBoost(userSpelling: "5"))
        XCTAssertNil(EncodeSettings.GainBoost(userSpelling: "+15"))
        XCTAssertNil(EncodeSettings.GainBoost(userSpelling: "loud"))
        XCTAssertNil(EncodeSettings.GainBoost(userSpelling: ""))
    }

    func test_decoding_acceptsUserSpellings() throws {
        // Arrange — what a YAML/JSON config would hand the decoder.
        let gainJSON = Data(#"["+6", "auto-if-quiet", "dB3"]"#.utf8)
        let bitrateJSON = Data(#"["64", "source"]"#.utf8)

        // Act
        let gains = try JSONDecoder().decode([EncodeSettings.GainBoost].self, from: gainJSON)
        let bitrates = try JSONDecoder().decode([EncodeSettings.Bitrate].self, from: bitrateJSON)

        // Assert
        XCTAssertEqual(gains, [.dB6, .autoIfQuiet, .dB3])
        XCTAssertEqual(bitrates, [.k64, .source])
    }

    func test_decoding_rejectsAnUnknownSpellingAndNamesTheAcceptedOnes() {
        // Arrange
        let bad = Data(#"["loud"]"#.utf8)

        // Act / Assert
        XCTAssertThrowsError(try JSONDecoder().decode([EncodeSettings.GainBoost].self, from: bad)) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("auto-if-quiet"), context.debugDescription)
        }
    }

    func test_enums_roundTripThroughCodable() throws {
        // Arrange / Act
        let encoded = try JSONEncoder().encode([EncodeSettings.Bitrate.k96])
        let gain = try JSONEncoder().encode([EncodeSettings.GainBoost.autoNormalize])
        let bitrates = try JSONDecoder().decode([EncodeSettings.Bitrate].self, from: encoded)
        let gains = try JSONDecoder().decode([EncodeSettings.GainBoost].self, from: gain)

        // Assert
        XCTAssertEqual(bitrates, [.k96])
        XCTAssertEqual(gains, [.autoNormalize])
    }
}
