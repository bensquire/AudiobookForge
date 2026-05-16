import XCTest
@testable import AudiobookForge

@MainActor
final class AudiobookProjectTests: XCTestCase {

    func test_canEnqueue_falseOnEmptyDraft() {
        // Arrange
        let project = AudiobookProject()

        // Act / Assert
        XCTAssertFalse(project.canEnqueue)
    }

    func test_canEnqueue_falseWithoutChapters() {
        // Arrange — metadata + output dir set, but no chapters yet
        let project = AudiobookProject()
        project.metadata.title = "x"
        project.metadata.author = "y"
        project.settings.outputDirectory = URL(fileURLWithPath: "/out")

        // Act / Assert
        XCTAssertFalse(project.canEnqueue)
    }

    func test_canEnqueue_falseWithoutMetadata() {
        // Arrange — chapters + output dir, blank metadata
        let project = AudiobookProject()
        project.chapters = [makeChapter()]
        project.settings.outputDirectory = URL(fileURLWithPath: "/out")

        // Act / Assert
        XCTAssertFalse(project.canEnqueue)
    }

    func test_canEnqueue_falseWithoutOutputDirectory() {
        // Arrange
        let project = AudiobookProject()
        project.chapters = [makeChapter()]
        project.metadata.title = "x"
        project.metadata.author = "y"
        project.settings.outputDirectory = nil

        // Act / Assert
        XCTAssertFalse(project.canEnqueue)
    }

    func test_canEnqueue_trueWhenAllPiecesPresent() {
        // Arrange
        let project = AudiobookProject()
        project.chapters = [makeChapter()]
        project.metadata.title = "Dune"
        project.metadata.author = "Frank Herbert"
        project.settings.outputDirectory = URL(fileURLWithPath: "/out")

        // Act / Assert
        XCTAssertTrue(project.canEnqueue)
    }

    func test_reset_clearsChaptersAndMetadataButKeepsSettings() {
        // Arrange — populated draft with custom settings
        let project = AudiobookProject()
        project.chapters = [makeChapter(), makeChapter()]
        project.metadata.title = "x"; project.metadata.author = "y"
        project.settings.outputDirectory = URL(fileURLWithPath: "/out")
        project.settings.bitrate = .k192
        project.settings.filenameTemplate = "{title}.m4b"

        // Act
        project.reset()

        // Assert — chapters + metadata wiped, settings preserved so the
        // user doesn't have to re-pick output dir / bitrate / template
        // for every book they queue.
        XCTAssertTrue(project.chapters.isEmpty)
        XCTAssertTrue(project.metadata.isEmpty)
        XCTAssertEqual(project.settings.outputDirectory?.path, "/out")
        XCTAssertEqual(project.settings.bitrate, .k192)
        XCTAssertEqual(project.settings.filenameTemplate, "{title}.m4b")
    }

    func test_totalDuration_sumsChapterDurations() {
        // Arrange
        let project = AudiobookProject()
        project.chapters = [
            makeChapter(duration: 60),
            makeChapter(duration: 90),
            makeChapter(duration: 150),
        ]

        // Act
        let total = project.totalDuration

        // Assert
        XCTAssertEqual(total, 300, accuracy: 0.001)
    }

    private func makeChapter(duration: TimeInterval = 60) -> Chapter {
        Chapter(
            sourceURL: URL(fileURLWithPath: "/tmp/x.m4a"),
            title: "x",
            duration: duration,
            codec: .aac,
            sampleRate: 44_100,
            channels: 2)
    }
}
