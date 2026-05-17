import Foundation

/// Build an FFMETADATA1 file describing the book + chapter offsets.
/// ffmpeg consumes this via `-i metadata.txt -map_metadata 1`.
enum ChapterBuilder {
    static func ffmetadata(for chapters: [Chapter], metadata: BookMetadata) -> String {
        var out = ";FFMETADATA1\n"
        out += kv("title", metadata.title)
        out += kv("artist", metadata.author)
        out += kv("album", metadata.title)
        out += kv("album_artist", metadata.author)
        out += kv("composer", metadata.narrator) // narrator → composer is the de-facto convention
        out += kv("date", metadata.year)
        out += kv("genre", metadata.genre.isEmpty ? "Audiobook" : metadata.genre)
        out += kv("description", metadata.description)
        out += kv("comment", metadata.description)
        if !metadata.series.isEmpty {
            out += kv("TXXX:series", metadata.series)
            if !metadata.seriesPosition.isEmpty {
                out += kv("TXXX:series-part", metadata.seriesPosition)
            }
        }

        // FFMETADATA chapters are in arbitrary timebase; using ms keeps numbers
        // small and avoids floating point drift across long books.
        var cursor: Int64 = 0
        for chap in chapters {
            let durMs = Int64((chap.duration * 1000).rounded())
            let start = cursor
            let end = cursor + max(0, durMs - 1)
            cursor += durMs
            out += "\n[CHAPTER]\n"
            out += "TIMEBASE=1/1000\n"
            out += "START=\(start)\n"
            out += "END=\(end)\n"
            out += kv("title", chap.title)
        }
        return out
    }

    static func concatList(for chapters: [Chapter]) -> String {
        concatList(paths: chapters.map(\.sourceURL.path))
    }

    /// Concat-demuxer list pointing at intermediate `.m4a` files produced
    /// by the parallel-encode Phase 1.
    static func concatList(forIntermediates urls: [URL]) -> String {
        concatList(paths: urls.map(\.path))
    }

    /// ffmpeg concat demuxer format. Paths must be single-quoted with any
    /// embedded single-quote escaped as `'\''`.
    private static func concatList(paths: [String]) -> String {
        paths.map { path in
            let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
            return "file '\(escaped)'"
        }.joined(separator: "\n") + "\n"
    }

    private static func kv(_ key: String, _ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // FFMETADATA escapes: =, ;, #, \, and newline.
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "=", with: "\\=")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "#", with: "\\#")
            .replacingOccurrences(of: "\n", with: "\\\n")
        return "\(key)=\(escaped)\n"
    }
}
