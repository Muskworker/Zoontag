import Foundation
import AppKit

final class MetadataSearchController: ObservableObject {
    @Published private(set) var results: [SearchResultItem] = []
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var lastError: String? = nil

    private let facetCounter = FacetCounter()

    // Exposed facets (computed from results)
    @Published private(set) var topFacets: [TagFacet] = []

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []

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

        let q = NSMetadataQuery()
        query = q

        // Restrict search to chosen folders
        q.searchScopes = state.scopeURLs

        // Build predicate
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

        // Start
        if !q.start() {
            lastError = "Failed to start Spotlight query."
            isSearching = false
        }
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

            let tags = (item.value(forAttribute: kMDItemUserTags as String) as? [String]) ?? []

            newResults.append(SearchResultItem(url: url, displayName: name, tags: tags))
        }

        results = newResults
        topFacets = facetCounter.topTags(from: newResults)
    }

    private func buildPredicate(include: Set<String>, exclude: Set<String>) -> NSPredicate {
        var sub: [NSPredicate] = []

        for tag in include.sorted() {
            sub.append(NSPredicate(format: "%K == %@", kMDItemUserTags as String, tag))
        }

        for tag in exclude.sorted() {
            let p = NSPredicate(format: "%K == %@", kMDItemUserTags as String, tag)
            sub.append(NSCompoundPredicate(notPredicateWithSubpredicate: p))
        }

        if sub.isEmpty {
            // No tag filter: show everything in scope
            return NSPredicate(value: true)
        } else {
            return NSCompoundPredicate(andPredicateWithSubpredicates: sub)
        }
    }
}
