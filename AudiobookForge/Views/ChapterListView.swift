import SwiftUI
import UniformTypeIdentifiers

struct ChapterListView: View {
    @Environment(AudiobookProject.self) private var project
    @State private var selection = Set<Chapter.ID>()
    @State private var isImporting = false
    @State private var isTargeted = false

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
            if case .success(let urls) = result {
                Task { await importPaths(urls) }
            }
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

    /// Pulled out so the row builders close over `Binding`s into the
    /// chapters array by index — gives us O(1) title bindings instead of
    /// the O(n) `firstIndex(where:)` per keystroke we had before.
    @ViewBuilder
    private func chapterTable(bindable: Bindable<AudiobookProject>) -> some View {
        let chapters = bindable.wrappedValue.chapters
        let indexByID = Dictionary(
            uniqueKeysWithValues: chapters.enumerated().map { ($1.id, $0) })

        Table(chapters, selection: $selection) {
            TableColumn("#") { chap in
                Text("\((indexByID[chap.id] ?? 0) + 1)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 24, ideal: 32, max: 40)

            TableColumn("Title") { chap in
                if let i = indexByID[chap.id] {
                    TextField("", text: bindable.chapters[i].title)
                        .textFieldStyle(.plain)
                }
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
            Button {
                isImporting = true
            } label: {
                Label("Add Files…", systemImage: "plus")
            }
            .controlSize(.small)
        }
        .padding(10)
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
                .controlSize(.large)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: helpers

    private func deleteSelected() {
        project.chapters.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    private func importPaths(_ urls: [URL]) async {
        let files = await Task.detached(priority: .userInitiated) { () -> [URL] in
            var results: [URL] = []
            for url in urls {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    // Use NSDirectoryEnumerator.allObjects — the for-in
                    // form trips a Swift 6 `makeIterator` warning in
                    // async contexts.
                    let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
                    let all = walker?.allObjects.compactMap { $0 as? URL } ?? []
                    results.append(contentsOf: all.filter(isAudio))
                } else if isAudio(url) {
                    results.append(url)
                }
            }
            // Natural sort so "Chapter 2" precedes "Chapter 10".
            results.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            return results
        }.value

        // Probe concurrently — serial awaits stall drag-drop on long books.
        let probed: [(Int, URL, AudioProbe.Probed)] = await withTaskGroup(
            of: (Int, URL, AudioProbe.Probed).self
        ) { group in
            for (i, url) in files.enumerated() {
                group.addTask { (i, url, await AudioProbe.probe(url)) }
            }
            var out: [(Int, URL, AudioProbe.Probed)] = []
            for await item in group { out.append(item) }
            return out.sorted { $0.0 < $1.0 }
        }

        let added: [Chapter] = probed.map { _, url, p in
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
            if let first = probed.first?.2, project.metadata.isEmpty {
                if project.metadata.title.isEmpty { project.metadata.title = first.album ?? "" }
                if project.metadata.author.isEmpty { project.metadata.author = first.artist ?? "" }
            }
            project.chapters.append(contentsOf: added)
        }
    }

}

private let audioExtensions: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "flac", "ogg", "opus"]

private func isAudio(_ url: URL) -> Bool {
    audioExtensions.contains(url.pathExtension.lowercased())
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
