import Foundation

/// Audiobook metadata lookup. Primary source is Audnexus (community Audible
/// mirror used by Audiobookshelf/Plex). iTunes Search API is the fallback
/// for non-Audible titles.
enum MetadataSearch {
    enum Provider: String, CaseIterable, Identifiable {
        case audnexus
        case itunes
        case all

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .audnexus: "Audnexus"
            case .itunes: "iTunes"
            case .all: "All providers"
            }
        }
    }

    enum SearchError: Error, LocalizedError {
        case badResponse
        var errorDescription: String? {
            switch self {
            case .badResponse: "Unexpected response from metadata server"
            }
        }
    }

    static func search(query: String, provider: Provider = .all) async throws -> [MetadataSearchResult] {
        let results: [MetadataSearchResult]
        switch provider {
        case .audnexus:
            results = await (try? audnexusSearch(query: query)) ?? []
        case .itunes:
            results = await (try? itunesSearch(query: query)) ?? []
        case .all:
            // Audnexus first in the merged list because it's the higher-
            // quality source for audiobooks specifically; Set.insert
            // preserves that priority when iTunes returns the same title.
            async let audnex = await (try? audnexusSearch(query: query)) ?? []
            async let itunes = await (try? itunesSearch(query: query)) ?? []
            results = await audnex + itunes
        }
        var seen = Set<String>()
        return results.filter { seen.insert(($0.title + "|" + $0.author).lowercased()).inserted }
    }

    /// Fetch the full Audnexus record for richer description, full
    /// narrator list, and a higher-res cover URL.
    static func enrich(_ result: MetadataSearchResult) async throws -> MetadataSearchResult {
        guard result.source == .audnexus else { return result }
        let url = URL(string: "https://api.audnex.us/books/\(result.id)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let book = try JSONDecoder().decode(AudnexusBook.self, from: data)
        return result.merging(book)
    }

    static func fetchCover(_ url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    // MARK: - Providers

    private static func audnexusSearch(query: String) async throws -> [MetadataSearchResult] {
        var comps = URLComponents(string: "https://api.audnex.us/books")!
        comps.queryItems = [URLQueryItem(name: "name", value: query)]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let books = (try? JSONDecoder().decode([AudnexusBook].self, from: data)) ?? []
        return books.map(MetadataSearchResult.init(audnexus:))
    }

    private static func itunesSearch(query: String) async throws -> [MetadataSearchResult] {
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "audiobook"),
            URLQueryItem(name: "limit", value: "10")
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let envelope = try JSONDecoder().decode(ITunesEnvelope.self, from: data)
        return envelope.results.map(MetadataSearchResult.init(itunes:))
    }
}

// MARK: - Audnexus DTOs

private struct AudnexusBook: Decodable {
    let asin: String
    let title: String
    let authors: [Named]?
    let narrators: [Named]?
    let seriesPrimary: Series?
    let releaseDate: String?
    let image: String?
    let summary: String?
    let description: String?

    struct Named: Decodable { let name: String }
    struct Series: Decodable {
        let name: String
        let position: String?
    }
}

private extension MetadataSearchResult {
    init(audnexus book: AudnexusBook) {
        self.init(
            id: book.asin,
            source: .audnexus,
            title: book.title,
            author: (book.authors ?? []).map(\.name).joined(separator: ", "),
            narrator: book.narrators?.map(\.name).joined(separator: ", "),
            series: book.seriesPrimary?.name,
            seriesPosition: book.seriesPrimary?.position,
            year: book.releaseDate.map { String($0.prefix(4)) },
            description: book.summary ?? book.description,
            coverURL: book.image.flatMap(URL.init(string:))
        )
    }

    func merging(_ book: AudnexusBook) -> MetadataSearchResult {
        let narrators = (book.narrators ?? []).map(\.name).joined(separator: ", ")
        return MetadataSearchResult(
            id: id,
            source: source,
            title: book.title.isEmpty ? title : book.title,
            author: author,
            narrator: narrators.isEmpty ? narrator : narrators,
            series: series ?? book.seriesPrimary?.name,
            seriesPosition: seriesPosition ?? book.seriesPrimary?.position,
            year: year,
            description: book.summary ?? description,
            coverURL: coverURL ?? book.image.flatMap(URL.init(string:))
        )
    }
}

// MARK: - iTunes DTOs

private struct ITunesEnvelope: Decodable {
    let results: [ITunesResult]
}

private struct ITunesResult: Decodable {
    let collectionId: Int?
    let collectionName: String?
    let artistName: String?
    let releaseDate: String?
    let description: String?
    let artworkUrl100: String?
}

private extension MetadataSearchResult {
    init(itunes r: ITunesResult) {
        // Bump artwork up from the default 100x100 thumbnail.
        let art = r.artworkUrl100?.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        self.init(
            id: r.collectionId.map(String.init) ?? UUID().uuidString,
            source: .itunes,
            title: r.collectionName ?? "",
            author: r.artistName ?? "",
            narrator: nil,
            series: nil,
            seriesPosition: nil,
            year: r.releaseDate.map { String($0.prefix(4)) },
            description: r.description,
            coverURL: art.flatMap(URL.init(string:))
        )
    }
}
