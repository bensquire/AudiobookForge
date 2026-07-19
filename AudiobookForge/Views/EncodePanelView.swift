import ForgeCore
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
            // Labels sit outside the pickers (labelsHidden) so "Bitrate"
            // starts at the row's leading edge, aligned with "Output:"
            // below — a Picker's built-in label right-aligns inside a
            // fixed frame.
            HStack(spacing: 8) {
                Text("Bitrate")
                    .foregroundStyle(.secondary)
                Picker("Bitrate", selection: $project.settings.bitrate) {
                    ForEach(EncodeSettings.Bitrate.allCases) { b in
                        Text(b.label).tag(b)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("encode.bitrate")
                .frame(width: 140)

                Text("Gain")
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                Picker("Gain", selection: $project.settings.gainBoost) {
                    ForEach(EncodeSettings.GainBoost.allCases) { g in
                        Text(g.label).tag(g)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("encode.gain")
                .frame(width: 140)

                Spacer()
            }

            outputControl

            if willRemux {
                Label("Lossless remux — sources are already AAC, no re-encode needed",
                      systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack {
                // Gate on canEnqueue so the empty prep area doesn't show a
                // meaningless "Will save as .m4b" built from blank metadata.
                if let name = plannedOutputName, project.canEnqueue {
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
        // A finishing item leaves the count unchanged but just dropped a
        // file at (possibly) the planned path — refresh the collision hint.
        // (lazy: this expression re-evaluates on every progress tick, so
        // don't build a throwaway array each time.)
        .onChange(of: queue.items.lazy.filter(\.status.isFinished).count) { _, _ in
            refreshPlannedOutput()
        }
    }

    /// Labelled row. The label flips between the generic "Output folder"
    /// when nothing is picked and the actual destination directory once a
    /// folder is selected (folder name + any template subdirs that will
    /// be created from metadata). The button stays as a stable "Change…"
    /// affordance.
    /// "Output: [📁 Folder name ▾]" — the labelled-button idiom used by
    /// Permute, Bakery, Audiobook Builder etc. The button itself carries
    /// the current selection (last path component); full path lives in
    /// the tooltip.
    private var outputControl: some View {
        let dir = project.settings.outputDirectory
        return HStack(spacing: 8) {
            Text("Output:")
                .foregroundStyle(.secondary)
            Button(action: chooseOutputDir) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                    Text(dir?.lastPathComponent ?? "Choose folder…")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .accessibilityIdentifier("encode.chooseOutput")
            .help(dir?.path ?? "")
            Spacer(minLength: 12)
            if let format = outputFormatLabel {
                Text(format)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var enqueueButton: some View {
        Button {
            // Only clear the prep area if the enqueue actually happened —
            // a nil return (e.g. output dir vanished since the last
            // render) must not discard the user's draft.
            guard queue.enqueue(from: project) != nil else { return }
            project.reset()
        } label: {
            Label("Add to Queue", systemImage: "plus.rectangle.on.rectangle")
                .frame(minWidth: 140)
        }
        .accessibilityIdentifier("encode.addToQueue")
        .controlSize(.large)
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(!project.canEnqueue)
    }

    /// "192 kbps · Stereo · AAC · +6 dB" — the actual format the .m4b
    /// will be written in, given the current bitrate, source channel
    /// layout, and gain setting. Hidden until chapters are dropped
    /// because channel info isn't known otherwise.
    private var outputFormatLabel: String? {
        guard let first = project.chapters.first else { return nil }
        let bitrate = EncodeJob.resolveBitrate(
            chapters: project.chapters, settings: project.settings
        ).replacingOccurrences(of: "k", with: " kbps")
        let channels = channelLayoutLabel(first.channels)
        return [bitrate, channels, "AAC", project.settings.gainBoost.suffix]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func channelLayoutLabel(_ count: Int) -> String {
        switch count {
        case 1: "Mono"
        case 2: "Stereo"
        case 6: "5.1"
        case 8: "7.1"
        default: count > 0 ? "\(count) ch" : ""
        }
    }

    private func chooseOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            SecurityScope.retain(url)
            project.settings.outputDirectory = url
        }
    }
}
