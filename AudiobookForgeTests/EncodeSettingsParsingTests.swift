import XCTest
@testable import ForgeCore

/// The human spellings `forge.yml` accepts for bitrate and gain. Strict
/// on purpose: anything not listed is nil so the config loader can
/// reject it up front instead of encoding with a silent default.
final class EncodeSettingsParsingTests: XCTestCase {
    // MARK: - Bitrate

    func test_bitrate_acceptsSourceSpellings() {
        XCTAssertEqual(EncodeSettings.Bitrate(userSpelling: "source"), .source)
        XCTAssertEqual(EncodeSettings.Bitrate(userSpelling: "Match source"), .source)
    }

    func test_bitrate_acceptsNumberWithOrWithoutUnit() {
        XCTAssertEqual(EncodeSettings.Bitrate(userSpelling: "64k"), .k64)
        XCTAssertEqual(EncodeSettings.Bitrate(userSpelling: "64"), .k64)
        XCTAssertEqual(EncodeSettings.Bitrate(userSpelling: "128 kbps"), .k128)
        XCTAssertEqual(EncodeSettings.Bitrate(userSpelling: "192K"), .k192)
    }

    func test_bitrate_rejectsUnsupportedValues() {
        XCTAssertNil(EncodeSettings.Bitrate(userSpelling: "48k"))
        XCTAssertNil(EncodeSettings.Bitrate(userSpelling: "64m"))
        XCTAssertNil(EncodeSettings.Bitrate(userSpelling: ""))
        XCTAssertNil(EncodeSettings.Bitrate(userSpelling: "high"))
    }

    // MARK: - GainBoost

    func test_gain_acceptsOffAndAutoSpellings() {
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "off"), .off)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "none"), .off)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "auto"), .autoNormalize)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "auto-normalize"), .autoNormalize)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "Normalise"), .autoNormalize)
    }

    func test_gain_acceptsAutoIfQuietSpellings() {
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "auto-if-quiet"), .autoIfQuiet)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "Auto If Quiet"), .autoIfQuiet)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "lift-if-quiet"), .autoIfQuiet)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "auto_if_quiet"), .autoIfQuiet)
    }

    func test_gain_acceptsFixedStepsWithOptionalSignAndUnit() {
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "3"), .dB3)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "+6"), .dB6)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "9dB"), .dB9)
        XCTAssertEqual(EncodeSettings.GainBoost(userSpelling: "+12 dB"), .dB12)
    }

    func test_gain_rejectsStepsTheAppDoesNotOffer() {
        XCTAssertNil(EncodeSettings.GainBoost(userSpelling: "5"))
        XCTAssertNil(EncodeSettings.GainBoost(userSpelling: "+15"))
        XCTAssertNil(EncodeSettings.GainBoost(userSpelling: "loud"))
        XCTAssertNil(EncodeSettings.GainBoost(userSpelling: ""))
    }

    func test_enums_roundTripThroughCodable() throws {
        let encoded = try JSONEncoder().encode([EncodeSettings.Bitrate.k96])
        XCTAssertEqual(try JSONDecoder().decode([EncodeSettings.Bitrate].self, from: encoded), [.k96])
        let gain = try JSONEncoder().encode([EncodeSettings.GainBoost.autoNormalize])
        XCTAssertEqual(
            try JSONDecoder().decode([EncodeSettings.GainBoost].self, from: gain), [.autoNormalize]
        )
    }
}
