import XCTest
@testable import AudiobookForge

/// Pins `AudioProbe.parseBitrateFromFFmpegBanner` against captured stderr
/// from the pinned ffmpeg version (see `scripts/build-ffmpeg.sh`). If
/// upstream ever rewords this output, both this test suite and the
/// parser need updating in lockstep — bumping ffmpeg without rerunning
/// these tests would silently regress bitrate detection for MP3 sources
/// with embedded cover art (the very bug the parser exists to fix).
final class AudioProbeBitrateParseTests: XCTestCase {
    func test_parse_cbrMP3_64kbps() {
        // Arrange — real banner from a 64kbps CBR MP3 (Stephen Baxter
        // audiobook, captured during workstream A bring-up).
        let banner = """
        Input #0, mp3, from '/path/to/Evolution 09.mp3':
          Duration: 01:23:15.19, start: 0.000000, bitrate: 64 kb/s
          Stream #0:0: Audio: mp3, 44100 Hz, stereo, s16p, 64 kb/s
        """

        // Act
        let result = AudioProbe.parseBitrateFromFFmpegBanner(banner)

        // Assert — 64 kb/s → 64_000 bits/sec
        XCTAssertEqual(result, 64000)
    }

    func test_parse_aac_96kbps_picksStreamNotContainer() {
        // Arrange — AAC in MP4. ffmpeg prints both a container-level
        // bitrate (100 kb/s, includes overhead) and a stream-specific
        // one (96 kb/s). The parser must return the stream value
        // because that's the codec-level truth.
        let banner = """
        Input #0, mov,mp4,m4a,3gp,3g2,mj2, from '/tmp/sample.m4a':
          Duration: 00:00:05.00, start: 0.000000, bitrate: 100 kb/s
          Stream #0:0[0x1](und): Audio: aac (mp4a / 0x6134706D), 44100 Hz, stereo, fltp, 96 kb/s (default)
        """

        // Act
        let result = AudioProbe.parseBitrateFromFFmpegBanner(banner)

        // Assert
        XCTAssertEqual(result, 96000)
    }

    func test_parse_picksLastKbpsTokenOnAudioLine() {
        // Arrange — synthetic line with multiple `N kb/s` tokens. The
        // parser walks them and keeps the last, which matches how
        // ffmpeg orders stream-then-extras for some codecs.
        let banner = """
        Input #0, somefmt, …:
          Stream #0:0: Audio: aac, 44100 Hz, stereo, 80 kb/s, oddly 128 kb/s tail
        """

        // Act / Assert
        XCTAssertEqual(AudioProbe.parseBitrateFromFFmpegBanner(banner), 128_000)
    }

    func test_parse_skipsContainerDurationLine() {
        // Arrange — `bitrate: …` appears on the Duration line and again
        // on the Audio line. Parser must scan Audio: lines only and
        // ignore container-level numbers on Duration.
        let banner = """
        Input #0, wav, from '/x.wav':
          Duration: 00:01:00.00, bitrate: 999 kb/s
          Stream #0:0: Audio: pcm_s16le, 44100 Hz, 2 channels, s16, 1411 kb/s
        """

        // Act / Assert — gets the Audio-line value, not the Duration one.
        XCTAssertEqual(AudioProbe.parseBitrateFromFFmpegBanner(banner), 1_411_000)
    }

    func test_parse_returnsNil_whenNoAudioLine() {
        // Arrange — error banner, no streams parsed
        let banner = """
        Input #0, mp3, from '/missing.mp3':
          [matroska,webm @ 0x1] EBML header parsing failed
        """

        // Act
        let result = AudioProbe.parseBitrateFromFFmpegBanner(banner)

        // Assert
        XCTAssertNil(result)
    }

    func test_parse_returnsNil_whenAudioLineHasNoKbpsToken() {
        // Arrange — pathological banner: Audio line exists but no
        // bitrate token (e.g. ffmpeg failed to determine it).
        let banner = """
        Stream #0:0: Audio: aac, 44100 Hz, stereo, fltp
        """

        // Act / Assert
        XCTAssertNil(AudioProbe.parseBitrateFromFFmpegBanner(banner))
    }

    func test_parse_returnsNil_onEmptyInput() {
        XCTAssertNil(AudioProbe.parseBitrateFromFFmpegBanner(""))
    }

    func test_parse_handlesWhitespaceVariants() {
        // Arrange — ffmpeg sometimes inserts extra spaces around values
        // depending on locale; the regex tolerates that.
        let banner = """
        Stream #0:0: Audio: aac, 44100 Hz, mono, 32  kb/s
        """

        // Act / Assert
        XCTAssertEqual(AudioProbe.parseBitrateFromFFmpegBanner(banner), 32000)
    }
}
