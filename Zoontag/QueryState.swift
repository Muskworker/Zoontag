import Foundation

struct QueryState: Equatable {
    var includeTags: Set<String> = []
    var excludeTags: Set<String> = []
    /// File kinds to require. When non-empty a result must have a `fileKind` that
    /// belongs to this set (OR logic: any matching kind passes).
    var includeFileTypes: Set<String> = []
    /// File kinds to suppress. A result whose `fileKind` belongs to this set is
    /// excluded (OR logic: matching any excluded kind removes the item).
    var excludeFileTypes: Set<String> = []
    var scopeURLs: [URL] = []
    var sortOption: SearchResultSortOption = .createdNewestFirst
    /// Whether search results include files in subdirectories of the chosen scope folder.
    /// Defaults to true to preserve existing behavior.
    var includeSubdirectories: Bool = true
}
