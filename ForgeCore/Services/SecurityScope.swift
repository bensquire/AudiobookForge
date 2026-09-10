import Foundation

/// Holds `startAccessingSecurityScopedResource()` grants for user-picked
/// URLs (drag-drop, file importer, NSOpenPanel) so the sandboxed app —
/// and the bundled ffmpeg child process — can still read/write them at
/// encode time, long after the picker's callback has returned.
///
/// Sandboxed apps with `com.apple.security.files.user-selected.read-write`
/// receive an implicit grant for the URL the user picked, but only while
/// the URL is "in scope". Storing the bare URL into the project model
/// and reading it later from a child process yields `EPERM` ("Operation
/// not permitted") on the input file.
///
/// Every grant is balanced, as the platform requires: "You must balance
/// each call to `startAccessingSecurityScopedResource()` for a given
/// security-scoped URL with a call to `stopAccessingSecurityScopedResource()`"
/// — /documentation/foundation/url/startaccessingsecurityscopedresource().
/// Grants outlive the picker, so they are released by sweeping against
/// what the app still refers to (`releaseUnused(keeping:)`) and, for
/// whatever is still in use, at termination (`releaseAll()`).
@MainActor
public enum SecurityScope {
    /// Key on the standardized path, not the URL — `URL` equality is
    /// surprising across `file://x` vs `file://x/`, symlink vs resolved,
    /// and other normal-looking variations that would all hit the same
    /// inode. The value is the URL the grant was taken on, so the stop
    /// is made against the same one.
    private static var held: [String: URL] = [:]

    /// The sandbox calls, injectable because a test runner holds no
    /// grants: the real `startAccessingSecurityScopedResource()` returns
    /// false for every URL a test can construct, so the bookkeeping
    /// would never be exercised.
    static var startAccess: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() }
    static var stopAccess: (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }

    /// Start the security scope on `url` and remember we did, so we
    /// don't double-start the same URL (which is a real cost). Idempotent.
    public static func retain(_ url: URL) {
        let key = url.standardizedFileURL.path
        guard held[key] == nil else { return }
        if startAccess(url) {
            held[key] = url
        }
        // If startAccessing… returned false the URL either wasn't
        // security-scoped (e.g. a `file://` we constructed ourselves)
        // or sandboxing isn't in effect. Nothing was granted, so nothing
        // is recorded and nothing is owed a stop.
    }

    /// Release every grant that `live` no longer accounts for.
    ///
    /// A grant on a folder is what makes its children readable, so a
    /// held URL that contains a live one is kept even though the folder
    /// itself is not in the set: the user drops a folder, and what the
    /// app then refers to is the chapter files inside it.
    public static func releaseUnused(keeping live: some Sequence<URL>) {
        let livePaths = Set(live.map(\.standardizedFileURL.path))
        for (key, url) in held where !livePaths.contains(key) {
            let asFolder = key.hasSuffix("/") ? key : key + "/"
            guard !livePaths.contains(where: { $0.hasPrefix(asFolder) }) else { continue }
            stopAccess(url)
            held.removeValue(forKey: key)
        }
    }

    /// Balance every outstanding grant. For app termination, where what
    /// is left is still in use and so cannot be swept.
    public static func releaseAll() {
        for url in held.values {
            stopAccess(url)
        }
        held.removeAll()
    }

    /// How many grants are outstanding. For tests and diagnostics.
    public static var heldCount: Int {
        held.count
    }
}
