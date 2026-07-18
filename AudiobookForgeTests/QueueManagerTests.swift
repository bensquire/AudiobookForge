import XCTest
@testable import AudiobookForge

@MainActor
final class QueueManagerTests: QueueTestCase {
    // MARK: - plannedOutputURL

    func test_plannedOutputURL_returnsNilWithoutOutputDirectory() {
        // Arrange — no output dir, but everything else is fine
        let queue = QueueManager()
        let draft = makeDraft(outputDir: nil)

        // Act
        let planned = queue.plannedOutputURL(for: draft)

        // Assert
        XCTAssertNil(planned)
    }

    func test_plannedOutputURL_appliesTemplateAndDedupesAgainstDisk() throws {
        // Arrange — output dir has a pre-existing file at the template path
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let pre = tmp.appendingPathComponent("Dune.m4b")
        try Data().write(to: pre)
        let queue = QueueManager()
        let draft = makeDraft(outputDir: tmp, title: "Dune", template: "{title}.m4b")

        // Act
        let planned = queue.plannedOutputURL(for: draft)

        // Assert — collision pushed to "(2)"
        XCTAssertEqual(planned?.lastPathComponent, "Dune (2).m4b")
    }

    // MARK: - enqueue

    func test_enqueue_appendsItemAndReturnsIt() {
        // Arrange
        let queue = QueueManager()
        let draft = makeDraft(outputDir: tmp)

        // Act
        let item = queue.enqueue(from: draft)

        // Assert
        XCTAssertNotNil(item)
        XCTAssertEqual(queue.items.count, 1)
        XCTAssertEqual(queue.items.first?.id, item?.id)
    }

    func test_enqueue_failsWhenDraftIsIncomplete() {
        // Arrange — chapters present but no output dir
        let queue = QueueManager()
        let draft = makeDraft(outputDir: nil)

        // Act
        let item = queue.enqueue(from: draft)

        // Assert
        XCTAssertNil(item)
        XCTAssertTrue(queue.items.isEmpty)
    }

    func test_enqueue_dedupesAgainstOtherPendingItems() {
        // Arrange — two drafts with identical template output
        let queue = QueueManager()
        let first = makeDraft(outputDir: tmp, title: "Dune")
        let second = makeDraft(outputDir: tmp, title: "Dune")

        // Act
        _ = queue.enqueue(from: first)
        let second_item = queue.enqueue(from: second)

        // Assert — second item resolves to "Dune (2).m4b" before encode
        // starts, so the user sees the renamed path on the queue row.
        XCTAssertEqual(second_item?.spec.outputURL.lastPathComponent, "Dune (2).m4b")
    }

    // MARK: - cancel / remove

    func test_cancel_marksPendingItemCancelled() throws {
        // Arrange — enqueue two so the first stays pending (worker may
        // grab one but the second is definitely still pending)
        let queue = QueueManager()
        _ = queue.enqueue(from: makeDraft(outputDir: tmp, title: "A"))
        let second = try XCTUnwrap(queue.enqueue(from: makeDraft(outputDir: tmp, title: "B")))

        // Act — cancel before the worker can pick it up
        queue.cancel(second)

        // Assert
        XCTAssertEqual(second.status, .cancelled)
    }

    func test_remove_dropsFinishedItem() throws {
        // Arrange — enqueue then force a "succeeded" terminal state so
        // remove() takes the immediate-delete path.
        let queue = QueueManager()
        let item = try XCTUnwrap(queue.enqueue(from: makeDraft(outputDir: tmp)))
        item.status = .succeeded

        // Act
        queue.remove(item)

        // Assert
        XCTAssertTrue(queue.items.isEmpty)
    }

    func test_clearFinished_keepsActiveItems() throws {
        // Arrange
        let queue = QueueManager()
        let a = try XCTUnwrap(queue.enqueue(from: makeDraft(outputDir: tmp, title: "A")))
        let b = try XCTUnwrap(queue.enqueue(from: makeDraft(outputDir: tmp, title: "B")))
        a.status = .succeeded
        b.status = .pending

        // Act
        queue.clearFinished()

        // Assert
        XCTAssertEqual(queue.items.count, 1)
        XCTAssertEqual(queue.items.first?.id, b.id)
    }

    // MARK: - status helpers

    func test_status_isActive_isFinished_partitionCorrectly() {
        // Arrange / Act / Assert — sanity check the categorization
        XCTAssertTrue(QueueItem.Status.pending.isActive)
        XCTAssertTrue(QueueItem.Status.running.isActive)
        XCTAssertFalse(QueueItem.Status.succeeded.isActive)
        XCTAssertFalse(QueueItem.Status.failed("x").isActive)
        XCTAssertFalse(QueueItem.Status.cancelled.isActive)

        XCTAssertTrue(QueueItem.Status.succeeded.isFinished)
        XCTAssertTrue(QueueItem.Status.failed("x").isFinished)
        XCTAssertTrue(QueueItem.Status.cancelled.isFinished)
        XCTAssertFalse(QueueItem.Status.pending.isFinished)
        XCTAssertFalse(QueueItem.Status.running.isFinished)
    }

    func test_status_isRetryable_onlyForTerminalFailures() {
        // Arrange / Act / Assert
        XCTAssertTrue(QueueItem.Status.failed("x").isRetryable)
        XCTAssertTrue(QueueItem.Status.cancelled.isRetryable)
        XCTAssertFalse(QueueItem.Status.succeeded.isRetryable)
        XCTAssertFalse(QueueItem.Status.pending.isRetryable)
        XCTAssertFalse(QueueItem.Status.running.isRetryable)
    }
}
