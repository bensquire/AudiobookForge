import Foundation

/// Pure helpers for the drag-drop / file-importer ingest path, split out
/// of ChapterListView so the ordering and dedupe rules are unit-testable.
public enum ChapterImport {
    /// The audio files a drop or a pick names, in chapter order. A folder
    /// is walked, skipping hidden files so AppleDouble sidecars ("._ch01.mp3"
    /// on FAT/exFAT drives) don't become zero-length chapters; a file is
    /// kept if it is audio and still there. Sorted naturally by file name,
    /// so "Chapter 2" precedes "Chapter 10", then deduped against the
    /// draft's chapters.
    public static func audioFiles(
        in urls: [URL], existingPaths: Set<String>, fileManager: FileManager = .default
    ) -> [URL] {
        var found: [URL] = []
        for url in urls {
            if fileManager.isDirectory(at: url) {
                guard let walker = fileManager.enumerator(
                    at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                ) else { continue }
                for case let file as URL in walker where LibraryScanner.isAudio(file) {
                    found.append(file)
                }
            } else if LibraryScanner.isAudio(url), fileManager.fileExists(atPath: url.path) {
                found.append(url)
            }
        }
        found
            .sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return dedupe(found, existingPaths: existingPaths)
    }

    /// The draft's metadata after an import. A draft with nothing typed
    /// yet takes its title from the first file's album tag and its author
    /// from the artist tag; anything the user already entered is kept.
    public static func metadata(
        _ current: BookMetadata, seededFrom first: AudioProbe.Probed?
    ) -> BookMetadata {
        guard let first, current.isEmpty else { return current }
        var seeded = current
        seeded.title = first.album ?? ""
        seeded.author = first.artist ?? ""
        return seeded
    }

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
