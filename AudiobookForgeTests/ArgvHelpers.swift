import Foundation

extension [String] {
    /// The value that immediately follows `key` in a flat
    /// `["-flag", "value", …]` argv list, or nil if the key isn't
    /// present or has nothing after it. Used by every test that pins
    /// ffmpeg argument construction.
    subscript(adjacent key: String) -> String? {
        guard let i = firstIndex(of: key), i + 1 < count else { return nil }
        return self[i + 1]
    }
}
