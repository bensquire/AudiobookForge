import ArgumentParser
import ForgeCore
import Foundation

struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Walk the library roots and classify every book (done / needs-forge / needs-review)."
    )

    @OptionGroup var global: GlobalOptions

    @Flag(help: "Print the manifest as JSON to stdout instead of a summary table.")
    var json = false

    @Flag(help: "Skip chapter probing (fast, but every mp4-family book reads as needs-review).")
    var noProbe = false

    func run() async throws {
        let config = try global.loadConfig()

        for root in config.libraryRootURLs
            where !FileManager.default.fileExists(atPath: root.path)
        {
            throw ValidationError("Library root does not exist: \(root.path)")
        }

        let scanner = LibraryScanner(chapterFormat: noProbe
            ? { _ in .none }
            : { url in await AudioProbe.chapterFormat(url) }
        )
        let manifest = await scanner.scan(roots: config.libraryRootURLs)

        try write(manifest, to: config.stateDirURL)

        if json {
            FileHandle.standardOutput.write(try Self.encoder.encode(manifest))
        } else {
            printSummary(manifest, stateDir: config.stateDirURL)
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
