import Foundation

struct QueryState: Equatable {
    var includeTags: Set<String> = []
    var excludeTags: Set<String> = []
    var scopeURLs: [URL] = []
}
