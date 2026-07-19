import XCTest
@testable import ForgeCore

/// Batch lifecycle: the pump should report exactly one start per burst of
/// work and one finish (with counts) when the queue drains. Items here use
/// nonexistent sources so preflight fails them fast — no ffmpeg involved.
@MainActor
final class QueueManagerBatchTests: QueueTestCase {
    func test_batch_firesStartedOnceAndFinishedWithFailureCounts() async {
        // Arrange — two items whose sources don't exist, so both fail in
        // preflight and the queue drains on its own.
        let queue = QueueManager()
        var startedCount = 0
        var finishedCounts: (succeeded: Int, failed: Int)?
        let drained = expectation(description: "batch finished")
        queue.onBatchStarted = { startedCount += 1 }
        queue.onBatchFinished = { succeeded, failed in
            finishedCounts = (succeeded, failed)
            drained.fulfill()
        }

        // Act
        _ = queue.enqueue(from: makeDraft(outputDir: tmp, title: "A"))
        _ = queue.enqueue(from: makeDraft(outputDir: tmp, title: "B"))
        await fulfillment(of: [drained], timeout: 10)

        // Assert — one batch, not one event per item
        XCTAssertEqual(startedCount, 1)
        XCTAssertEqual(finishedCounts?.succeeded, 0)
        XCTAssertEqual(finishedCounts?.failed, 2)
    }

    func test_batch_countsResetBetweenBatches() async {
        // Arrange — run one batch to completion first
        let queue = QueueManager()
        var lastCounts: (succeeded: Int, failed: Int)?
        var drained = expectation(description: "first batch")
        queue.onBatchFinished = { succeeded, failed in
            lastCounts = (succeeded, failed)
            drained.fulfill()
        }
        _ = queue.enqueue(from: makeDraft(outputDir: tmp, title: "A"))
        await fulfillment(of: [drained], timeout: 10)

        // Act — a second, separate batch
        drained = expectation(description: "second batch")
        _ = queue.enqueue(from: makeDraft(outputDir: tmp, title: "B"))
        await fulfillment(of: [drained], timeout: 10)

        // Assert — second batch reports only its own item, not a running total
        XCTAssertEqual(lastCounts?.failed, 1)
    }
}
