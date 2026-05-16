import SwiftUI

@main
struct AudiobookForgeApp: App {
    @State private var project = AudiobookProject()
    @State private var queue = QueueManager()

    var body: some Scene {
        WindowGroup("AudiobookForge") {
            ContentView()
                .environment(project)
                .environment(queue)
                .frame(minWidth: 1300, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
