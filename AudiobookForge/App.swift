import AppKit
import ForgeCore
import SwiftUI

@main
struct AudiobookForgeApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var project: AudiobookProject

    init() {
        let project = AudiobookProject()
        project.settings = SettingsStore.load()
        _project = State(initialValue: project)
    }

    var body: some Scene {
        WindowGroup("AudiobookForge") {
            ContentView()
                .environment(project)
                .environment(appDelegate.queue)
                // 1120 = the three panes' minimum widths; anything larger
                // won't fit a 13" MacBook's default scaled resolution.
                .frame(minWidth: 1120, minHeight: 640)
                .onChange(of: project.settings) { oldSettings, newSettings in
                    SettingsStore.save(newSettings, previous: oldSettings)
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Owns the process-lifecycle side of the queue: notification wiring at
/// launch and an orderly stop at quit. Without the latter, Cmd-Q
/// mid-encode leaves up to a dozen ffmpeg children writing into
/// `.partial` files in the user's output folder.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let queue: QueueManager

    override init() {
        queue = QueueManager()
        // Wired here rather than inside QueueManager so unit tests never
        // touch UserNotifications (needs a host app bundle).
        QueueNotifier.install()
        queue.onBatchStarted = { QueueNotifier.requestAuthorization() }
        queue.onBatchFinished = { succeeded, failed in
            QueueNotifier.queueDrained(succeeded: succeeded, failed: failed)
        }
        super.init()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard queue.isProcessing else { return .terminateNow }
        Task { @MainActor in
            await queue.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
