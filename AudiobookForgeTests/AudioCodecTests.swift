import XCTest
import CoreMedia
@testable import AudiobookForge

final class AudioCodecTests: XCTestCase {

    func test_init_recognisesAAC() {
        // Arrange — kAudioFormatMPEG4AAC FourCC
        let fourCC: FourCharCode = 0x61616320 // 'aac '

        // Act
        let codec = AudioCodec(fourCC: fourCC)

        // Assert
        XCTAssertEqual(codec, .aac)
    }

    func test_init_recognisesMP3() {
        // Arrange
        let fourCC: FourCharCode = 0x2e6d7033 // '.mp3'

        // Act
        let codec = AudioCodec(fourCC: fourCC)

        // Assert
        XCTAssertEqual(codec, .mp3)
    }

    func test_init_recognisesALAC() {
        // Arrange
        let fourCC: FourCharCode = 0x616c6163 // 'alac'

        // Act
        let codec = AudioCodec(fourCC: fourCC)

        // Assert
        XCTAssertEqual(codec, .alac)
    }

    func test_init_recognisesPCM() {
        // Arrange — kAudioFormatLinearPCM
        let fourCC: FourCharCode = 0x6c70636d // 'lpcm'

        // Act
        let codec = AudioCodec(fourCC: fourCC)

        // Assert
        XCTAssertEqual(codec, .pcm)
    }

    func test_init_unknownFourCC_returnsUnknown() {
        // Arrange — made-up FourCC
        let fourCC: FourCharCode = 0x787a7a7a // 'xzzz'

        // Act
        let codec = AudioCodec(fourCC: fourCC)

        // Assert
        XCTAssertEqual(codec, .unknown("xzzz"))
    }

    func test_isMP4RemuxFriendly_trueOnlyForAAC() {
        // Arrange / Act / Assert — only AAC may be remuxed straight into
        // an .m4b without re-encoding.
        XCTAssertTrue(AudioCodec.aac.isMP4RemuxFriendly)
        XCTAssertFalse(AudioCodec.mp3.isMP4RemuxFriendly)
        XCTAssertFalse(AudioCodec.alac.isMP4RemuxFriendly)
        XCTAssertFalse(AudioCodec.opus.isMP4RemuxFriendly)
        XCTAssertFalse(AudioCodec.flac.isMP4RemuxFriendly)
        XCTAssertFalse(AudioCodec.unknown("xxxx").isMP4RemuxFriendly)
    }
}
