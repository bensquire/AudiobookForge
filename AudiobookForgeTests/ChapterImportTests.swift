import XCTest
@testable import ForgeCore

final class ChapterImportTests: XCTestCase {
    private var tmp: URL!

    override func setUp() async throws {
        try await super.setUp()
        tmp = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
            create: true
        )
    }

    override func tearDown() async throws {
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
        try await super.tearDown()
    }

    /// An empty file at `relative` under `tmp`; the walk reads names, not audio.
    @discardableResult
    private func touch(_ relative: String) throws -> URL {
        let url = tmp.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: url)
        return url
    }

    // MARK: - audioFiles

    func test_audioFiles_walksAFolderInNaturalOrderAndSkipsNonAudio() throws {
        // Arrange — a dropped folder with a cover and out-of-order names
        try touch("Book/Chapter 10.mp3")
        try touch("Book/Chapter 2.mp3")
        try touch("Book/cover.jpg")

        // Act
        let files = ChapterImport.audioFiles(in: [tmp.appendingPathComponent("Book")], existingPaths: [])

        // Assert
        XCTAssertEqual(files.map(\.lastPathComponent), ["Chapter 2.mp3", "Chapter 10.mp3"])
    }

    func test_audioFiles_skipsHiddenAppleDoubleSidecars() throws {
        // Arrange — what a FAT/exFAT drive leaves beside every file
        try touch("Book/01.mp3")
        try touch("Book/._01.mp3")

        // Act
        let files = ChapterImport.audioFiles(in: [tmp.appendingPathComponent("Book")], existingPaths: [])

        // Assert
        XCTAssertEqual(files.map(\.lastPathComponent), ["01.mp3"])
    }

    func test_audioFiles_keepsPickedAudioFilesAndDropsMissingOrNonAudioOnes() throws {
        // Arrange — two picked files that exist, one that has gone, one image
        let kept = try touch("a.mp3")
        let alsoKept = try touch("b.m4a")
        let gone = tmp.appendingPathComponent("gone.mp3")
        let image = try touch("cover.jpg")

        // Act
        let files = ChapterImport.audioFiles(in: [image, gone, alsoKept, kept], existingPaths: [])

        // Assert
        XCTAssertEqual(files.map(\.lastPathComponent), ["a.mp3", "b.m4a"])
    }

    func test_audioFiles_leavesOutFilesAlreadyInTheDraft() throws {
        // Arrange — the folder is dropped again after one chapter was imported
        let already = try touch("Book/01.mp3")
        try touch("Book/02.mp3")

        // Act
        let files = ChapterImport.audioFiles(
            in: [tmp.appendingPathComponent("Book")],
            existingPaths: [already.standardizedFileURL.path]
        )

        // Assert
        XCTAssertEqual(files.map(\.lastPathComponent), ["02.mp3"])
    }

    // MARK: - metadata seeding

    func test_metadata_emptyDraftTakesTitleAndAuthorFromTheFirstFile() {
        // Arrange
        var first = AudioProbe.Probed(duration: 60)
        first.album = "Dune"
        first.artist = "Frank Herbert"

        // Act
        let seeded = ChapterImport.metadata(BookMetadata(), seededFrom: first)

        // Assert
        XCTAssertEqual(seeded.title, "Dune")
        XCTAssertEqual(seeded.author, "Frank Herbert")
    }

    func test_metadata_keepsWhatTheUserAlreadyTyped() {
        // Arrange
        var typed = BookMetadata()
        typed.title = "My Title"
        var first = AudioProbe.Probed(duration: 60)
        first.album = "Tagged Album"
        first.artist = "Tagged Artist"

        // Act
        let result = ChapterImport.metadata(typed, seededFrom: first)

        // Assert — a draft with anything typed is left exactly as it was
        XCTAssertEqual(result, typed)
    }

    // MARK: - dedupe

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
