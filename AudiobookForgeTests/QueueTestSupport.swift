import XCTest
@testable import AudiobookForge

/// Shared fixtures for the queue-focused suites: a throwaway output
/// directory per test and a minimal enqueueable draft. Subclass instead
/// of copying — the draft shape must track `Chapter`/`AudiobookProject`
/// initializer changes in exactly one place.
@MainActor
class QueueTestCase: XCTestCase {
    var tmp: URL!

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

    /// A draft that satisfies `canEnqueue` without touching real audio —
    /// the source file deliberately doesn't exist, so anything that
    /// actually encodes it fails fast in preflight (no ffmpeg involved).
    func makeDraft(
        outputDir: URL?,
        title: String = "x",
        author: String = "y",
        template: String = "{title}.m4b"
    ) -> AudiobookProject {
        let p = AudiobookProject()
        p.chapters = [
            Chapter(
                sourceURL: URL(fileURLWithPath: "/tmp/nonexistent-\(title).m4a"),
                title: "t",
                duration: 60,
                codec: .aac,
                sampleRate: 44100,
                channels: 2
            )
        ]
        p.metadata.title = title
        p.metadata.author = author
        p.settings.outputDirectory = outputDir
        p.settings.filenameTemplate = template
        return p
    }
}
