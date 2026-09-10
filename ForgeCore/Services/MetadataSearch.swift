import Foundation

/// Audiobook metadata lookup. Primary source is Audnexus (community Audible
/// mirror used by Audiobookshelf/Plex). iTunes Search API is the fallback
/// for non-Audible titles.
public enum MetadataSearch {
    public enum Provider: String, CaseIterable, Identifiable, Sendable {
        case audnexus
        case itunes
        case all

        public var id: String {
            rawValue
        }

        public var label: String {
            switch self {
            case .audnexus: "Audnexus"
            case .itunes: "iTunes"
            case .all: "All providers"
            }
        }
    }

    public enum SearchError: Error, LocalizedError, Equatable {
        case badResponse
        case httpStatus(Int)
        case insecureURL(URL)
        case coverTooLarge(Int)

        public var errorDescription: String? {
            switch self {
            case .badResponse: "Unexpected response from metadata server"
            case let .httpStatus(code): "Metadata server returned HTTP \(code)"
            case let .insecureURL(url): "Refusing non-HTTPS metadata URL: \(url.absoluteString)"
            case let .coverTooLarge(bytes):
                "Cover image is too large (\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)))"
            }
        }
    }

    /// Covers bigger than this are almost certainly not artwork (or are
    /// a hostile response); ImageIO would happily try to decode them.
    static let maxCoverBytes = 20 * 1024 * 1024

    /// Short per-request timeout — the shared session's 60 s default
    /// leaves the search button spinning for a minute when a provider
    /// is down. Ephemeral so nothing is persisted between launches.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// One provider's failure is an error the user should see (offline,
    /// provider down) — not an empty result list. With `.all`, a single
    /// provider failing is tolerated as long as the other answered.
    public static func search(query: String,
                              provider: Provider = .all) async throws -> [MetadataSearchResult]
    {
        let results: [MetadataSearchResult]
        switch provider {
        case .audnexus:
            results = try await audnexusSearch(query: query)
        case .itunes:
            results = try await itunesSearch(query: query)
        case .all:
            // Audnexus first in the merged list because it's the higher-
            // quality source for audiobooks specifically; Set.insert
            // preserves that priority when iTunes returns the same title.
            async let audnex = attempt { try await audnexusSearch(query: query) }
            async let itunes = attempt { try await itunesSearch(query: query) }
            let outcomes = await [audnex, itunes]
            let successes = outcomes.compactMap { try? $0.get() }
            if successes.isEmpty, case let .failure(error) = outcomes[0] {
                throw error
            }
            results = successes.flatMap(\.self)
        }
        var seen = Set<String>()
        return results.filter { seen.insert(($0.title + "|" + $0.author).lowercased()).inserted }
    }

    /// Fetch the full Audnexus record for richer description, full
    /// narrator list, and a higher-res cover URL.
    public static func enrich(_ result: MetadataSearchResult) async throws -> MetadataSearchResult {
        // The id came from the provider, not the user, but it still lands
        // in a URL path — accept only a well-formed ASIN so a hostile
        // record can't redirect us to `../authors/…`.
        guard result.source == .audnexus, isASIN(result.id) else { return result }
        let url = URL(string: "https://api.audnex.us/books/\(result.id)")!
        let data = try await fetch(url)
        let book = try JSONDecoder().decode(AudnexusBook.self, from: data)
        return result.merging(book)
    }

    public static func fetchCover(_ url: URL) async throws -> Data {
        let data = try await fetch(url)
        guard data.count <= maxCoverBytes else { throw SearchError.coverTooLarge(data.count) }
        return data
    }

    /// `Result(catching:)` for an async body. The stdlib's async overload
    /// doesn't resolve for `Result<_, any Error>` on our deployment
    /// target, so this stays even though the project is in Swift 6 mode.
    private static func attempt(
        _ body: () async throws -> [MetadataSearchResult]
    ) async -> Result<[MetadataSearchResult], Error> {
        do {
            return try await .success(body())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Transport

    /// GET `url` and return the body only for a 2xx response over HTTPS.
    /// Provider cover URLs arrive as strings from the network, so the
    /// scheme is enforced here rather than trusted.
    static func fetch(_ url: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else { throw SearchError.insecureURL(url) }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw SearchError.badResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw SearchError.httpStatus(http.statusCode)
        }
        return data
    }

    static func isASIN(_ s: String) -> Bool {
        s.count == 10 && s.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }

    /// `URLComponents` leaves `+` bare in query values, which both
    /// providers decode as a space — "C++" would search for "C  ".
    static func url(_ base: String, query: [(String, String)]) -> URL {
        var comps = URLComponents(string: base)!
        comps.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        comps.percentEncodedQuery = comps.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return comps.url!
    }

    // MARK: - Providers

    private static func audnexusSearch(query: String) async throws -> [MetadataSearchResult] {
        let url = url("https://api.audnex.us/books", query: [("name", query)])
        let data = try await fetch(url)
        let books = try JSONDecoder().decode([AudnexusBook].self, from: data)
        return books.map(MetadataSearchResult.init(audnexus:))
    }

    private static func itunesSearch(query: String) async throws -> [MetadataSearchResult] {
        let url = url("https://itunes.apple.com/search", query: [
            ("term", query),
            ("media", "audiobook"),
            ("limit", "10")
        ])
        let data = try await fetch(url)
        let envelope = try JSONDecoder().decode(ITunesEnvelope.self, from: data)
        return envelope.results.map(MetadataSearchResult.init(itunes:))
    }
}

// MARK: - Audnexus DTOs

struct AudnexusBook: Decodable {
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

extension MetadataSearchResult {
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

struct ITunesEnvelope: Decodable {
    let results: [ITunesResult]
}

struct ITunesResult: Decodable {
    let collectionId: Int?
    let collectionName: String?
    let artistName: String?
    let releaseDate: String?
    let description: String?
    let artworkUrl100: String?
}

extension MetadataSearchResult {
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
