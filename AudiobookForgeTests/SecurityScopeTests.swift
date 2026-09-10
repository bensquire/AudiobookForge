import XCTest
@testable import ForgeCore

/// The sandbox grants a test runner nothing, so the real
/// `startAccessingSecurityScopedResource()` refuses every URL a test can
/// build. These swap the two sandbox calls for a ledger and check the
/// bookkeeping around them: what is started is recorded, what is
/// released is exactly what nothing refers to any more, and every start
/// ends up balanced by one stop.
@MainActor
final class SecurityScopeTests: XCTestCase {
    private var started: [URL] = []
    private var stopped: [URL] = []

    override func setUp() async throws {
        try await super.setUp()
        started = []
        stopped = []
        SecurityScope.startAccess = { [self] url in
            started.append(url)
            return true
        }
        SecurityScope.stopAccess = { [self] url in stopped.append(url) }
    }

    override func tearDown() async throws {
        SecurityScope.releaseAll()
        SecurityScope.startAccess = { $0.startAccessingSecurityScopedResource() }
        SecurityScope.stopAccess = { $0.stopAccessingSecurityScopedResource() }
        try await super.tearDown()
    }

    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    // MARK: - retain

    func test_retain_takesTheGrantOncePerURL() {
        // Arrange / Act — the same file arrives twice, as a re-drop would.
        SecurityScope.retain(url("/books/ch1.mp3"))
        SecurityScope.retain(url("/books/ch1.mp3"))

        // Assert — one grant taken, one owed.
        XCTAssertEqual(started.count, 1, "started \(started.count) times for one URL")
        XCTAssertEqual(SecurityScope.heldCount, 1)
    }

    func test_retain_recordsNothingWhenTheGrantIsRefused() {
        // Arrange — a URL the sandbox will not grant, which is what a
        // path the app constructed itself looks like.
        SecurityScope.startAccess = { _ in false }

        // Act
        SecurityScope.retain(url("/books/ch1.mp3"))

        // Assert — nothing was granted, so nothing is owed a stop.
        XCTAssertEqual(SecurityScope.heldCount, 0)
        SecurityScope.releaseAll()
        XCTAssertTrue(stopped.isEmpty, "stopped a grant that was never started: \(stopped)")
    }

    // MARK: - releaseUnused

    func test_releaseUnused_releasesWhatNothingRefersTo() {
        // Arrange — two books imported, one of them then cleared.
        SecurityScope.retain(url("/books/kept.mp3"))
        SecurityScope.retain(url("/books/dropped.mp3"))

        // Act
        SecurityScope.releaseUnused(keeping: [url("/books/kept.mp3")])

        // Assert
        XCTAssertEqual(stopped.map(\.path), ["/books/dropped.mp3"])
        XCTAssertEqual(SecurityScope.heldCount, 1)
    }

    func test_releaseUnused_keepsAFolderThatHoldsALiveFile() {
        // Arrange — the user dropped a folder; the grant is on the
        // folder, but what the app refers to afterwards is the chapters
        // inside it. Releasing the folder would revoke access to them.
        SecurityScope.retain(url("/books/Dune"))

        // Act
        SecurityScope.releaseUnused(keeping: [url("/books/Dune/ch1.mp3")])

        // Assert
        XCTAssertTrue(stopped.isEmpty, "released the folder its live chapters live in")
        XCTAssertEqual(SecurityScope.heldCount, 1)
    }

    func test_releaseUnused_doesNotKeepAFolderOnANameThatMerelySharesAPrefix() {
        // Arrange — "/books/Dune2" is not inside "/books/Dune".
        SecurityScope.retain(url("/books/Dune"))

        // Act
        SecurityScope.releaseUnused(keeping: [url("/books/Dune2/ch1.mp3")])

        // Assert
        XCTAssertEqual(stopped.map(\.path), ["/books/Dune"])
    }

    func test_releaseUnused_releasesEverythingWhenNothingIsLive() {
        // Arrange — a cleared draft with an empty queue.
        SecurityScope.retain(url("/books/a.mp3"))
        SecurityScope.retain(url("/out"))

        // Act
        SecurityScope.releaseUnused(keeping: [URL]())

        // Assert
        XCTAssertEqual(SecurityScope.heldCount, 0)
        XCTAssertEqual(Set(stopped.map(\.path)), ["/books/a.mp3", "/out"])
    }

    // MARK: - the platform's requirement

    func test_everyGrantTakenIsBalancedByExactlyOneRelease() {
        // Arrange — a session's worth: a folder, its chapters, an output
        // directory, a second book, then a clear and a quit.
        for path in ["/books/Dune", "/books/Dune/ch1.mp3", "/out", "/books/Emma"] {
            SecurityScope.retain(url(path))
        }

        // Act
        SecurityScope.releaseUnused(keeping: [url("/books/Dune/ch1.mp3"), url("/out")])
        SecurityScope.releaseAll()

        // Assert — the count matches and no URL was stopped twice, which
        // is what /documentation/foundation/url/startaccessingsecurityscopedresource()
        // requires of a caller.
        XCTAssertEqual(stopped.count, started.count, "started \(started.count), stopped \(stopped.count)")
        XCTAssertEqual(Set(stopped.map(\.path)), Set(started.map(\.path)))
        XCTAssertEqual(Set(stopped.map(\.path)).count, stopped.count, "a URL was stopped twice: \(stopped)")
        XCTAssertEqual(SecurityScope.heldCount, 0)
    }

    func test_releaseAll_isIdempotent() {
        // Arrange
        SecurityScope.retain(url("/books/a.mp3"))

        // Act — quit paths can both run in a shutdown.
        SecurityScope.releaseAll()
        SecurityScope.releaseAll()

        // Assert
        XCTAssertEqual(stopped.count, 1, "stopped \(stopped.count) times for one grant")
    }
}
