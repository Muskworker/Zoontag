import XCTest
@testable import Zoontag

final class ZoontagTests: XCTestCase {
    func testFinderTagRawValueParsesNameAndColorIndex() {
        let parsed = FinderTag(rawValue: "Work\n6")

        XCTAssertEqual(parsed?.name, "Work")
        XCTAssertEqual(parsed?.colorHex, "FF453A")
    }

    func testNewlineDelimitedPathParserDefersTrailingPartialLineUntilFlush() {
        var buffer = Data("/tmp/alpha".utf8)

        let withoutFlush = NewlineDelimitedPathParser.consumeAvailableLines(from: &buffer, flush: false)

        XCTAssertTrue(withoutFlush.isEmpty)
        XCTAssertEqual(String(decoding: buffer, as: UTF8.self), "/tmp/alpha")

        let withFlush = NewlineDelimitedPathParser.consumeAvailableLines(from: &buffer, flush: true)

        XCTAssertEqual(withFlush, ["/tmp/alpha"])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testNewlineDelimitedPathParserConsumesOnlyCompleteLinesWithoutFlush() {
        var buffer = Data("/tmp/alpha\n/tmp/bravo".utf8)

        let lines = NewlineDelimitedPathParser.consumeAvailableLines(from: &buffer, flush: false)

        XCTAssertEqual(lines, ["/tmp/alpha"])
        XCTAssertEqual(String(decoding: buffer, as: UTF8.self), "/tmp/bravo")
    }

    func testNewlineDelimitedPathParserRoundTripsUTF8AcrossChunks() {
        var buffer = Data()
        buffer.append(Data("/tmp/cafe".utf8))
        _ = NewlineDelimitedPathParser.consumeAvailableLines(from: &buffer, flush: false)
        buffer.append(Data("\u{301}.txt\n".utf8))

        let lines = NewlineDelimitedPathParser.consumeAvailableLines(from: &buffer, flush: false)

        XCTAssertEqual(lines, ["/tmp/cafe\u{301}.txt"])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testNewlineDelimitedPathParserFlushAfterPartialDrain() {
        var buffer = Data("/tmp/alpha\n/tmp/bravo".utf8)

        let first = NewlineDelimitedPathParser.consumeAvailableLines(from: &buffer, flush: false)
        let second = NewlineDelimitedPathParser.consumeAvailableLines(from: &buffer, flush: true)

        XCTAssertEqual(first, ["/tmp/alpha"])
        XCTAssertEqual(second, ["/tmp/bravo"])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testSearchResultsCoverageShowsKnownTotalWhenComplete() {
        let coverage = SearchResultsCoverage(visibleCount: 42, totalCount: 42, hasMoreResults: false)

        XCTAssertEqual(coverage.resultCountText, "Results: 42")
        XCTAssertNil(coverage.statusText)
    }

    func testSearchResultsCoverageShowsKnownTotalWhenTruncated() {
        let coverage = SearchResultsCoverage(visibleCount: 5000, totalCount: 7321, hasMoreResults: true)

        XCTAssertEqual(coverage.resultCountText, "Results: 5000 of 7321")
        XCTAssertEqual(coverage.statusText, "Showing first 5000 of 7321 results.")
    }

    func testSearchResultsCoverageShowsUnknownTotalWhenTruncated() {
        let coverage = SearchResultsCoverage(visibleCount: 5000, totalCount: nil, hasMoreResults: true)

        XCTAssertEqual(coverage.resultCountText, "Results: 5000+")
        XCTAssertEqual(coverage.statusText, "Showing first 5000 results. Load more to continue.")
    }

    func testSearchResultPaginatorUsesSortedOrderBeforeLimit() {
        let baseURL = URL(fileURLWithPath: "/tmp")
        let items = [
            SearchResultItem(url: baseURL.appending(path: "2.txt"), displayName: "Bravo", tags: []),
            SearchResultItem(url: baseURL.appending(path: "4.txt"), displayName: "Delta", tags: []),
            SearchResultItem(url: baseURL.appending(path: "1.txt"), displayName: "Alpha", tags: []),
            SearchResultItem(url: baseURL.appending(path: "3.txt"), displayName: "Charlie", tags: []),
        ]

        let page = SearchResultPaginator.page(items, sortOption: .nameAscending, limit: 2)

        XCTAssertEqual(page.totalCount, 4)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.visible.map(\.displayName), ["Alpha", "Bravo"])
    }

    func testSearchResultPaginatorNextPagePrefixRemainsStable() {
        let baseURL = URL(fileURLWithPath: "/tmp")
        let items = [
            SearchResultItem(url: baseURL.appending(path: "2.txt"), displayName: "Bravo", tags: []),
            SearchResultItem(url: baseURL.appending(path: "4.txt"), displayName: "Delta", tags: []),
            SearchResultItem(url: baseURL.appending(path: "1.txt"), displayName: "Alpha", tags: []),
            SearchResultItem(url: baseURL.appending(path: "3.txt"), displayName: "Charlie", tags: []),
        ]

        let firstPage = SearchResultPaginator.page(items, sortOption: .nameAscending, limit: 2).visible
        let secondPage = SearchResultPaginator.page(items, sortOption: .nameAscending, limit: 3).visible

        XCTAssertEqual(Array(secondPage.prefix(firstPage.count)).map(\.id), firstPage.map(\.id))
    }

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

    func testSearchResultSortOptionOrdersNamesAscendingAndDescending() {
        let baseURL = URL(fileURLWithPath: "/tmp")
        let items = [
            SearchResultItem(url: baseURL.appending(path: "z.mov"), displayName: "Zulu", tags: []),
            SearchResultItem(url: baseURL.appending(path: "b.mov"), displayName: "beta", tags: []),
            SearchResultItem(url: baseURL.appending(path: "a.mov"), displayName: "Alpha", tags: []),
        ]

        let ascending = SearchResultSortOption.nameAscending.sorted(items)
        XCTAssertEqual(ascending.map(\.displayName), ["Alpha", "beta", "Zulu"])

        let descending = SearchResultSortOption.nameDescending.sorted(items)
        XCTAssertEqual(descending.map(\.displayName), ["Zulu", "beta", "Alpha"])
    }

    func testSearchResultSortOptionOrdersModifiedDateNewestFirstWithNilLast() {
        let baseURL = URL(fileURLWithPath: "/tmp")
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDate = Date(timeIntervalSince1970: 1_800_000_000)

        let items = [
            SearchResultItem(url: baseURL.appending(path: "missing.txt"),
                             displayName: "Missing",
                             tags: [],
                             contentModificationDate: nil),
            SearchResultItem(url: baseURL.appending(path: "old.txt"),
                             displayName: "Old",
                             tags: [],
                             contentModificationDate: oldDate),
            SearchResultItem(url: baseURL.appending(path: "new.txt"),
                             displayName: "New",
                             tags: [],
                             contentModificationDate: newDate),
        ]

        let sorted = SearchResultSortOption.modifiedNewestFirst.sorted(items)
        XCTAssertEqual(sorted.map(\.displayName), ["New", "Old", "Missing"])
    }

    func testSearchResultSortOptionOrdersSizeSmallestFirstWithNilLast() {
        let baseURL = URL(fileURLWithPath: "/tmp")
        let items = [
            SearchResultItem(url: baseURL.appending(path: "unknown.bin"),
                             displayName: "Unknown",
                             tags: [],
                             fileSizeBytes: nil),
            SearchResultItem(url: baseURL.appending(path: "large.bin"),
                             displayName: "Large",
                             tags: [],
                             fileSizeBytes: 2_000),
            SearchResultItem(url: baseURL.appending(path: "small.bin"),
                             displayName: "Small",
                             tags: [],
                             fileSizeBytes: 120),
        ]

        let sorted = SearchResultSortOption.sizeSmallestFirst.sorted(items)
        XCTAssertEqual(sorted.map(\.displayName), ["Small", "Large", "Unknown"])
    }
}
