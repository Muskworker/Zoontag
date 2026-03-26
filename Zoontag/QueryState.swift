import Foundation

struct QueryState: Equatable {
    var includeTags: Set<String> = []
    var excludeTags: Set<String> = []
    var scopeURLs: [URL] = []
    var sortOption: SearchResultSortOption = .createdNewestFirst
    /// Whether search results include files in subdirectories of the chosen scope folder.
    /// Defaults to true to preserve existing behavior.
    var includeSubdirectories: Bool = true
}
