import XCTest
@testable import AudiobookForge

final class CancelTokenTests: XCTestCase {
    func test_setOnCancel_firesWhenCancelled() {
        // Arrange
        let token = CancelToken()
        var fired = false
        token.setOnCancel { fired = true }

        // Act
        token.cancel()

        // Assert
        XCTAssertTrue(fired)
        XCTAssertTrue(token.isCancelled)
    }

    func test_setOnCancel_afterCancel_firesImmediately() {
        // Arrange — cancel first; a handler registered late must still be
        // told (this is what covers the ffmpeg spawn window: cancel lands
        // while Process is launching, kill handler registers just after).
        let token = CancelToken()
        token.cancel()
        var fired = false

        // Act
        token.setOnCancel { fired = true }

        // Assert
        XCTAssertTrue(fired)
    }

    func test_setOnCancel_appendsHandlersInsteadOfReplacing() {
        // Arrange — EncodeJob registers a fan-out handler AND FFmpegRunner
        // registers a terminate handler on the same token; both must fire.
        let token = CancelToken()
        var count = 0
        token.setOnCancel { count += 1 }
        token.setOnCancel { count += 1 }

        // Act
        token.cancel()

        // Assert
        XCTAssertEqual(count, 2)
    }

    func test_cancel_isIdempotent() {
        // Arrange
        let token = CancelToken()
        var count = 0
        token.setOnCancel { count += 1 }

        // Act
        token.cancel()
        token.cancel()

        // Assert — handlers run exactly once
        XCTAssertEqual(count, 1)
    }
}
