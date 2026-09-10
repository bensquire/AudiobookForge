import Foundation

/// Pure helpers for the drag-drop / file-importer ingest path, split out
/// of ChapterListView so the ordering and dedupe rules are unit-testable.
public enum ChapterImport {
    /// Drop URLs whose standardized path is already a chapter source or a
    /// duplicate earlier in this same batch (two overlapping folders
    /// dropped together yield the same file twice). Order-preserving.
    public static func dedupe(_ urls: [URL], existingPaths: Set<String>) -> [URL] {
        var seen = existingPaths
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// Split probed files into importable ones and finished audiobooks.
    /// A file that already carries embedded chapter markers (Audible
    /// m4b, chaptered podcast MP3) is a finished book — importing it
    /// would flatten it into a single chapter and silently discard its
    /// structure. Order-preserving on both sides.
    public static func partitionFinished(
        _ probed: [(url: URL, info: AudioProbe.Probed)]
    ) -> (importable: [(url: URL, info: AudioProbe.Probed)], skippedNames: [String]) {
        let importable = probed.filter { !$0.info.hasChapters }
        let skipped = probed.filter(\.info.hasChapters).map(\.url.lastPathComponent)
        return (importable, skipped)
    }

    /// The chapter a probed file becomes on import. Title falls back to
    /// the file name when the tag is missing or blank.
    public static func chapter(for url: URL, probed p: AudioProbe.Probed) -> Chapter {
        let tagged = p.title?.trimmingCharacters(in: .whitespaces) ?? ""
        return Chapter(
            sourceURL: url,
            title: tagged.isEmpty ? url.deletingPathExtension().lastPathComponent : tagged,
            duration: p.duration,
            sourceBitrate: p.bitrate,
            codec: p.codec,
            sampleRate: p.sampleRate,
            channels: p.channels
        )
    }
}
