import Foundation

/// Result of a library scan: every discovered book with a classification
/// the pipeline (and a human reading the JSON) can act on.
public struct LibraryManifest: Codable, Equatable {
    public var scannedAt: Date
    public var roots: [String]
    public var books: [BookRecord]

    public init(scannedAt: Date, roots: [String], books: [BookRecord]) {
        self.scannedAt = scannedAt
        self.roots = roots
        self.books = books
    }
}

public struct BookRecord: Codable, Equatable {
    public enum Classification: String, Codable {
        /// Finished audiobook(s) — chaptered mp4-family files. Leave alone.
        case done
        /// Loose chapter files (mp3/flac/wav/…) ready for the forge.
        case needsForge = "needs-forge"
        /// Odd shapes a human should look at (unchaptered single m4b,
        /// cue sheets, mixed formats in one folder).
        case needsReview = "needs-review"
    }

    public var path: String
    public var classification: Classification
    /// One line of human-readable justification for the classification —
    /// this is what makes the manifest reviewable.
    public var reason: String
    public var audioFileCount: Int
    /// Lowercased extensions present, sorted, e.g. ["m4b", "mp3"].
    public var formats: [String]
    public var totalBytes: Int64
    /// For all-mp4 books: the *weakest* chapter storage across the
    /// files. `chpl`-only books play fine in ffmpeg-lineage players but
    /// show no chapters in Apple ones — candidates for a lossless
    /// chapter upgrade. Nil for loose-file books (not applicable).
    public var chapterFormat: AudioProbe.ChapterFormat?

    public init(path: String, classification: Classification, reason: String,
                audioFileCount: Int, formats: [String], totalBytes: Int64,
                chapterFormat: AudioProbe.ChapterFormat? = nil)
    {
        self.path = path
        self.classification = classification
        self.reason = reason
        self.audioFileCount = audioFileCount
        self.formats = formats
        self.totalBytes = totalBytes
        self.chapterFormat = chapterFormat
    }
}

/// Walks library roots, groups audio into "books", and classifies each.
///
/// A *book* is a directory that directly contains audio files, with two
/// refinements: disc subfolders ("Disk 1", "CD2", …) merge into their
/// parent, and a lone audio file sitting directly in a scanned directory
/// is its own book (single-file m4b rips live like this).
///
/// Chapter detection is injected so the classification rules are unit
/// testable without real audio files; production passes AudioProbe.
public struct LibraryScanner {
    public typealias ChapterProbe = @Sendable (URL) async -> AudioProbe.ChapterFormat

    /// Extensions that count as audio for grouping purposes.
    public static let audioExtensions: Set<String> =
        ["mp3", "m4a", "m4b", "aac", "wav", "flac", "ogg", "opus"]

    /// mp4-family extensions that *can* carry chapter atoms — candidates
    /// for "already forged".
    private static let mp4Extensions: Set<String> = ["m4a", "m4b", "aac"]

    private static let discFolderPattern = /^(disc|disk|cd)\W*\d*$/.ignoresCase()

    private let chapterFormat: ChapterProbe

    public init(chapterFormat: @escaping ChapterProbe) {
        self.chapterFormat = chapterFormat
    }

    // MARK: - Scan

    public func scan(roots: [URL]) async -> LibraryManifest {
        var books: [BookRecord] = []
        for root in roots {
            let groups = Self.discoverBooks(under: root)
            for group in groups {
                books.append(await classify(group))
            }
        }
        books.sort { $0.path < $1.path }
        return LibraryManifest(
            scannedAt: Date(),
            roots: roots.map(\.path),
            books: books
        )
    }

    // MARK: - Discovery

    /// A candidate book: its identifying directory (or lone file) plus
    /// every audio file that belongs to it.
    public struct BookGroup: Equatable {
        public var path: URL
        public var audioFiles: [URL]

        public init(path: URL, audioFiles: [URL]) {
            self.path = path
            self.audioFiles = audioFiles
        }
    }

    /// Group the subtree under `root` into books. Pure filesystem-shape
    /// logic; exposed for tests (which build the shapes with empty files).
    public static func discoverBooks(under root: URL) -> [BookGroup] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Bucket every audio file by its immediate parent directory.
        var byDir: [URL: [URL]] = [:]
        for case let url as URL in walker where isAudio(url) {
            byDir[url.deletingLastPathComponent().standardizedFileURL, default: []]
                .append(url)
        }

