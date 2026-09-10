import Foundation

public extension FileManager {
    /// True when `url` exists and is a directory. The `ObjCBool` dance
    /// behind `fileExists(atPath:isDirectory:)` is easy to get subtly
    /// wrong (a missing path leaves the flag untouched), so it lives here
    /// once.
    func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
