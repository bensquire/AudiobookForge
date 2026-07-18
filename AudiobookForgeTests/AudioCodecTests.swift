import CoreMedia
import XCTest
@testable import AudiobookForge

final class AudioCodecTests: XCTestCase {
    func test_init_recognisesAAC() {
        // Arrange — kAudioFormatMPEG4AAC FourCC
        let fourCC: FourCharCode = 0x6161_6320 // 'aac '

        // Act
        let codec = AudioCodec(fourCC: fourCC)

        // Assert
        XCTAssertEqual(codec, .aac)
    }

    func test_init_recognisesMP3() {
        // Arrange
        let fourCC: FourCharCode = 0x2E6D_7033 // '.mp3'

        // Act
        let codec = AudioCodec(fourCC: fourCC)

        // Assert
        XCTAssertEqual(codec, .mp3)
    }

    func test_init_recognisesHEAACProfilesAsDistinctCodecs() {
        // Arrange — kAudioFormatMPEG4AAC_HE / _HE_V2 FourCCs. These must
        // NOT collapse into .aac: LC and HE bitstreams can't be mixed in
        // one `-c:a copy` concat, and codec equality is what canRemux
        // relies on to prevent that.
        let heFourCC: FourCharCode = 0x6161_6368 // 'aach'
        let heV2FourCC: FourCharCode = 0x6161_6370 // 'aacp'

        // Act
        let he = AudioCodec(fourCC: heFourCC)
        let heV2 = AudioCodec(fourCC: heV2FourCC)

        // Assert
        XCTAssertEqual(he, .aacHE)
        XCTAssertEqual(heV2, .aacHEv2)
        XCTAssertNotEqual(he, .aac)
        XCTAssertNotEqual(heV2, .aac)
    }

    func test_init_recognisesALAC() {
        // Arrange
        let fourCC: FourCharCode = 0x616C_6163 // 'alac'

        // Act
        let codec = AudioCodec(fourCC: fourCC)

        // Assert
        XCTAssertEqual(codec, .alac)
    }

    func test_init_recognisesPCM() {
        // Arrange — kAudioFormatLinearPCM
        let fourCC: FourCharCode = 0x6C70_636D // 'lpcm'

        // Act
        let codec = AudioCodec(fourCC: fourCC)

        // Assert
        XCTAssertEqual(codec, .pcm)
    }

    func test_init_unknownFourCC_returnsUnknown() {
        // Arrange — made-up FourCC
        let fourCC: FourCharCode = 0x787A_7A7A // 'xzzz'

        // Act
        let codec = AudioCodec(fourCC: fourCC)

        // Assert
        XCTAssertEqual(codec, .unknown("xzzz"))
    }

    func test_isMP4RemuxFriendly_trueOnlyForAACFamily() {
        // Arrange / Act / Assert — only the AAC family may be remuxed
        // straight into an .m4b without re-encoding. Uniform HE books get
        // the fast path too; mixing profiles is blocked by canRemux's
        // codec-equality check, not here.
        XCTAssertTrue(AudioCodec.aac.isMP4RemuxFriendly)
        XCTAssertTrue(AudioCodec.aacHE.isMP4RemuxFriendly)
        XCTAssertTrue(AudioCodec.aacHEv2.isMP4RemuxFriendly)
        XCTAssertFalse(AudioCodec.mp3.isMP4RemuxFriendly)
        XCTAssertFalse(AudioCodec.alac.isMP4RemuxFriendly)
        XCTAssertFalse(AudioCodec.opus.isMP4RemuxFriendly)
        XCTAssertFalse(AudioCodec.flac.isMP4RemuxFriendly)
        XCTAssertFalse(AudioCodec.unknown("xxxx").isMP4RemuxFriendly)
    }
}
