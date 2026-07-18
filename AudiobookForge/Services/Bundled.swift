import Foundation

enum Bundled {
    private static let lock = NSLock()
    private static var cache: [String: URL?] = [:]
    private static var _overrideDirectory: URL?

    /// Test hook: point binary resolution at an explicit directory (the
    /// repo's Resources/bin) since unit tests run outside the app bundle.
    /// Clears the memoisation cache so a mid-suite change takes effect.
    static func setOverrideDirectory(_ url: URL?) {
        lock.lock(); defer { lock.unlock() }
        _overrideDirectory = url
        cache.removeAll()
    }

    /// Resolve a binary that ships inside the app bundle's Resources/bin/.
    /// Falls back to a `which` lookup so `swift run`/CLI smoke-tests work
    /// when the binaries are not yet bundled. Memoised because the
    /// fallback spawns a subprocess and `binary("ffmpeg")` gets called
    /// once per chapter during a drag-drop probe.
    static func binary(_ name: String) -> URL? {
        lock.lock()
        if let cached = cache[name] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = resolve(name)
        lock.lock()
        cache[name] = resolved
        lock.unlock()
        return resolved
    }

    private static func resolve(_ name: String) -> URL? {
        lock.lock()
        let override = _overrideDirectory
        lock.unlock()
        if let override {
            let candidate = override.appendingPathComponent(name)
            return FileManager.default.isExecutableFile(atPath: candidate.path)
                ? candidate : nil
        }
        if let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "bin") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: nil) {
            return url
        }
        // Dev fallback: look on PATH (e.g. brew-installed ffmpeg).
        // Debug builds only — a release bundle always ships its own
        // binary, and a damaged bundle should fail loudly rather than
        // silently run whatever user-writable ffmpeg is first on PATH.
        #if DEBUG
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
                let path = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return path.isEmpty ? nil : URL(fileURLWithPath: path)
            } catch {
                return nil
            }
        #else
            return nil
        #endif
    }
}
