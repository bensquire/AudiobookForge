import SwiftUI

struct EncodePanelView: View {
    @Environment(AudiobookProject.self) private var project
    @Environment(QueueManager.self) private var queue

    /// Cached so we don't re-stat the filesystem on every render
    /// (this view re-evaluates on every encode progress tick).
    @State private var plannedOutputName: String?

    private var willRemux: Bool {
        EncodeJob.canRemux(chapters: project.chapters, settings: project.settings)
    }

    private func refreshPlannedOutput() {
        plannedOutputName = queue.plannedOutputURL(for: project)?.lastPathComponent
    }

    var body: some View {
        @Bindable var project = project

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("Bitrate", selection: $project.settings.bitrate) {
                    ForEach(EncodeSettings.Bitrate.allCases) { b in
                        Text(b.label).tag(b)
                    }
                }
                .frame(width: 200)

                Picker("Codec", selection: $project.settings.codec) {
                    ForEach(EncodeSettings.Codec.allCases) { c in
                        Text(c.rawValue.uppercased()).tag(c)
                    }
                }
                .frame(width: 160)

                Spacer()

                outputControl
            }

            if willRemux {
                Label("Lossless remux — sources are already AAC, no re-encode needed",
                      systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack {
                if let name = plannedOutputName {
                    Label("Will save as \(name)", systemImage: "doc.badge.arrow.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                enqueueButton
            }
        }
        .padding(12)
        .task { refreshPlannedOutput() }
        .onChange(of: project.metadata.title) { _, _ in refreshPlannedOutput() }
        .onChange(of: project.metadata.author) { _, _ in refreshPlannedOutput() }
        .onChange(of: project.metadata.series) { _, _ in refreshPlannedOutput() }
        .onChange(of: project.metadata.year) { _, _ in refreshPlannedOutput() }
        .onChange(of: project.settings.outputDirectory) { _, _ in refreshPlannedOutput() }
        .onChange(of: project.settings.filenameTemplate) { _, _ in refreshPlannedOutput() }
        .onChange(of: queue.items.count) { _, _ in refreshPlannedOutput() }
    }

    private var outputControl: some View {
        @Bindable var project = project
        return HStack(spacing: 6) {
            Text(project.settings.outputDirectory?.path ?? "No output folder")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(maxWidth: 280, alignment: .trailing)
            Button("Output…") { chooseOutputDir() }
                .controlSize(.small)
        }
    }

    private var enqueueButton: some View {
        Button {
            _ = queue.enqueue(from: project)
            project.reset()
        } label: {
            Label("Add to Queue", systemImage: "plus.rectangle.on.rectangle")
                .frame(minWidth: 140)
        }
        .controlSize(.large)
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(!project.canEnqueue)
    }

    private func chooseOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            project.settings.outputDirectory = panel.url
        }
    }
}
