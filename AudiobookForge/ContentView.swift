import ForgeCore
import SwiftUI

struct ContentView: View {
    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                ChapterListView()
                Divider()
                EncodePanelView()
            }
            .frame(minWidth: 480, idealWidth: 540)

            MetadataPanelView()
                .frame(minWidth: 360, idealWidth: 400)

            QueuePanelView()
                .frame(minWidth: 280, idealWidth: 340)
        }
    }
}
