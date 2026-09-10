import ArgumentParser
import ForgeCore
import Foundation

struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Walk the library roots and classify every book (done / needs-forge / needs-review)."
    )

    @OptionGroup var global: GlobalOptions

    @Flag(
        help: "Print the manifest as JSON to stdout instead of a summary table (it is still written to stateDir)."
    )
    var json = false

    @Flag(help: "Skip chapter probing (fast, but every mp4-family book reads as needs-review).")
    var noProbe = false

    func run() async throws {
        let config = try global.loadConfig()

        // Without ffmpeg, `AudioProbe.chapterFormat` quietly answers
        // `.none` for everything and every chpl-only m4b gets filed as
        // needs-review. Refuse to write a manifest built on that.
        if !noProbe, Bundled.binary("ffmpeg") == nil {
            throw ScanError.ffmpegMissing
        }

        for root in config.libraryRootURLs where !FileManager.default.isDirectory(at: root) {
            throw ScanError.rootNotADirectory(root.path)
        }

        let probe: @Sendable (URL) async -> AudioProbe.ChapterFormat = if noProbe {
            { _ in .none }
        } else {
            { url in await AudioProbe.chapterFormat(url) }
        }
        let scanner = LibraryScanner(chapterFormat: probe)
        let manifest = await scanner.scan(roots: config.libraryRootURLs)

        try write(manifest, to: config.stateDirURL)

        if json {
            try FileHandle.standardOutput.write(Self.encoder.encode(manifest) + Data("\n".utf8))
        } else {
            printSummary(manifest, stateDir: config.stateDirURL)
        }
    }

    /// Environment problems, not usage errors — reported as a one-line
    /// `Error:` without the usage block `ValidationError` appends.
    enum ScanError: Error, CustomStringConvertible {
        case ffmpegMissing
        case rootNotADirectory(String)

        var description: String {
            switch self {
            case .ffmpegMissing:
                "ffmpeg not found. Set FORGE_FFMPEG_DIR to a directory containing the ffmpeg "
                    + "binary, or pass --no-probe to skip chapter probing."
            case let .rootNotADirectory(path):
                "Library root is not a directory: \(path)"
            }
        }
    }

    // MARK: - Output

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private func write(_ manifest: LibraryManifest, to stateDir: URL) throws {
        try FileManager.default.createDirectory(
            at: stateDir, withIntermediateDirectories: true
        )
        let url = stateDir.appendingPathComponent("manifest.json")
        try Self.encoder.encode(manifest).write(to: url, options: .atomic)
    }

    private func printSummary(_ manifest: LibraryManifest, stateDir: URL) {
        let byClass = Dictionary(grouping: manifest.books, by: \.classification)
        let order: [BookRecord.Classification] = [.needsForge, .needsReview, .done]

        for classification in order {
            guard let books = byClass[classification], !books.isEmpty else { continue }
            print("\n\(heading(for: classification)) (\(books.count))")
            for book in books {
                let size = ByteCountFormatter.string(
                    fromByteCount: book.totalBytes, countStyle: .file
                )
                print("  \(shortPath(book.path, roots: manifest.roots))")
                print("      \(book.reason) · \(book.audioFileCount) files · \(size)")
            }
        }

        let total = manifest.books.count
        let counts = order
            .compactMap { c in byClass[c].map { "\($0.count) \(c.rawValue)" } }
            .joined(separator: ", ")
        print("\n\(total) books scanned: \(counts)")
        print("Manifest: \(stateDir.appendingPathComponent("manifest.json").path)")
    }

    private func heading(for c: BookRecord.Classification) -> String {
        switch c {
        case .needsForge: "NEEDS FORGE"
        case .needsReview: "NEEDS REVIEW"
        case .done: "DONE"
        }
    }

    /// Trim the library-root prefix so the table reads as relative paths.
    private func shortPath(_ path: String, roots: [String]) -> String {
        for root in roots where path.hasPrefix(root) {
            return String(path.dropFirst(root.count)).trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
        }
        return path
    }
}
