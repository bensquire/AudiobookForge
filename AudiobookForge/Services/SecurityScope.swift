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
/// We start the scope once per URL and never release it — the access
/// dies with the app process. This is what every other macOS app
/// holding user-picked paths across its lifetime does; releasing
/// requires a paired stop call per use site, which is fragile, and the
/// downside is just slightly higher kernel bookkeeping.
@MainActor
enum SecurityScope {
    /// Key on the standardized path, not the URL — `URL` equality is
    /// surprising across `file://x` vs `file://x/`, symlink vs resolved,
    /// and other normal-looking variations that would all hit the same
    /// inode.
    private static var held: Set<String> = []

    /// Start the security scope on `url` and remember we did, so we
    /// don't double-start the same URL (which is a real cost). Idempotent.
    static func retain(_ url: URL) {
        let key = url.standardizedFileURL.path
        guard !held.contains(key) else { return }
        if url.startAccessingSecurityScopedResource() {
            held.insert(key)
        }
        // If startAccessing… returned false the URL either wasn't
        // security-scoped (e.g. a `file://` we constructed ourselves)
        // or sandboxing isn't in effect. Either way, no harm done —
        // a subsequent direct read will succeed or fail on its own.
    }
}
