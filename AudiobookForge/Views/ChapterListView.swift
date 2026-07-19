import ForgeCore
import SwiftUI
import UniformTypeIdentifiers

struct ChapterListView: View {
    @Environment(AudiobookProject.self) private var project
    @State private var selection = Set<Chapter.ID>()
    @State private var isImporting = false
    @State private var isTargeted = false
    @State private var confirmClear = false
    /// Files skipped on import because they already carry embedded
    /// chapters — flattening one into a single chapter would silently
    /// destroy its structure (Audible m4bs etc. are already forged).
    @State private var skippedFinishedBooks: [String] = []

    var body: some View {
        @Bindable var project = project

        VStack(spacing: 0) {
            header
            Divider()
            if project.chapters.isEmpty {
                dropZone
            } else {
                chapterTable(bindable: $project)
            }
        }
        .dropDestination(for: URL.self, action: { urls, _ in
            Task { await importPaths(urls) }
            return true
        }, isTargeted: { isTargeted = $0 })
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.audio, .mp3, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                Task { await importPaths(urls) }
            }
        }
        .alert(
            "Already a chaptered audiobook",
            isPresented: Binding(
                get: { !skippedFinishedBooks.isEmpty },
                set: { if !$0 { skippedFinishedBooks = [] } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                skippedFinishedBooks.joined(separator: "\n")
                    + "\n\nThese files already contain chapter markers — "
                    + "importing them here would flatten the book into a "
                    + "single chapter. Nothing to forge."
            )
        }
        .overlay(alignment: .center) {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Pulled out so we can close over a fresh per-render `indexByID`
    /// dictionary for the row-number column. Title binding goes through
    /// `titleBinding(for:)` which looks up by id at access time — Table's
    /// row closures hold stale `chap` references during diffs (notably
    /// after a `project.reset()`), and index-based bindings into the
    /// array would crash on the now-empty array.
    @ViewBuilder
    private func chapterTable(bindable _: Bindable<AudiobookProject>) -> some View {
        let chapters = project.chapters
        let indexByID = Dictionary(
            uniqueKeysWithValues: chapters.enumerated().map { ($1.id, $0) }
        )

        Table(chapters, selection: $selection) {
            TableColumn("#") { chap in
                Text("\((indexByID[chap.id] ?? 0) + 1)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 24, ideal: 32, max: 40)

            TableColumn("Title") { chap in
                TextField("", text: titleBinding(for: chap.id))
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("chapters.rowTitle")
            }

            TableColumn("Duration") { chap in
                Text(chap.displayDuration)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 70, max: 90)

            TableColumn("File") { chap in
                Text(chap.sourceURL.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
        }
        .onDeleteCommand(perform: deleteSelected)
        .accessibilityIdentifier("chapters.table")
    }

    private var header: some View {
        HStack {
            Text("Chapters").font(.headline)
            Spacer()
            if !project.chapters.isEmpty {
                Text("\(project.chapters.count) files · \(project.totalDuration.abbreviated)")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            if hasDraftWork {
                Button {
                    if project.canEnqueue {
                        confirmClear = true
                    } else {
                        project.reset()
                    }
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .accessibilityIdentifier("chapters.clear")
                .controlSize(.small)
                .help("Discard the current book and start over")
            }
            Button {
                isImporting = true
            } label: {
                Label("Add Files…", systemImage: "plus")
            }
            .accessibilityIdentifier("chapters.addFiles")
            .controlSize(.small)
        }
        .padding(10)
        .confirmationDialog(
            "Discard current book?",
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { project.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Chapters and metadata will be cleared. Output folder, bitrate, and gain settings are kept.")
        }
    }

    private var hasDraftWork: Bool {
        !project.chapters.isEmpty
            || !project.metadata.isEmpty
            || project.metadata.coverData != nil
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Drop MP3 files or a folder here")
                .font(.title3)
            Text("They'll be ordered naturally and turned into chapters.")
                .foregroundStyle(.secondary)
                .font(.callout)
            Button("Choose Files…") { isImporting = true }
                .accessibilityIdentifier("chapters.chooseFiles")
                .controlSize(.large)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: helpers

    /// Title binding that looks up the chapter by id at access time so it
    /// survives `chapters` being mutated (cleared on enqueue + reset, etc).
    /// Index-based bindings would crash the moment the array shrank under
    /// a stale row closure held by `Table` during a diff.
    private func titleBinding(for id: Chapter.ID) -> Binding<String> {
        Binding(
            get: { project.chapters.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                if let i = project.chapters.firstIndex(where: { $0.id == id }) {
                    project.chapters[i].title = newValue
                }
            }
        )
    }

    private func deleteSelected() {
        project.chapters.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    private func importPaths(_ urls: [URL]) async {
        // Hold the sandbox grant on every dropped/picked URL up front —
        // this includes folders whose children inherit access while the
        // parent's scope is held. Without this the AudioProbe ffmpeg
        // pass (and later encode) sees EPERM on the input file.
        for url in urls {
            SecurityScope.retain(url)
        }

        let existingPaths = Set(project.chapters.map(\.sourceURL.standardizedFileURL.path))
        let files = await Task.detached(priority: .userInitiated) { () -> [URL] in
            var results: [URL] = []
            for url in urls {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    // Use NSDirectoryEnumerator.allObjects — the for-in
                    // form trips a Swift 6 `makeIterator` warning in
                    // async contexts. skipsHiddenFiles keeps AppleDouble
                    // sidecars ("._Chapter 01.mp3" on FAT/exFAT drives)
                    // from becoming zero-duration junk chapters.
                    let walker = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    )
                    let all = walker?.allObjects.compactMap { $0 as? URL } ?? []
                    results.append(contentsOf: all.filter(isAudio))
                } else if isAudio(url) {
                    results.append(url)
                }
            }
            // Natural sort so "Chapter 2" precedes "Chapter 10".
            results
                .sort {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }
            // Same file dropped twice (or already in the chapter list)
            // shouldn't become a duplicate chapter.
            return ChapterImport.dedupe(results, existingPaths: existingPaths)
        }.value

        // Probe concurrently — serial awaits stall drag-drop on long books.
        let probed: [(Int, URL, AudioProbe.Probed)] = await withTaskGroup(
            of: (Int, URL, AudioProbe.Probed).self
        ) { group in
            for (i, url) in files.enumerated() {
                group.addTask { await (i, url, AudioProbe.probe(url)) }
            }
            var out: [(Int, URL, AudioProbe.Probed)] = []
            for await item in group {
                out.append(item)
            }
            return out.sorted { $0.0 < $1.0 }
        }

        let (importable, skippedNames) = ChapterImport.partitionFinished(
            probed.map { (url: $0.1, info: $0.2) }
        )

        let added: [Chapter] = importable.map { url, p in
            Chapter(
                sourceURL: url,
                title: p.title?.nilIfEmpty ?? url.deletingPathExtension().lastPathComponent,
                duration: p.duration,
                sourceBitrate: p.bitrate,
                codec: p.codec,
                sampleRate: p.sampleRate,
                channels: p.channels
            )
        }

        await MainActor.run {
            if let first = importable.first?.info, project.metadata.isEmpty {
                if project.metadata.title.isEmpty { project.metadata.title = first.album ?? "" }
                if project.metadata.author.isEmpty { project.metadata.author = first.artist ?? "" }
            }
            project.chapters.append(contentsOf: added)
            skippedFinishedBooks = skippedNames
        }
    }
}

private let audioExtensions: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "flac", "ogg", "opus"]

private func isAudio(_ url: URL) -> Bool {
    audioExtensions.contains(url.pathExtension.lowercased())
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
