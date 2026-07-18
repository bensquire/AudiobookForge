import Foundation

/// Pure helpers for the drag-drop / file-importer ingest path, split out
/// of ChapterListView so the ordering and dedupe rules are unit-testable.
enum ChapterImport {
    /// Drop URLs whose standardized path is already a chapter source or a
    /// duplicate earlier in this same batch (two overlapping folders
    /// dropped together yield the same file twice). Order-preserving.
    static func dedupe(_ urls: [URL], existingPaths: Set<String>) -> [URL] {
        var seen = existingPaths
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
