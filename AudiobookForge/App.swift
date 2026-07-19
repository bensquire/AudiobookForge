import ForgeCore
import SwiftUI

@main
struct AudiobookForgeApp: App {
    @State private var project: AudiobookProject
    @State private var queue: QueueManager

    init() {
        let queue = QueueManager()
        // Wired here rather than inside QueueManager so unit tests never
        // touch UserNotifications (needs a host app bundle).
        QueueNotifier.install()
        queue.onBatchStarted = { QueueNotifier.requestAuthorization() }
        queue.onBatchFinished = { succeeded, failed in
            QueueNotifier.queueDrained(succeeded: succeeded, failed: failed)
        }
        _queue = State(initialValue: queue)

        let project = AudiobookProject()
        project.settings = SettingsStore.load()
        _project = State(initialValue: project)
    }

    var body: some Scene {
        WindowGroup("AudiobookForge") {
            ContentView()
                .environment(project)
                .environment(queue)
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
