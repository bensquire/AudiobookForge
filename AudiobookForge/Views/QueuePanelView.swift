import SwiftUI

struct QueuePanelView: View {
    @Environment(QueueManager.self) private var queue

    var body: some View {
        VStack(spacing: 0) {
            header
            if queue.items.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(queue.items) { item in
                            QueueRow(item: item)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var header: some View {
        let pending = queue.items.filter(\.status.isActive).count
        let done = queue.items.filter(\.status.isSucceeded).count
        return HStack(spacing: 8) {
            Text("Queue").font(.headline)
            if !queue.items.isEmpty {
                Text("\(pending) pending · \(done) done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if queue.items.contains(where: \.status.isFinished) {
                Button("Clear Done") { queue.clearFinished() }
                    .accessibilityIdentifier("queue.clearDone")
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Queue is empty")
                .foregroundStyle(.secondary)
            Text("Prep a book on the left and click **Add to Queue**.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct QueueRow: View {
    @Environment(QueueManager.self) private var queue
    @Environment(AudiobookProject.self) private var project
    let item: QueueItem
    @State private var hovering = false
    @State private var pendingMode: HydrateMode?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Status-coloured stripe on the leading edge reads at a glance
            // without tinting the whole card.
            RoundedRectangle(cornerRadius: 2)
                .fill(item.status.tint)
                .frame(width: 3)
                .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    CoverThumbnail(data: item.spec.metadata.coverData, size: 40, cornerRadius: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title.isEmpty ? "Untitled" : item.title)
                            .font(.callout).bold()
                            .lineLimit(1)
                        Text(item.author.isEmpty ? "Unknown" : item.author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text((item.finalOutputURL ?? item.spec.outputURL).lastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Badge(text: item.status.label, color: item.status.tint)
                        .accessibilityIdentifier("queue.item.status")
                }

                if item.status.isRunning {
                    VStack(alignment: .leading, spacing: 3) {
                        ProgressView(value: item.progress)
                            .progressViewStyle(.linear)
                            .tint(item.status.tint)
                        if let label = item.progressLabel {
                            Text(label).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } else if case let .failed(msg) = item.status {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                actionRow
            }
            .padding(.vertical, 10)
            .padding(.trailing, 12)
            .padding(.leading, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(hovering ? 1.0 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("queue.item")
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .confirmationDialog(
            "Replace current prep area?",
            isPresented: Binding(
                get: { pendingMode != nil },
                set: { if !$0 { pendingMode = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingMode
        ) { mode in
            Button("Replace", role: .destructive) { applyHydrate(mode: mode) }
            Button("Cancel", role: .cancel) {}
        } message: { mode in
            switch mode {
            case .edit:
                Text("Loading this item will discard the book you're currently prepping.")
            case .duplicate:
                Text("Duplicating this item will discard the book you're currently prepping.")
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 4) {
            Spacer()
            if item.status.isSucceeded, let url = item.finalOutputURL {
                rowButton("Reveal", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                rowButton("Duplicate", systemImage: "plus.square.on.square") {
                    requestHydrate(mode: .duplicate)
                }
            }
            // Editable states: anything not running and not already done.
            // Succeeded items use Duplicate above; running items have to
            // be cancelled first.
            if item.status.isPending || item.status.isRetryable {
                rowButton("Edit", systemImage: "pencil") {
                    requestHydrate(mode: .edit)
                }
            }
            if item.status.isRetryable {
                rowButton("Retry", systemImage: "arrow.clockwise") { queue.retry(item) }
            }
            if item.status.isFinished {
                rowButton("Remove", systemImage: "xmark") { queue.remove(item) }
            } else {
                rowButton("Cancel", systemImage: "stop.fill") { queue.cancel(item) }
            }
        }
    }

    /// Either show the confirm dialog (if the prep area has work) or
    /// apply the hydrate immediately.
    private func requestHydrate(mode: HydrateMode) {
        if project.canEnqueue {
            pendingMode = mode
        } else {
            applyHydrate(mode: mode)
        }
    }

    private func applyHydrate(mode: HydrateMode) {
        project.hydrate(from: item.spec)
        if mode == .edit {
            queue.remove(item)
        }
    }

    private func rowButton(_ label: String, systemImage: String,
                           action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.caption)
        }
        .accessibilityIdentifier("queue.item.\(label.lowercased())")
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }
}

/// The user's intent when hydrating a queued item back into the prep
/// area. `Identifiable` so it can drive `confirmationDialog(presenting:)`
/// directly — no wrapper struct needed.
private enum HydrateMode: String, Identifiable {
    case edit, duplicate
    var id: String {
        rawValue
    }
}

private struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2).bold()
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
