import Foundation

enum Bundled {
    /// Resolve a binary that ships inside the app bundle's Resources/bin/.
    /// Falls back to a `which` lookup so `swift run`/CLI smoke-tests work
    /// when the binaries are not yet bundled.
    static func binary(_ name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "bin") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: nil) {
            return url
        }
        // Dev fallback: look on PATH (e.g. brew-installed ffmpeg).
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        } catch {
            return nil
        }
    }
}
