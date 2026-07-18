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
}
