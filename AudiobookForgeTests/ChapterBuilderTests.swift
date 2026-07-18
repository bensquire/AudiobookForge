import XCTest
@testable import AudiobookForge

final class ChapterBuilderTests: XCTestCase {
    // MARK: - concat list

    func test_concatList_emitsOneLinePerChapter() {
        // Arrange
        let chapters = [
            Chapter(sourceURL: URL(fileURLWithPath: "/tmp/a.mp3"), title: "A", duration: 1),
            Chapter(sourceURL: URL(fileURLWithPath: "/tmp/b.mp3"), title: "B", duration: 1)
        ]

        // Act
        let list = ChapterBuilder.concatList(for: chapters)

        // Assert
        XCTAssertEqual(list, "file '/tmp/a.mp3'\nfile '/tmp/b.mp3'\n")
    }

    func test_concatList_escapesSingleQuotesInPaths() {
        // Arrange — apostrophe in the path is the ffmpeg concat demuxer's
        // one quoting hazard.
        let chapters = [
            Chapter(sourceURL: URL(fileURLWithPath: "/tmp/Don't Look.mp3"), title: "T", duration: 1)
        ]

        // Act
        let list = ChapterBuilder.concatList(for: chapters)

        // Assert — `'` becomes `'\''` (close, escaped, reopen)
        XCTAssertEqual(list, "file '/tmp/Don'\\''t Look.mp3'\n")
    }

    // MARK: - ffmetadata

    func test_ffmetadata_includesBookLevelTags() {
        // Arrange
        var meta = BookMetadata()
        meta.title = "Dune"
        meta.author = "Frank Herbert"
        meta.year = "1965"
        meta.narrator = "Scott Brick"

        // Act
        let text = ChapterBuilder.ffmetadata(for: [], metadata: meta)

        // Assert
        XCTAssertTrue(text.hasPrefix(";FFMETADATA1\n"))
        XCTAssertTrue(text.contains("title=Dune\n"))
        XCTAssertTrue(text.contains("artist=Frank Herbert\n"))
        XCTAssertTrue(text.contains("date=1965\n"))
        // Narrator is mapped onto the de-facto `composer` tag.
        XCTAssertTrue(text.contains("composer=Scott Brick\n"))
    }

    func test_ffmetadata_defaultsToAudiobookGenreWhenBlank() {
        // Arrange
        var meta = BookMetadata()
        meta.title = "x"
        meta.author = "y"

        // Act
        let text = ChapterBuilder.ffmetadata(for: [], metadata: meta)

        // Assert
        XCTAssertTrue(text.contains("genre=Audiobook\n"))
    }

    func test_ffmetadata_marksFileAsAudiobook() {
        // Arrange
        var meta = BookMetadata()
        meta.title = "x"
        meta.author = "y"

        // Act
        let text = ChapterBuilder.ffmetadata(for: [], metadata: meta)

        // Assert — media_type=2 becomes the mp4 `stik` atom that makes
        // Apple Books / iTunes treat the file as an audiobook.
        XCTAssertTrue(text.contains("media_type=2\n"))
    }

    func test_ffmetadata_seriesRidesOnAtomsTheMP4MuxerActuallyWrites() {
        // Arrange — ffmpeg's mp4 muxer drops unknown keys (the old
        // TXXX:* tags never reached the file), so series must ride on
        // `show`/`episode_sort`/`grouping`.
        var meta = BookMetadata()
        meta.title = "x"
        meta.author = "y"
        meta.series = "Dune Saga"
        meta.seriesPosition = "3"

        // Act
        let text = ChapterBuilder.ffmetadata(for: [], metadata: meta)

        // Assert
        XCTAssertTrue(text.contains("show=Dune Saga\n"))
        XCTAssertTrue(text.contains("episode_sort=3\n"))
        XCTAssertTrue(text.contains("grouping=Dune Saga \\#3\n"))
        XCTAssertFalse(text.contains("TXXX"))
    }

    func test_ffmetadata_nonIntegerSeriesPositionSkipsEpisodeSort() {
        // Arrange — "3.5" novellas are common; `tves` is an integer atom
        // so a fractional position must not be written there.
        var meta = BookMetadata()
        meta.title = "x"
        meta.author = "y"
        meta.series = "Dune Saga"
        meta.seriesPosition = "3.5"

        // Act
        let text = ChapterBuilder.ffmetadata(for: [], metadata: meta)

        // Assert — grouping still carries the human-readable form
        XCTAssertFalse(text.contains("episode_sort="))
        XCTAssertTrue(text.contains("grouping=Dune Saga \\#3.5\n"))
    }

    func test_ffmetadata_chaptersCarryConsecutiveMillisecondRanges() {
        // Arrange — two 1500 ms chapters
        let chapters = [
            Chapter(sourceURL: URL(fileURLWithPath: "/tmp/a.mp3"), title: "One", duration: 1.5),
            Chapter(sourceURL: URL(fileURLWithPath: "/tmp/b.mp3"), title: "Two", duration: 1.5)
        ]

        // Act
        let text = ChapterBuilder.ffmetadata(for: chapters, metadata: BookMetadata())

        // Assert — first chapter 0..1499, second 1500..2999 (end inclusive)
        XCTAssertTrue(text.contains("[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=1499\ntitle=One\n"))
        XCTAssertTrue(text.contains("[CHAPTER]\nTIMEBASE=1/1000\nSTART=1500\nEND=2999\ntitle=Two\n"))
    }

    func test_ffmetadata_escapesSpecialCharacters() {
        // Arrange — ffmetadata requires escaping =, ;, #, \ and newlines.
        var meta = BookMetadata()
        meta.title = "A = B; C # D"
        meta.author = "z"

        // Act
        let text = ChapterBuilder.ffmetadata(for: [], metadata: meta)

        // Assert
        XCTAssertTrue(text.contains("title=A \\= B\\; C \\# D\n"))
    }
}
