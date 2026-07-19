import Foundation

public struct BookMetadata: Equatable {
    public var title: String = ""
    public var subtitle: String = ""
    public var author: String = ""
    public var narrator: String = ""
    public var series: String = ""
    public var seriesPosition: String = ""
    public var year: String = ""
    public var description: String = ""
    public var genre: String = ""
    public var coverData: Data?
    public var coverSourceURL: URL?

    public var isEmpty: Bool {
        title.isEmpty && author.isEmpty && narrator.isEmpty
    }

    /// What the queue needs to identify and label a book. Whitespace-only
    /// values don't count.
    public var hasRequiredFields: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !author.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

public enum MetadataSource: String, Hashable {
    case audnexus
    case itunes

    public var label: String {
        switch self {
        case .audnexus: "Audnexus"
        case .itunes: "iTunes"
        }
    }
}

public struct MetadataSearchResult: Identifiable, Hashable, Sendable {
    public let id: String // ASIN or other provider key
    public let source: MetadataSource
    public let title: String
    public let author: String
    public let narrator: String?
    public let series: String?
    public let seriesPosition: String?
    public let year: String?
    public let description: String?
    public let coverURL: URL?
}
