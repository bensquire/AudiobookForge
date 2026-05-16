import Foundation
import Observation

/// The "draft" the user is currently editing. All encode state lives on
/// `QueueItem` once a draft is enqueued; this type is purely about the
/// prep area.
@Observable
final class AudiobookProject {
    var chapters: [Chapter] = []
    var metadata: BookMetadata = .init()
    var settings: EncodeSettings = .init()

    var totalDuration: TimeInterval {
        chapters.reduce(0) { $0 + $1.duration }
    }

    var canEnqueue: Bool {
        !chapters.isEmpty
            && metadata.hasRequiredFields
            && settings.outputDirectory != nil
    }

    /// Clear chapters + metadata so the prep area is ready for the next
    /// book. We deliberately preserve `settings` (output dir, codec,
    /// bitrate, filename template) so the user doesn't have to re-pick
    /// them for every queued book.
    func reset() {
        chapters = []
        metadata = .init()
    }
}
