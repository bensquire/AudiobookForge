import XCTest
@testable import AudiobookForge

final class BookMetadataTests: XCTestCase {
    func test_isEmpty_trueOnDefaultInit() {
        // Arrange
        let meta = BookMetadata()

        // Act / Assert
        XCTAssertTrue(meta.isEmpty)
    }

    func test_isEmpty_falseWhenAnyOfTitleAuthorNarratorIsSet() {
        // Arrange — three independent fields that "count"
        var withTitle = BookMetadata(); withTitle.title = "x"
        var withAuthor = BookMetadata(); withAuthor.author = "x"
        var withNarrator = BookMetadata(); withNarrator.narrator = "x"

        // Act / Assert
        XCTAssertFalse(withTitle.isEmpty)
        XCTAssertFalse(withAuthor.isEmpty)
        XCTAssertFalse(withNarrator.isEmpty)
    }

    func test_hasRequiredFields_requiresBothTitleAndAuthor() {
        // Arrange
        var titleOnly = BookMetadata(); titleOnly.title = "x"
        var authorOnly = BookMetadata(); authorOnly.author = "x"
        var both = BookMetadata(); both.title = "x"; both.author = "y"

        // Act / Assert
        XCTAssertFalse(titleOnly.hasRequiredFields)
        XCTAssertFalse(authorOnly.hasRequiredFields)
        XCTAssertTrue(both.hasRequiredFields)
    }

    func test_hasRequiredFields_ignoresWhitespaceOnlyValues() {
        // Arrange — user pasted whitespace into both fields by accident
        var meta = BookMetadata()
        meta.title = "   "
        meta.author = "\t\n"

        // Act
        let ok = meta.hasRequiredFields

        // Assert
        XCTAssertFalse(ok)
    }
}