        // Merge disc folders into their parent book.
        var merged: [URL: [URL]] = [:]
        for (dir, files) in byDir {
            let owner = isDiscFolder(dir) ? dir.deletingLastPathComponent() : dir
            merged[owner.standardizedFileURL, default: []].append(contentsOf: files)
        }

        return merged
            .map { dir, files in
                let sorted = files.sorted {
                    $0.path.localizedStandardCompare($1.path) == .orderedAscending
                }
                // A lone audio file directly inside a folder that also
                // holds other books reads better identified by the file.
                if sorted.count == 1, dir == root.standardizedFileURL {
                    return BookGroup(path: sorted[0], audioFiles: sorted)
                }
                return BookGroup(path: dir, audioFiles: sorted)
            }
            .sorted { $0.path.path < $1.path.path }
    }

    static func isAudio(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    static func isDiscFolder(_ url: URL) -> Bool {
        url.lastPathComponent.firstMatch(of: discFolderPattern) != nil
    }

    // MARK: - Classification

    public func classify(_ group: BookGroup) async -> BookRecord {
        let exts = Set(group.audioFiles.map { $0.pathExtension.lowercased() })
        let mp4Files = group.audioFiles.filter {
            Self.mp4Extensions.contains($0.pathExtension.lowercased())
        }
        let looseFiles = group.audioFiles.filter {
            !Self.mp4Extensions.contains($0.pathExtension.lowercased())
        }
        let hasCue = FileManager.default.siblingCueExists(near: group.path)

        let classification: BookRecord.Classification
        let reason: String
        var weakestFormat: AudioProbe.ChapterFormat?

        if looseFiles.isEmpty {
            // mp4-family only: forged if every file carries chapters.
            // Record the weakest storage format across the set — one
            // chpl-only file makes the whole book Apple-invisible.
            var unchaptered = 0
            var sawChpl = false
            for file in mp4Files {
                switch await chapterFormat(file) {
                case .none: unchaptered += 1
                case .chpl: sawChpl = true
                case .chap: break
                }
            }
            weakestFormat = unchaptered > 0 ? AudioProbe.ChapterFormat.none
                : sawChpl ? .chpl : .chap
            if unchaptered == 0 {
                classification = .done
                let formatNote = sawChpl ? " (chpl-only — chapters invisible to Apple players)" : ""
                reason = (mp4Files.count == 1
                    ? "Single chaptered \(mp4Files[0].pathExtension.lowercased())"
                    : "\(mp4Files.count) chaptered mp4-family files") + formatNote
            } else if hasCue {
                classification = .needsReview
                reason = "Unchaptered mp4-family file with a cue sheet — chapters may live in the cue"
            } else if mp4Files.count == 1 {
                classification = .needsReview
                reason = "Single mp4-family file without chapter markers"
            } else {
                classification = .needsReview
                reason = "\(unchaptered) of \(mp4Files.count) mp4-family files lack chapter markers"
            }
        } else if mp4Files.isEmpty {
            classification = .needsForge
            reason = "\(looseFiles.count) loose \(exts.sorted().joined(separator: "/")) files"
        } else {
            classification = .needsReview
            reason = "Mixed formats: \(looseFiles.count) loose files alongside \(mp4Files.count) mp4-family files"
        }

        let bytes = group.audioFiles.reduce(Int64(0)) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }

        return BookRecord(
            path: group.path.path,
            classification: classification,
            reason: reason,
            audioFileCount: group.audioFiles.count,
            formats: exts.sorted(),
            totalBytes: bytes,
            chapterFormat: weakestFormat
        )
    }
}

private extension FileManager {
    /// A .cue next to the book (same dir for a folder-book, or beside a
    /// lone-file book) hints that chapters live outside the audio.
    func siblingCueExists(near path: URL) -> Bool {
        var isDir: ObjCBool = false
        _ = fileExists(atPath: path.path, isDirectory: &isDir)
        let dir = isDir.boolValue ? path : path.deletingLastPathComponent()
        let entries = (try? contentsOfDirectory(atPath: dir.path)) ?? []
        return entries.contains { $0.lowercased().hasSuffix(".cue") }
    }
}
