import Foundation
import UserNotifications

/// Posts a local notification when the encode queue drains. Kept out of
/// QueueManager so unit tests never touch UserNotifications (its center
/// requires a host app bundle and crashes in a bare test runner) — the
/// app wires these in via QueueManager's onBatchStarted/onBatchFinished.
@MainActor
enum QueueNotifier {
    /// Without a delegate macOS silently swallows notifications while
    /// the app is frontmost; this one opts into showing them anyway.
    /// UNUserNotificationCenter holds its delegate weakly, so keep the
    /// strong reference here.
    private static let presenter = ForegroundPresenter()

    /// Call once at app startup, before any notification is requested.
    static func install() {
        UNUserNotificationCenter.current().delegate = presenter
    }

    /// Ask once, at the moment the user kicks off long-running work.
    /// Safe to call repeatedly — the system remembers the answer.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { granted, error in
            // Auth quietly fails on unsigned/dev builds — surface it in
            // the log so a missing "queue finished" banner is diagnosable.
            if let error {
                NSLog("QueueNotifier: authorization failed: \(error)")
            } else if !granted {
                NSLog("QueueNotifier: notifications not granted")
            }
        }
    }

    static func queueDrained(succeeded: Int, failed: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Audiobook queue finished"
        content.body = summary(succeeded: succeeded, failed: failed)
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
        ) { error in
            if let error {
                NSLog("QueueNotifier: delivery failed: \(error)")
            }
        }
    }

    private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _: UNUserNotificationCenter,
            willPresent _: UNNotification,
            withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            completionHandler([.banner, .sound])
        }
    }

    /// "3 books encoded" / "2 books encoded, 1 failed" / "1 book failed".
    /// Pure so it's unit-testable without a notification center.
    nonisolated static func summary(succeeded: Int, failed: Int) -> String {
        let book = { (n: Int) in n == 1 ? "1 book" : "\(n) books" }
        switch (succeeded, failed) {
        case (_, 0): return "\(book(succeeded)) encoded"
        case (0, _): return "\(book(failed)) failed"
        default: return "\(book(succeeded)) encoded, \(failed) failed"
        }
    }
}
