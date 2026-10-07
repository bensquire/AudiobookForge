import XCTest
@testable import ForgeCore

/// Pins the mapping from each provider's JSON shape to
/// `MetadataSearchResult`, using trimmed captures of real responses.
/// A provider renaming a field would otherwise surface as blank rows
/// in the UI with no test going red.
final class MetadataDTOTests: XCTestCase {
    // MARK: - Audnexus

    private let audnexusJSON = Data("""
    [{
      "asin": "B08G9PRS1K",
      "title": "Project Hail Mary",
      "authors": [{"asin": "B00G0WYW92", "name": "Andy Weir"}],
      "narrators": [{"name": "Ray Porter"}],
      "seriesPrimary": {"asin": "B0DZ", "name": "Standalone Reads", "position": "1"},
      "releaseDate": "2021-05-04T00:00:00.000Z",
      "image": "https://m.media-amazon.com/images/I/91vS2L5YfEL.jpg",
      "summary": "A lone astronaut must save the earth.",
      "description": "Long-form description."
    }]
    """.utf8)

    func test_audnexus_mapsSearchRecord() throws {
        // Arrange — the trimmed capture in `audnexusJSON`.

        // Act
        let books = try JSONDecoder().decode([AudnexusBook].self, from: audnexusJSON)
        let result = try MetadataSearchResult(audnexus: XCTUnwrap(
            books.first,
            "the JSON decoded to no books"
        ))

        // Assert
        XCTAssertEqual(result.id, "B08G9PRS1K")
        XCTAssertEqual(result.source, .audnexus)
        XCTAssertEqual(result.title, "Project Hail Mary")
        XCTAssertEqual(result.author, "Andy Weir")
        XCTAssertEqual(result.narrator, "Ray Porter")
        XCTAssertEqual(result.series, "Standalone Reads")
        XCTAssertEqual(result.seriesPosition, "1")
        XCTAssertEqual(result.year, "2021")
        XCTAssertEqual(result.description, "A lone astronaut must save the earth.")
        XCTAssertEqual(result.coverURL?.host, "m.media-amazon.com")
    }

    func test_audnexus_toleratesMissingOptionalFields() throws {
        // Arrange — the minimum a record can carry.
        let json = Data(#"[{"asin": "B000000000", "title": "Bare"}]"#.utf8)

        // Act
        let books = try JSONDecoder().decode([AudnexusBook].self, from: json)
        let result = try MetadataSearchResult(audnexus: XCTUnwrap(
            books.first,
            "the JSON decoded to no books"
        ))

        // Assert
        XCTAssertEqual(result.author, "")
        XCTAssertNil(result.narrator)
        XCTAssertNil(result.series)
        XCTAssertNil(result.year)
        XCTAssertNil(result.coverURL)
    }

    func test_audnexus_multipleAuthorsAreJoined() throws {
        // Arrange
        let json = Data(#"[{"asin": "B000000000", "title": "T", "authors": [{"name": "A"}, {"name": "B"}]}]"#
            .utf8)

        // Act
        let books = try JSONDecoder().decode([AudnexusBook].self, from: json)
        let result = try MetadataSearchResult(audnexus: XCTUnwrap(
            books.first,
            "the JSON decoded to no books"
        ))

        // Assert
        XCTAssertEqual(result.author, "A, B")
    }

    func test_audnexus_mergingPrefersRicherEnrichedFields() throws {
        // Arrange — search hit without narrator/series; enrich record has both.
        let searchHit = MetadataSearchResult(
            id: "B08G9PRS1K", source: .audnexus, title: "T", author: "A", narrator: nil,
            series: nil, seriesPosition: nil, year: "2021", description: nil, coverURL: nil
        )
        let books = try JSONDecoder().decode([AudnexusBook].self, from: audnexusJSON)

        // Act
        let merged = try searchHit.merging(XCTUnwrap(books.first, "the JSON decoded to no books"))

        // Assert — existing non-nil fields are kept, gaps are filled.
        XCTAssertEqual(merged.author, "A")
        XCTAssertEqual(merged.narrator, "Ray Porter")
        XCTAssertEqual(merged.series, "Standalone Reads")
        XCTAssertEqual(merged.year, "2021")
        XCTAssertNotNil(merged.coverURL)
    }

    // MARK: - iTunes

    func test_itunes_mapsEnvelopeAndUpsizesArtwork() throws {
        // Arrange
        let json = Data("""
        {"resultCount": 1, "results": [{
          "wrapperType": "audiobook",
          "collectionId": 1552184040,
          "collectionName": "Project Hail Mary (Unabridged)",
          "artistName": "Andy Weir",
          "releaseDate": "2021-05-04T07:00:00Z",
          "description": "<p>Ryland Grace is the sole survivor</p>",
          "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/x/100x100bb.jpg"
        }]}
        """.utf8)

        // Act
        let envelope = try JSONDecoder().decode(ITunesEnvelope.self, from: json)
        let result = try MetadataSearchResult(itunes: XCTUnwrap(
            envelope.results.first,
            "the JSON decoded to no results"
        ))

        // Assert
        XCTAssertEqual(result.id, "1552184040")
        XCTAssertEqual(result.source, .itunes)
        XCTAssertEqual(result.title, "Project Hail Mary (Unabridged)")
        XCTAssertEqual(result.author, "Andy Weir")
        XCTAssertEqual(result.year, "2021")
        XCTAssertEqual(result.coverURL?.lastPathComponent, "600x600bb.jpg")
        XCTAssertNil(result.narrator)
    }

    func test_itunes_missingCollectionIdGetsAFallbackId() throws {
        // Arrange
        let json = Data(#"{"results": [{"collectionName": "X"}]}"#.utf8)

        // Act
        let envelope = try JSONDecoder().decode(ITunesEnvelope.self, from: json)
        let result = try MetadataSearchResult(itunes: XCTUnwrap(
            envelope.results.first,
            "the JSON decoded to no results"
        ))

        // Assert
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.author, "")
    }
}
