import ForgeCore
import Foundation
import UserNotifications

/// Posts a local notification when the encode queue drains. Lives in
/// the app target, not ForgeCore: UserNotifications needs a host app
/// bundle (it crashes in a bare test runner and is dead weight in the
/// CLI). The app wires it in via QueueManager's onBatchStarted /
/// onBatchFinished; the message text itself is `QueueSummary` in core so
/// it stays unit-testable.
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
        content.body = QueueSummary.text(succeeded: succeeded, failed: failed)
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
}
