import XCTest
@testable import Zoontag

final class ZoontagTests: XCTestCase {
    func testFacetCounterTalliesTopTags() {
        let counter = FacetCounter()
        let baseURL = URL(fileURLWithPath: "/tmp")

        let results = [
            SearchResultItem(url: baseURL.appending(path: "a.jpg"), displayName: "A", tags: [FinderTag(name: "cat"), FinderTag(name: "blue")]),
            SearchResultItem(url: baseURL.appending(path: "b.jpg"), displayName: "B", tags: [FinderTag(name: "cat", colorHex: "FF0000"), FinderTag(name: "green")]),
            SearchResultItem(url: baseURL.appending(path: "c.jpg"), displayName: "C", tags: [FinderTag(name: "blue")]),
        ]

        let facets = counter.topTags(from: results, limit: 3, sample: nil)
        XCTAssertEqual(facets.count, 3)

        let counts = Dictionary(uniqueKeysWithValues: facets.map { ($0.tag, $0.count) })
        XCTAssertEqual(counts["cat"], 2)
        XCTAssertEqual(counts["blue"], 2)
        XCTAssertEqual(counts["green"], 1)
    }

    func testSpotlightPredicateIsNilWhenNoTags() {
        XCTAssertNil(SpotlightTagQueryBuilder.predicate(include: [], exclude: []))
    }

    func testMDFindQueryEscapesValues() {
        let query = SpotlightTagQueryBuilder.queryString(include: ["cat's"], exclude: ["blue\\green"])
        XCTAssertEqual(query, "kMDItemUserTags == 'cat\\'s' && !(kMDItemUserTags == 'blue\\\\green')")
    }

    func testMDFindQueryIsNilWhenNoClauses() {
        XCTAssertNil(SpotlightTagQueryBuilder.queryString(include: [], exclude: []))
    }
}
