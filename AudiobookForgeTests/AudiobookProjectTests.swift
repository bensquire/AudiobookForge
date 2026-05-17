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
            makeChapter(duration: 150)
        ]

        // Act
        let total = project.totalDuration

        // Assert
        XCTAssertEqual(total, 300, accuracy: 0.001)
    }

    func test_hydrate_replacesChaptersMetadataAndSettings() {
        // Arrange — the project starts with some half-edited state the
        // user wouldn't want to keep after loading a queued item.
        let project = AudiobookProject()
        project.chapters = [makeChapter()]
        project.metadata.title = "stale draft"
        project.settings.bitrate = .k32

        let spec = EncodeSpec(
            chapters: [makeChapter(duration: 120), makeChapter(duration: 240)],
            metadata: { var m = BookMetadata(); m.title = "Dune"; m.author = "FH"; return m }(),
            settings: {
                var s = EncodeSettings()
                s.bitrate = .k192
                s.gainBoost = .dB6
                s.outputDirectory = URL(fileURLWithPath: "/out")
                s.filenameTemplate = "{title}.m4b"
                return s
            }(),
            outputURL: URL(fileURLWithPath: "/out/Dune.m4b")
        )

        // Act
        project.hydrate(from: spec)

        // Assert — every field from the spec made it across.
        XCTAssertEqual(project.chapters.count, 2)
        XCTAssertEqual(project.totalDuration, 360, accuracy: 0.001)
        XCTAssertEqual(project.metadata.title, "Dune")
        XCTAssertEqual(project.metadata.author, "FH")
        XCTAssertEqual(project.settings.bitrate, .k192)
        XCTAssertEqual(project.settings.gainBoost, .dB6)
        XCTAssertEqual(project.settings.outputDirectory?.path, "/out")
        XCTAssertEqual(project.settings.filenameTemplate, "{title}.m4b")
    }

    func test_hydrate_roundTripsThroughEncodeSpec() {
        // Arrange — a populated draft, snapshot it as a spec, mutate the
        // draft, then hydrate back. Result should equal the snapshot.
        let project = AudiobookProject()
        project.chapters = [makeChapter(duration: 60)]
        project.metadata.title = "A"; project.metadata.author = "B"
        project.settings.outputDirectory = URL(fileURLWithPath: "/o")
        project.settings.gainBoost = .autoNormalize

        let snapshot = EncodeSpec(
            chapters: project.chapters,
            metadata: project.metadata,
            settings: project.settings,
            outputURL: URL(fileURLWithPath: "/o/A.m4b")
        )

        // Mutate the live project away from the snapshot.
        project.chapters = []
        project.metadata.title = "junk"
        project.settings.gainBoost = .off

        // Act
        project.hydrate(from: snapshot)

        // Assert
        XCTAssertEqual(project.chapters.count, 1)
        XCTAssertEqual(project.metadata.title, "A")
        XCTAssertEqual(project.settings.gainBoost, .autoNormalize)
    }

    private func makeChapter(duration: TimeInterval = 60) -> Chapter {
        Chapter(
            sourceURL: URL(fileURLWithPath: "/tmp/x.m4a"),
            title: "x",
            duration: duration,
            codec: .aac,
            sampleRate: 44100,
            channels: 2
        )
    }
}
