import Foundation

/// Pick a non-conflicting output URL. Matches Finder/Safari behaviour:
/// `foo.m4b`, then `foo (2).m4b`, `foo (3).m4b`, …
///
/// We use this in two places:
///   1. At enqueue time so the user sees the resolved final path on the
///      queue row (no surprises).
///   2. At encode-start time as a defensive re-check in case another
///      finished item dropped a file at the same path in the meantime.
enum OutputPathResolver {

    static func uniqueURL(for desired: URL,
                          fileManager: FileManager = .default,
                          maxAttempts: Int = 999,
                          isTaken: (URL) -> Bool = { _ in false }) -> URL {
        func taken(_ url: URL) -> Bool {
            fileManager.fileExists(atPath: url.path) || isTaken(url)
        }
        if !taken(desired) { return desired }

        let dir = desired.deletingLastPathComponent()
        let ext = desired.pathExtension
        let stem = desired.deletingPathExtension().lastPathComponent
        for n in 2...maxAttempts {
            let name = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !taken(candidate) { return candidate }
        }
        // Degenerate: 999 collisions. Fall back to a UUID suffix so we never
        // overwrite a user's existing file.
        let name = ext.isEmpty
            ? "\(stem) (\(UUID().uuidString.prefix(8)))"
            : "\(stem) (\(UUID().uuidString.prefix(8))).\(ext)"
        return dir.appendingPathComponent(name)
    }
}
