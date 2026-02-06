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
        XCTAssertEqual(query, "kMDItemUserTags == 'cat\\'s*' && !(kMDItemUserTags == 'blue\\\\green*')")
    }

    func testMDFindQuerySupportsExcludeOnlyFilters() {
        let query = SpotlightTagQueryBuilder.queryString(include: [], exclude: ["untagged"])
        XCTAssertEqual(query, "!(kMDItemUserTags == 'untagged*')")
    }

    func testMDFindQueryIsNilWhenNoClauses() {
        XCTAssertNil(SpotlightTagQueryBuilder.queryString(include: [], exclude: []))
    }

    func testAutocompleteResolvedColorUsesExactMatchEvenAfterUserOverride() {
        let catalog = [
            "cat": TagAutocompleteEntry(id: "cat", displayName: "Cat", color: .red),
        ]

        let resolved = TagAutocompleteLogic.resolvedColor(for: "  cAt  ",
                                                          in: catalog,
                                                          userOverrodeColor: true)

        XCTAssertEqual(resolved, .red)
    }

    func testAutocompleteResolvedColorClearsWhenNoMatchAndNoOverride() {
        let catalog = [
            "cat": TagAutocompleteEntry(id: "cat", displayName: "Cat", color: .red),
        ]

        let resolved = TagAutocompleteLogic.resolvedColor(for: "dog",
                                                          in: catalog,
                                                          userOverrodeColor: false)

        XCTAssertEqual(resolved, FinderTagColorOption.none)
    }

    func testAutocompleteMovedHighlightedSuggestionWrapsBothDirections() {
        let suggestions = [
            TagAutocompleteEntry(id: "alpha", displayName: "Alpha", color: .none),
            TagAutocompleteEntry(id: "beta", displayName: "Beta", color: .none),
            TagAutocompleteEntry(id: "gamma", displayName: "Gamma", color: .none),
        ]

        let wrappedForward = TagAutocompleteLogic.movedHighlightedSuggestionID(in: suggestions,
                                                                               currentID: "gamma",
                                                                               delta: 1)
        XCTAssertEqual(wrappedForward, "alpha")

        let wrappedBackward = TagAutocompleteLogic.movedHighlightedSuggestionID(in: suggestions,
                                                                                currentID: "alpha",
                                                                                delta: -1)
        XCTAssertEqual(wrappedBackward, "gamma")
    }

    func testAutocompleteAcceptedSuggestionFallsBackToFirstOption() {
        let suggestions = [
            TagAutocompleteEntry(id: "alpha", displayName: "Alpha", color: .blue),
            TagAutocompleteEntry(id: "beta", displayName: "Beta", color: .green),
        ]

        let accepted = TagAutocompleteLogic.acceptedSuggestion(in: suggestions, highlightedID: nil)
        XCTAssertEqual(accepted, suggestions.first)
    }

    func testAutocompleteSuggestionsExcludeExactMatchAndSortResults() {
        let catalog = [
            "cat": TagAutocompleteEntry(id: "cat", displayName: "Cat", color: .none),
            "bobcat": TagAutocompleteEntry(id: "bobcat", displayName: "bobcat", color: .none),
            "cats": TagAutocompleteEntry(id: "cats", displayName: "Cats", color: .none),
            "dog": TagAutocompleteEntry(id: "dog", displayName: "Dog", color: .none),
        ]

        let suggestions = TagAutocompleteLogic.suggestions(for: " cat ", in: catalog, limit: 10)

        XCTAssertEqual(suggestions.map(\.id), ["bobcat", "cats"])
    }

    func testAutocompleteSuggestionsRespectLimit() {
        let catalog = [
            "tag-a": TagAutocompleteEntry(id: "tag-a", displayName: "tag-a", color: .none),
            "tag-b": TagAutocompleteEntry(id: "tag-b", displayName: "tag-b", color: .none),
            "tag-c": TagAutocompleteEntry(id: "tag-c", displayName: "tag-c", color: .none),
        ]

        let suggestions = TagAutocompleteLogic.suggestions(for: "tag", in: catalog, limit: 2)

        XCTAssertEqual(suggestions.count, 2)
        XCTAssertEqual(suggestions.map(\.id), ["tag-a", "tag-b"])
    }

    func testSelectionTagSummaryCountsDistinctItemsPerTag() {
        let baseURL = URL(fileURLWithPath: "/tmp")
        let items = [
            SearchResultItem(url: baseURL.appending(path: "a.jpg"),
                             displayName: "A",
                             tags: [FinderTag(name: "Cat"), FinderTag(name: "cat"), FinderTag(name: "Blue")]),
            SearchResultItem(url: baseURL.appending(path: "b.jpg"),
                             displayName: "B",
                             tags: [FinderTag(name: "cat"), FinderTag(name: "Green")]),
            SearchResultItem(url: baseURL.appending(path: "c.jpg"),
                             displayName: "C",
                             tags: [FinderTag(name: "blue")]),
        ]

        let summaries = SelectionTagSummaryBuilder.build(from: items)
        let counts = Dictionary(uniqueKeysWithValues: summaries.map { ($0.normalizedName, $0.count) })

        XCTAssertEqual(counts["cat"], 2)
        XCTAssertEqual(counts["blue"], 2)
        XCTAssertEqual(counts["green"], 1)
    }

    func testSelectionTagSummaryPrefersExplicitColorAndSortsByDisplayName() {
        let baseURL = URL(fileURLWithPath: "/tmp")
        let items = [
            SearchResultItem(url: baseURL.appending(path: "a.jpg"),
                             displayName: "A",
                             tags: [FinderTag(name: "zebra"), FinderTag(name: "apple", colorHex: "FF0000")]),
            SearchResultItem(url: baseURL.appending(path: "b.jpg"),
                             displayName: "B",
                             tags: [FinderTag(name: "Apple"), FinderTag(name: "zebra", colorHex: "00FF00")]),
        ]

        let summaries = SelectionTagSummaryBuilder.build(from: items)

        XCTAssertEqual(summaries.map(\.normalizedName), ["apple", "zebra"])
        XCTAssertEqual(summaries.first(where: { $0.normalizedName == "apple" })?.colorHex, "FF0000")
        XCTAssertEqual(summaries.first(where: { $0.normalizedName == "zebra" })?.colorHex, "00FF00")
    }
}
