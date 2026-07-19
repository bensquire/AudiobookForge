import XCTest
@testable import ForgeCore

final class LibraryScannerTests: XCTestCase {
    private var tmp: URL!

    override func setUp() {
        super.setUp()
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

    // MARK: - fixtures

    /// Create an empty file (content irrelevant — discovery and
    /// classification look at names/shape; chapter probing is faked).
    private func touch(_ relative: String) {
        let url = tmp.appendingPathComponent(relative)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    private func scanner(
        chaptered: Set<String> = [],
        chplOnly: Set<String> = []
    ) -> LibraryScanner {
        LibraryScanner(chapterFormat: { url in
            if chplOnly.contains(url.lastPathComponent) { return .chpl }
            return chaptered.contains(url.lastPathComponent) ? .chap : .none
        })
    }

    // MARK: - discovery

    func test_discover_groupsAudioByDirectory() {
        // Arrange — two book folders and a non-audio straggler
        touch("Book A/01.mp3")
        touch("Book A/02.mp3")
        touch("Book B/only.mp3")
        touch("Book B/cover.jpg")

        // Act
        let groups = LibraryScanner.discoverBooks(under: tmp)

        // Assert
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].audioFiles.count, 2)
        XCTAssertEqual(groups[1].audioFiles.count, 1)
    }

    func test_discover_mergesDiscFoldersIntoParentBook() {
        // Arrange — the Proxima/Ultima shape: one book split over discs
        touch("Ultima/Disk 1/01.mp3")
        touch("Ultima/Disk 1/02.mp3")
        touch("Ultima/Disk 2/01.mp3")

        // Act
        let groups = LibraryScanner.discoverBooks(under: tmp)

        // Assert — one book, all three files, identified by the parent
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].path.lastPathComponent, "Ultima")
        XCTAssertEqual(groups[0].audioFiles.count, 3)
    }

    func test_discover_loneFileDirectlyInRootIsItsOwnBook() {
        // Arrange — the "Artemis Fowl.m4b at library top level" shape
        touch("Artemis Fowl.m4b")
        touch("Some Series/01.mp3")

        // Act
        let groups = LibraryScanner.discoverBooks(under: tmp)

        // Assert — the lone file is identified by the file, not the root
        let lone = groups.first { $0.audioFiles.count == 1 && $0.path.pathExtension == "m4b" }
        XCTAssertNotNil(lone)
        XCTAssertEqual(lone?.path.lastPathComponent, "Artemis Fowl.m4b")
    }

    func test_discover_ordersFilesNaturally() {
        // Arrange — "10" must not sort before "2"
        touch("Book/Chapter 10.mp3")
        touch("Book/Chapter 2.mp3")

        // Act
        let groups = LibraryScanner.discoverBooks(under: tmp)

        // Assert
        XCTAssertEqual(
            groups[0].audioFiles.map(\.lastPathComponent),
            ["Chapter 2.mp3", "Chapter 10.mp3"]
        )
    }

    // MARK: - classification

    func test_classify_looseMP3sAreNeedsForge() async {
        // Arrange
        touch("Book/01.mp3")
        touch("Book/02.mp3")
        let group = LibraryScanner.discoverBooks(under: tmp)[0]

        // Act
        let record = await scanner().classify(group)

        // Assert
        XCTAssertEqual(record.classification, .needsForge)
        XCTAssertEqual(record.formats, ["mp3"])
    }

    func test_classify_chapteredM4BIsDone() async {
        // Arrange
        touch("Book/book.m4b")
        let group = LibraryScanner.discoverBooks(under: tmp)[0]

        // Act
        let record = await scanner(chaptered: ["book.m4b"]).classify(group)

        // Assert
        XCTAssertEqual(record.classification, .done)
    }

    func test_classify_unchapteredM4BIsNeedsReview() async {
        // Arrange
        touch("Book/book.m4b")
        let group = LibraryScanner.discoverBooks(under: tmp)[0]

        // Act — probe says no chapters
        let record = await scanner().classify(group)

        // Assert
        XCTAssertEqual(record.classification, .needsReview)
        XCTAssertTrue(record.reason.contains("without chapter markers"))
    }

    func test_classify_unchapteredM4BWithCueMentionsTheCue() async {
        // Arrange — the Dark Diamond shape, minus the embedded chapters
        touch("Book/book.m4b")
        touch("Book/book.cue")
        let group = LibraryScanner.discoverBooks(under: tmp)[0]

        // Act
        let record = await scanner().classify(group)

        // Assert
        XCTAssertEqual(record.classification, .needsReview)
        XCTAssertTrue(record.reason.contains("cue"))
    }

    func test_classify_mixedLooseAndMP4IsNeedsReview() async {
        // Arrange — the Xeelee shape: mp3 books alongside finished m4bs
        touch("Book/01.mp3")
        touch("Book/other.m4b")
        let group = LibraryScanner.discoverBooks(under: tmp)[0]

        // Act
        let record = await scanner(chaptered: ["other.m4b"]).classify(group)

        // Assert
        XCTAssertEqual(record.classification, .needsReview)
        XCTAssertTrue(record.reason.contains("Mixed"))
    }

    func test_classify_multipleChapteredM4AsAreDone() async {
        // Arrange — the Reynolds shape: a folder of single-file books
        touch("Reynolds/Pushing Ice.m4a")
        touch("Reynolds/House of Suns.m4a")
        let group = LibraryScanner.discoverBooks(under: tmp)[0]

        // Act
        let record = await scanner(
            chaptered: ["Pushing Ice.m4a", "House of Suns.m4a"]
        ).classify(group)

        // Assert
        XCTAssertEqual(record.classification, .done)
    }

    // MARK: - end to end

    func test_scan_producesSortedManifestAcrossClassifications() async {
        // Arrange
        touch("A Done Book/book.m4b")
        touch("B Forge Book/01.mp3")
        touch("C Review Book/lonely.m4b")

        // Act
        let manifest = await scanner(chaptered: ["book.m4b"]).scan(roots: [tmp])

        // Assert
        XCTAssertEqual(manifest.books.count, 3)
        XCTAssertEqual(
            manifest.books.map(\.classification),
            [.done, .needsForge, .needsReview]
        )
        XCTAssertEqual(manifest.roots, [tmp.path])
    }
}

extension LibraryScannerTests {
    // MARK: - chapter format recording

    func test_classify_recordsChplOnlyAsWeakestFormat() async {
        // Arrange — the "Ender's Game" shape: done, but Apple-invisible
        touch("Book/book.m4b")
        let group = LibraryScanner.discoverBooks(under: tmp)[0]

        // Act
        let record = await scanner(chplOnly: ["book.m4b"]).classify(group)

        // Assert
        XCTAssertEqual(record.classification, .done)
        XCTAssertEqual(record.chapterFormat, .chpl)
        XCTAssertTrue(record.reason.contains("chpl-only"))
    }

    func test_classify_recordsChapForFullyVisibleBook() async {
        // Arrange
        touch("Book/book.m4b")
        let group = LibraryScanner.discoverBooks(under: tmp)[0]

        // Act
        let record = await scanner(chaptered: ["book.m4b"]).classify(group)

        // Assert
        XCTAssertEqual(record.chapterFormat, .chap)
        XCTAssertFalse(record.reason.contains("chpl"))
    }

    func test_classify_looseFilesHaveNoChapterFormat() async {
        // Arrange
        touch("Book/01.mp3")
        let group = LibraryScanner.discoverBooks(under: tmp)[0]

        // Act
        let record = await scanner().classify(group)

        // Assert — not applicable to loose-file books
        XCTAssertNil(record.chapterFormat)
    }
}
