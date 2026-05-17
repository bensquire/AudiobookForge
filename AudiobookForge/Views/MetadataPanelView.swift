import SwiftUI

struct MetadataPanelView: View {
    @Environment(AudiobookProject.self) private var project

    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var results: [MetadataSearchResult] = []
    @State private var searchError: String?
    @AppStorage("metadata.provider") private var providerRaw: String = MetadataSearch.Provider.all.rawValue

    private var provider: MetadataSearch.Provider {
        MetadataSearch.Provider(rawValue: providerRaw) ?? .all
    }

    var body: some View {
        @Bindable var project = project

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                coverSection
                searchSection
                Divider()

                field("Title", text: $project.metadata.title)
                field("Subtitle", text: $project.metadata.subtitle)
                field("Author", text: $project.metadata.author)
                field("Narrator", text: $project.metadata.narrator)
                HStack {
                    field("Series", text: $project.metadata.series)
                    field("#", text: $project.metadata.seriesPosition)
                        .frame(width: 70)
                }
                HStack {
                    field("Year", text: $project.metadata.year).frame(width: 100)
                    field("Genre", text: $project.metadata.genre)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $project.metadata.description)
                        .font(.body)
                        .frame(minHeight: 90)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor)))
                }
            }
            .padding(14)
        }
        // Project reset (Add to Queue, Clear, or Edit-loading another
        // item) wipes the prep area; the search panel's local state
        // should follow. resetToken changes only on reset()/hydrate(),
        // not on the user just deleting their last chapter.
        .onChange(of: project.resetToken) { _, _ in clearSearch() }
    }

    private var coverSection: some View {
        @Bindable var project = project
        return HStack(alignment: .top, spacing: 12) {
            CoverThumbnail(data: project.metadata.coverData, size: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text(project.metadata.title.isEmpty ? "Untitled" : project.metadata.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(project.metadata.author.isEmpty ? "Unknown Author" : project.metadata.author)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Button("Choose Cover…", action: chooseCover)
                        .controlSize(.small)
                    if project.metadata.coverData != nil {
                        Button("Clear") { project.metadata.coverData = nil }
                            .controlSize(.small)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search metadata…", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(runSearch)
                Picker("", selection: $providerRaw) {
                    ForEach(MetadataSearch.Provider.allCases) { p in
                        Text(p.label).tag(p.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                Button(action: runSearch) {
                    if isSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                if !results.isEmpty || !searchQuery.isEmpty || searchError != nil {
                    Button {
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search results")
                }
            }
            if let err = searchError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(results) { r in
                        SearchResultRow(result: r) { apply(r) }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("", text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func clearSearch() {
        searchQuery = ""
        results = []
        searchError = nil
    }

    private func runSearch() {
        Task {
            isSearching = true
            searchError = nil
            do {
                let q = searchQuery.trimmingCharacters(in: .whitespaces)
                let found = try await MetadataSearch.search(query: q, provider: provider)
                results = Array(found.prefix(8))
            } catch {
                searchError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
            isSearching = false
        }
    }

    private func apply(_ result: MetadataSearchResult) {
        Task {
            // Most providers already return the cover URL from search, so
            // start the cover download in parallel with the enrich call
            // rather than waiting on enrich first.
            async let enrichedTask = await (try? MetadataSearch.enrich(result)) ?? result
            async let initialCover: Data? = {
                guard let url = result.coverURL else { return nil }
                return try? await MetadataSearch.fetchCover(url)
            }()

            let enriched = await enrichedTask
            // If enrich returned a different (e.g. higher-res) cover URL,
            // prefer that. Otherwise use the parallel download.
            let coverData: Data?
            let coverURL: URL?
            if let enrichedURL = enriched.coverURL, enrichedURL != result.coverURL {
                coverData = try? await MetadataSearch.fetchCover(enrichedURL)
                coverURL = enrichedURL
            } else {
                coverData = await initialCover
                coverURL = result.coverURL
            }

            await MainActor.run {
                project.metadata.title = enriched.title
                project.metadata.author = enriched.author
                if let n = enriched.narrator { project.metadata.narrator = n }
                if let s = enriched.series { project.metadata.series = s }
                if let sp = enriched.seriesPosition { project.metadata.seriesPosition = sp }
                if let y = enriched.year { project.metadata.year = y }
                if let d = enriched.description { project.metadata.description = d }
                if let data = coverData {
                    project.metadata.coverData = data
                    project.metadata.coverSourceURL = coverURL
                }
            }
        }
    }

    private func chooseCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            SecurityScope.retain(url)
            project.metadata.coverData = try? Data(contentsOf: url)
            project.metadata.coverSourceURL = url
        }
    }
}

private struct SearchResultRow: View {
    let result: MetadataSearchResult
    let onApply: () -> Void

    var body: some View {
        Button(action: onApply) {
            HStack(alignment: .top, spacing: 8) {
                AsyncImage(url: result.coverURL) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    Color.gray.opacity(0.15)
                }
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title).font(.callout).lineLimit(1)
                    Text(result.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(result.source.label).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
