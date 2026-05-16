import Foundation
import Observation
import SwiftUI

@Observable
final class QueueItem: Identifiable {
    enum Status: Equatable {
        case pending
        case running
        case succeeded
        case failed(String)
        case cancelled

        var isPending: Bool {
            if case .pending = self { true } else { false }
        }

        var isRunning: Bool {
            if case .running = self { true } else { false }
        }

        var isSucceeded: Bool {
            if case .succeeded = self { true } else { false }
        }

        var isCancelled: Bool {
            if case .cancelled = self { true } else { false }
        }

        var isFailed: Bool {
            if case .failed = self { true } else { false }
        }

        var isActive: Bool {
            isPending || isRunning
        }

        var isFinished: Bool {
            !isActive
        }

        var isRetryable: Bool {
            isFailed || isCancelled
        }

        var label: String {
            switch self {
            case .pending: "Pending"
            case .running: "Running"
            case .succeeded: "Done"
            case .failed: "Failed"
            case .cancelled: "Cancelled"
            }
        }

        var tint: Color {
            switch self {
            case .pending: .secondary
            case .running: .accentColor
            case .succeeded: .green
            case .failed: .red
            case .cancelled: .orange
            }
        }
    }

    let id = UUID()
    var spec: EncodeSpec
    let sourceFingerprints: [URL: SourceFingerprint]
    let addedAt: Date

    var status: Status = .pending
    var progress: Double = 0
    var progressLabel: String? // only set while running, derived elsewhere otherwise
    var finalOutputURL: URL? // set on success (may differ from spec.outputURL)

    init(spec: EncodeSpec,
         sourceFingerprints: [URL: SourceFingerprint],
         addedAt: Date = .now)
    {
        self.spec = spec
        self.sourceFingerprints = sourceFingerprints
        self.addedAt = addedAt
    }

    var title: String {
        spec.metadata.title
    }

    var author: String {
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
