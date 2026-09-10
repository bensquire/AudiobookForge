import Foundation

/// The queue-drained message: "3 books encoded" / "2 books encoded,
/// 1 failed" / "1 book failed". Pure so it's unit-testable without a
/// notification center; the app's QueueNotifier puts it in a banner.
public enum QueueSummary {
    /// "3 books encoded" / "2 books encoded, 1 failed" / "1 book failed".
    /// Pure so it's unit-testable without a notification center.
    public static func text(succeeded: Int, failed: Int) -> String {
        let book = { (n: Int) in n == 1 ? "1 book" : "\(n) books" }
        switch (succeeded, failed) {
        case (_, 0): return "\(book(succeeded)) encoded"
        case (0, _): return "\(book(failed)) failed"
        default: return "\(book(succeeded)) encoded, \(failed) failed"
        }
    }
}
