import XCTest
@testable import AudiobookForge

final class ChapterImportTests: XCTestCase {
    func test_dedupe_dropsURLsAlreadyInTheChapterList() {
        // Arrange — one incoming file is already a chapter source
        let incoming = [
            URL(fileURLWithPath: "/books/ch1.mp3"),
            URL(fileURLWithPath: "/books/ch2.mp3")
        ]
        let existing: Set = ["/books/ch1.mp3"]

        // Act
        let result = ChapterImport.dedupe(incoming, existingPaths: existing)

        // Assert
        XCTAssertEqual(result.map(\.path), ["/books/ch2.mp3"])
    }

    func test_dedupe_dropsDuplicatesWithinTheSameBatch() {
        // Arrange — two overlapping folders dropped together yield the
        // same file twice in one import
        let incoming = [
            URL(fileURLWithPath: "/books/ch1.mp3"),
            URL(fileURLWithPath: "/books/ch1.mp3"),
            URL(fileURLWithPath: "/books/ch2.mp3")
        ]

        // Act
        let result = ChapterImport.dedupe(incoming, existingPaths: [])

        // Assert — order preserved, duplicate collapsed
        XCTAssertEqual(result.map(\.path), ["/books/ch1.mp3", "/books/ch2.mp3"])
    }

    func test_dedupe_standardizesPathsBeforeComparing() {
        // Arrange — same file reached via a redundant "./" path component
        let incoming = [
            URL(fileURLWithPath: "/books/./ch1.mp3"),
            URL(fileURLWithPath: "/books/ch1.mp3")
        ]

        // Act
        let result = ChapterImport.dedupe(incoming, existingPaths: [])

        // Assert
        XCTAssertEqual(result.count, 1)
    }

    func test_dedupe_emptyInputYieldsEmptyOutput() {
        // Arrange / Act / Assert
        XCTAssertTrue(ChapterImport.dedupe([], existingPaths: ["/x"]).isEmpty)
    }

    // MARK: - partitionFinished

    private func probed(_ path: String, hasChapters: Bool) -> (url: URL, info: AudioProbe.Probed) {
        var info = AudioProbe.Probed(duration: 60)
        info.hasChapters = hasChapters
        return (URL(fileURLWithPath: path), info)
    }

    func test_partitionFinished_skipsChapteredFilesAndKeepsOrder() {
        // Arrange — a mixed batch: finished m4b between two loose MP3s.
        let batch = [
            probed("/books/ch1.mp3", hasChapters: false),
            probed("/books/Finished Book.m4b", hasChapters: true),
            probed("/books/ch2.mp3", hasChapters: false)
        ]

        // Act
        let (importable, skipped) = ChapterImport.partitionFinished(batch)

        // Assert — importables keep their relative order; the skipped
        // list carries display names for the alert.
        XCTAssertEqual(importable.map(\.url.lastPathComponent), ["ch1.mp3", "ch2.mp3"])
        XCTAssertEqual(skipped, ["Finished Book.m4b"])
    }

    func test_partitionFinished_allFinishedYieldsNothingImportable() {
        // Arrange
        let batch = [
            probed("/books/a.m4b", hasChapters: true),
            probed("/books/b.m4b", hasChapters: true)
        ]

        // Act
        let (importable, skipped) = ChapterImport.partitionFinished(batch)

        // Assert
        XCTAssertTrue(importable.isEmpty)
        XCTAssertEqual(skipped, ["a.m4b", "b.m4b"])
    }

    func test_partitionFinished_chapterlessBatchPassesThroughUntouched() {
        // Arrange
        let batch = [
            probed("/books/ch1.mp3", hasChapters: false),
            probed("/books/ch2.mp3", hasChapters: false)
        ]

        // Act
        let (importable, skipped) = ChapterImport.partitionFinished(batch)

        // Assert
        XCTAssertEqual(importable.count, 2)
        XCTAssertTrue(skipped.isEmpty)
    }
}
