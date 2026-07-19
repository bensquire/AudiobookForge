import XCTest
@testable import ForgeCore

final class OutputPathResolverTests: XCTestCase {
    private var tmp: URL!

    override func setUp() {
        super.setUp()
        // Arrange (shared) — a fresh empty directory for every test so
        // collision behaviour is deterministic.
        // swiftlint:disable:next force_try
        tmp = try! FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
            create: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
        super.tearDown()
    }

    func test_uniqueURL_returnsDesiredWhenPathFree() {
        // Arrange
        let desired = tmp.appendingPathComponent("book.m4b")

        // Act
        let result = OutputPathResolver.uniqueURL(for: desired)

        // Assert
        XCTAssertEqual(result, desired)
    }

    func test_uniqueURL_appendsParenTwoWhenFileExists() throws {
        // Arrange — pre-populate so the desired path is taken on disk
        let desired = tmp.appendingPathComponent("book.m4b")
        try Data().write(to: desired)

        // Act
        let result = OutputPathResolver.uniqueURL(for: desired)

        // Assert
        XCTAssertEqual(result.lastPathComponent, "book (2).m4b")
    }

    func test_uniqueURL_keepsBumpingNumberUntilFree() throws {
        // Arrange — book.m4b, book (2).m4b, book (3).m4b all exist
        for name in ["book.m4b", "book (2).m4b", "book (3).m4b"] {
            try Data().write(to: tmp.appendingPathComponent(name))
        }

        // Act
        let result = OutputPathResolver.uniqueURL(
            for: tmp.appendingPathComponent("book.m4b")
        )

        // Assert
        XCTAssertEqual(result.lastPathComponent, "book (4).m4b")
    }

    func test_uniqueURL_respectsIsTakenPredicate() {
        // Arrange — disk is empty; isTaken claims book.m4b is in-flight
        let desired = tmp.appendingPathComponent("book.m4b")
        let claimed: Set<URL> = [desired]

        // Act
        let result = OutputPathResolver.uniqueURL(for: desired) {
            claimed.contains($0)
        }

        // Assert
        XCTAssertEqual(result.lastPathComponent, "book (2).m4b")
    }

    func test_uniqueURL_handlesExtensionlessPaths() throws {
        // Arrange — file with no extension already on disk
        let desired = tmp.appendingPathComponent("README")
        try Data().write(to: desired)

        // Act
        let result = OutputPathResolver.uniqueURL(for: desired)

        // Assert — Finder style "stem (N)" with no trailing dot
        XCTAssertEqual(result.lastPathComponent, "README (2)")
    }

    func test_uniqueURL_falsBackToUUIDAfterMaxAttempts() throws {
        // Arrange — exhaust the numeric range so the resolver has to fall
        // through to the UUID degenerate branch
        try Data().write(to: tmp.appendingPathComponent("x.m4b"))
        for n in 2 ... 5 {
            try Data().write(to: tmp.appendingPathComponent("x (\(n)).m4b"))
        }

        // Act — clamp maxAttempts to force the UUID fallback
        let result = OutputPathResolver.uniqueURL(
            for: tmp.appendingPathComponent("x.m4b"),
            maxAttempts: 5
        )

        // Assert — UUID branch matches `x (XXXXXXXX).m4b`
        let stem = result.deletingPathExtension().lastPathComponent
        XCTAssertTrue(stem.hasPrefix("x ("))
        XCTAssertTrue(stem.hasSuffix(")"))
        XCTAssertEqual(result.pathExtension, "m4b")
    }
}
