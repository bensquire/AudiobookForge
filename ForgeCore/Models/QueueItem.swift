import Foundation
import Observation

/// One row of the encode queue. Main-actor bound: it is UI state that the
/// queue worker mutates and the views observe, and the binding is what
/// lets a progress callback from a background thread capture it safely.
@MainActor
@Observable
public final class QueueItem: Identifiable {
    public enum Status: Equatable, Sendable {
        case pending
        case running
        case succeeded
        case failed(String)
        case cancelled

        public var isPending: Bool {
            if case .pending = self { true } else { false }
        }

        public var isRunning: Bool {
            if case .running = self { true } else { false }
        }

        public var isSucceeded: Bool {
            if case .succeeded = self { true } else { false }
        }

        public var isCancelled: Bool {
            if case .cancelled = self { true } else { false }
        }

        public var isFailed: Bool {
            if case .failed = self { true } else { false }
        }

        public var isActive: Bool {
            isPending || isRunning
        }

        public var isFinished: Bool {
            !isActive
        }

        public var isRetryable: Bool {
            isFailed || isCancelled
        }

        public var label: String {
            switch self {
            case .pending: "Pending"
            case .running: "Running"
            case .succeeded: "Done"
            case .failed: "Failed"
            case .cancelled: "Cancelled"
            }
        }
    }

    public let id = UUID()
    public var spec: EncodeSpec
    let sourceFingerprints: [URL: SourceFingerprint]
    let addedAt: Date

    public var status: Status = .pending
    public var progress: Double = 0
    public var progressLabel: String? // set only while running
    public var finalOutputURL: URL? // set on success (may differ from spec.outputURL)

    init(spec: EncodeSpec,
         sourceFingerprints: [URL: SourceFingerprint],
         addedAt: Date = .now)
    {
        self.spec = spec
        self.sourceFingerprints = sourceFingerprints
        self.addedAt = addedAt
    }

    public var title: String {
        spec.metadata.title
    }

    public var author: String {
        spec.metadata.author
    }
}

struct SourceFingerprint: Hashable {
    let size: Int64
    let mtime: Date

    /// Capture a file's size + modification time. Returns nil if the file
    /// can't be stat'd — caller treats that as a missing source.
    static func capture(_ url: URL,
                        fileManager: FileManager = .default) -> Self?
    {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.int64Value,
              let mtime = attrs[.modificationDate] as? Date
        else { return nil }
        return Self(size: size, mtime: mtime)
    }
}
