import XCTest
@testable import ForgeCore

/// Pure helpers behind the metadata lookup. The network calls themselves
/// are not exercised here; these pin the input validation and URL
/// construction that keep provider-supplied strings from steering them.
final class MetadataSearchTests: XCTestCase {
    // MARK: - ASIN validation

    func test_isASIN_acceptsTenUppercaseAlphanumerics() {
        XCTAssertTrue(MetadataSearch.isASIN("B08G9PRS1K"))
        XCTAssertTrue(MetadataSearch.isASIN("0000000000"))
    }

    func test_isASIN_rejectsPathTraversalLowercaseAndWrongLength() {
        XCTAssertFalse(MetadataSearch.isASIN("../authors"))
        XCTAssertFalse(MetadataSearch.isASIN("b08g9prs1k"))
        XCTAssertFalse(MetadataSearch.isASIN("B08G9PRS1"))
        XCTAssertFalse(MetadataSearch.isASIN("B08G9PRS1K/"))
        XCTAssertFalse(MetadataSearch.isASIN(""))
    }

    // MARK: - query URL construction

    func test_url_percentEncodesPlusSoProvidersDoNotReadItAsSpace() {
        // Arrange / Act
        let url = MetadataSearch.url("https://example.test/search", query: [("term", "C++ for kids")])

        // Assert
        XCTAssertEqual(url.query, "term=C%2B%2B%20for%20kids")
    }

    func test_url_keepsMultipleItemsInOrder() {
        let url = MetadataSearch.url("https://example.test/s", query: [("a", "1"), ("b", "x y")])
        XCTAssertEqual(url.absoluteString, "https://example.test/s?a=1&b=x%20y")
    }

    // MARK: - transport guards

    func test_fetch_refusesNonHTTPSURLBeforeTouchingTheNetwork() async throws {
        // Arrange — a provider-supplied cover URL with a plain scheme.
        let url = try XCTUnwrap(URL(string: "http://example.test/cover.jpg"))

        // Act / Assert
        do {
            _ = try await MetadataSearch.fetch(url)
            XCTFail("expected insecureURL")
        } catch let error as MetadataSearch.SearchError {
            XCTAssertEqual(error, .insecureURL(url))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func test_enrich_returnsNonAudnexusResultUntouchedWithoutNetwork() async throws {
        // Arrange — iTunes results have nothing to enrich from.
        let result = MetadataSearchResult(
            id: "123", source: .itunes, title: "T", author: "A", narrator: nil,
            series: nil, seriesPosition: nil, year: nil, description: nil, coverURL: nil
        )

        // Act
        let enriched = try await MetadataSearch.enrich(result)

        // Assert
        XCTAssertEqual(enriched, result)
    }

    func test_enrich_skipsMalformedAudnexusIDWithoutNetwork() async throws {
        // Arrange — a hostile id that would otherwise be spliced into
        // the request path.
        let result = MetadataSearchResult(
            id: "../authors/x", source: .audnexus, title: "T", author: "A", narrator: nil,
            series: nil, seriesPosition: nil, year: nil, description: nil, coverURL: nil
        )

        // Act
        let enriched = try await MetadataSearch.enrich(result)

        // Assert
        XCTAssertEqual(enriched, result)
    }
}
