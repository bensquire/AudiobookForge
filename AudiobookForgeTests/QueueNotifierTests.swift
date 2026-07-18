import XCTest
@testable import AudiobookForge

final class QueueNotifierTests: XCTestCase {
    func test_summary_allSucceeded() {
        // Arrange / Act / Assert
        XCTAssertEqual(QueueNotifier.summary(succeeded: 1, failed: 0), "1 book encoded")
        XCTAssertEqual(QueueNotifier.summary(succeeded: 3, failed: 0), "3 books encoded")
    }

    func test_summary_allFailed() {
        // Arrange / Act / Assert
        XCTAssertEqual(QueueNotifier.summary(succeeded: 0, failed: 1), "1 book failed")
        XCTAssertEqual(QueueNotifier.summary(succeeded: 0, failed: 2), "2 books failed")
    }

    func test_summary_mixedOutcome() {
        // Arrange / Act / Assert
        XCTAssertEqual(
            QueueNotifier.summary(succeeded: 2, failed: 1),
            "2 books encoded, 1 failed"
        )
    }
}
