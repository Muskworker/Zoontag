import Foundation
import AppKit
import Combine

private let metadataUserTagsAttribute = "kMDItemUserTags"

final class MetadataSearchController: ObservableObject {
    @Published private(set) var results: [SearchResultItem] = []
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var lastError: String? = nil

    private let facetCounter = FacetCounter()

    // Exposed facets (computed from results)
    @Published private(set) var topFacets: [TagFacet] = []

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var securityScopedURLs: [URL] = []

    deinit {
        stop()
    }

    func run(state: QueryState) {
        stop()
        lastError = nil

        guard !state.scopeURLs.isEmpty else {
            results = []
            topFacets = []
            return
        }

        let scopeURLs = beginSecurityScope(for: state.scopeURLs)
        guard !scopeURLs.isEmpty else {
            lastError = "macOS denied access to the selected folder."
            return
        }

        let q = NSMetadataQuery()
        query = q

        // Build predicate (nil == match all tags)
        q.predicate = buildPredicate(include: state.includeTags, exclude: state.excludeTags)

        // We’ll access URL, filename, and tags from attributes.
        // (NSMetadataQuery returns NSMetadataItems; values are read via keys below.)
        q.notificationBatchingInterval = 0.2

        isSearching = true

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
            self?.refreshFromQuery()
            self?.isSearching = false
        })

        observers.append(nc.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { [weak self] _ in
            self?.refreshFromQuery()
        })

        let primaryScopes = scopeURLs.map { $0 as NSURL }
        if startQuery(q, scopes: primaryScopes) {
            return
        }

        if let fallbackScopes = fallbackSearchScopes(for: scopeURLs),
           startQuery(q, scopes: fallbackScopes) {
            return
        }

        stop()
        lastError = spotlightFailureMessage(for: scopeURLs)
    }

    func stop() {
        if let q = query {
            q.stop()
            query = nil
        }
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
        observers.removeAll()
        isSearching = false

        for scopedURL in securityScopedURLs {
            scopedURL.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs.removeAll()
    }

    private func refreshFromQuery() {
        guard let q = query else { return }

        // Convert query results to SearchResultItems
        let items = (q.results as? [NSMetadataItem]) ?? []

        var newResults: [SearchResultItem] = []
        newResults.reserveCapacity(min(items.count, 5000))

        // Cap for now to keep UI snappy; later we can paginate/infinite scroll.
        let cap = 5000
        for item in items.prefix(cap) {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let name = (item.value(forAttribute: kMDItemFSName as String) as? String) ?? url.lastPathComponent

            let tags = (item.value(forAttribute: metadataUserTagsAttribute) as? [String]) ?? []

            newResults.append(SearchResultItem(url: url, displayName: name, tags: tags))
        }

        results = newResults
        topFacets = facetCounter.topTags(from: newResults)
    }

    private func buildPredicate(include: Set<String>, exclude: Set<String>) -> NSPredicate? {
        var sub: [NSPredicate] = []

        for tag in include.sorted() {
            sub.append(NSPredicate(format: "%K == %@", metadataUserTagsAttribute, tag))
        }

        for tag in exclude.sorted() {
            let p = NSPredicate(format: "%K == %@", metadataUserTagsAttribute, tag)
            sub.append(NSCompoundPredicate(notPredicateWithSubpredicate: p))
        }

        // If no include/exclude tags, let Spotlight match everything in scope by
        // returning nil (NSMetadataQuery treats nil predicate as TRUEPREDICATE).
        guard !sub.isEmpty else { return nil }

        return NSCompoundPredicate(andPredicateWithSubpredicates: sub)
    }

    @discardableResult
    private func beginSecurityScope(for urls: [URL]) -> [URL] {
        var scopes: [URL] = []

        // Release any prior scope access before starting new ones.
        for scopedURL in securityScopedURLs {
            scopedURL.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs.removeAll()

        for url in urls {
            if url.startAccessingSecurityScopedResource() {
                securityScopedURLs.append(url)
            }
            scopes.append(url)
        }

        return scopes
    }

    private func startQuery(_ query: NSMetadataQuery, scopes: [Any]) -> Bool {
        guard !scopes.isEmpty else { return false }
        query.searchScopes = scopes
        return query.start()
    }

    private func spotlightFailureMessage(for scopes: [URL]) -> String {
        let desc = scopes.map(\.path).joined(separator: ", ")
        return """
        Failed to start Spotlight query for \(desc).
        Spotlight indexing may be disabled. Open System Settings ▸ Siri & Spotlight or run `mdutil -i on <path>` to re-enable indexing, then try again.
        """
    }

    private func fallbackSearchScopes(for urls: [URL]) -> [Any]? {
        var scopes: [Any] = []
        var addedFallback = false

        for url in urls {
            if url.isEntireDiskScope {
                addedFallback = true
                if !scopes.contains(where: { ($0 as? String) == NSMetadataQueryLocalComputerScope }) {
                    scopes.append(NSMetadataQueryLocalComputerScope)
                }
            } else {
                scopes.append(url.resolvingSymlinksInPath().path)
            }
        }

        return addedFallback ? scopes : nil
    }
}

private extension URL {
    var isEntireDiskScope: Bool {
        let resolvedPath = resolvingSymlinksInPath().standardizedFileURL.path
        return resolvedPath == "/" || resolvedPath == "/System/Volumes/Data"
    }
}
