import Foundation

struct BookMetadata: Equatable {
    var title: String = ""
    var subtitle: String = ""
    var author: String = ""
    var narrator: String = ""
    var series: String = ""
    var seriesPosition: String = ""
    var year: String = ""
    var description: String = ""
    var genre: String = ""
    var coverData: Data? = nil
    var coverSourceURL: URL? = nil

    var isEmpty: Bool {
        title.isEmpty && author.isEmpty && narrator.isEmpty
    }

    /// What the queue needs to identify and label a book. Whitespace-only
    /// values don't count.
    var hasRequiredFields: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
        && !author.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

enum MetadataSource: String, Hashable {
    case audnexus
    case itunes

    var label: String {
        switch self {
        case .audnexus: return "Audnexus"
        case .itunes:   return "iTunes"
        }
    }
}

struct MetadataSearchResult: Identifiable, Hashable {
    let id: String                 // ASIN or other provider key
    let source: MetadataSource
    let title: String
    let author: String
    let narrator: String?
    let series: String?
    let seriesPosition: String?
    let year: String?
    let description: String?
    let coverURL: URL?
}
