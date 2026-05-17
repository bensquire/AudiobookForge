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

    /// Monotonic counter bumped on every `reset()` / `hydrate(from:)`.
    /// Views with local state that should follow the project's lifecycle
    /// (e.g. the metadata search panel's results) observe this rather
    /// than inferring "we reset" from a chapter-array side effect — that
    /// would also fire when the user just deletes their last chapter.
    var resetToken: Int = 0

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
        resetToken &+= 1
    }

    /// Pull a queued spec back into the prep area for editing. Drops
    /// the spec's `outputURL` because the queue re-derives that from
    /// `settings.outputDirectory` + filename template at enqueue time.
    /// Settings overwrite is intentional — the user is editing *that*
    /// item, so its output dir / bitrate / gain are what they want back.
    func hydrate(from spec: EncodeSpec) {
        chapters = spec.chapters
        metadata = spec.metadata
        settings = spec.settings
        resetToken &+= 1
    }
}
