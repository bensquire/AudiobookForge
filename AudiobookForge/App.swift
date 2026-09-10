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
                // Sandbox grants are taken when a URL is picked and are
                // owed a stop; here is the one place that can see
                // everything still referring to one, so the sweep lives
                // here rather than at each site that drops a reference.
                .onChange(of: scopedURLsInUse) { _, inUse in
                    SecurityScope.releaseUnused(keeping: inUse)
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }

    /// Every picked URL the app still refers to: the draft's chapters and
    /// output folder, and the same for each queued item, which outlives
    /// the draft it came from.
    private var scopedURLsInUse: Set<URL> {
        var urls = Set(project.chapters.map(\.sourceURL))
        if let outputDirectory = project.settings.outputDirectory { urls.insert(outputDirectory) }
        for item in appDelegate.queue.items {
            urls.formUnion(item.spec.chapters.map(\.sourceURL))
            if let outputDirectory = item.spec.settings.outputDirectory { urls.insert(outputDirectory) }
        }
        return urls
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
        // Wired here rather than inside QueueManager so ForgeCore (and
        // its tests, and the CLI) never touch UserNotifications.
        QueueNotifier.install()
        queue.onBatchStarted = { QueueNotifier.requestAuthorization() }
        queue.onBatchFinished = { succeeded, failed in
            QueueNotifier.queueDrained(succeeded: succeeded, failed: failed)
        }
        super.init()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard queue.isProcessing else {
            SecurityScope.releaseAll()
            return .terminateNow
        }
        Task {
            await queue.shutdown()
            // After the encodes have stopped, so nothing loses access to
            // a file it is still reading.
            SecurityScope.releaseAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
