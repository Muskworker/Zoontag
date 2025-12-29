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
        let indexingSummary = summarizeSpotlightIndexing(for: scopes)

        if indexingSummary.serverDisabled || (!indexingSummary.disabled.isEmpty && indexingSummary.enabled.isEmpty) {
            return """
            Failed to start Spotlight query for \(desc).
            Spotlight indexing appears to be disabled. Open System Settings ▸ Siri & Spotlight or run `sudo mdutil -i on /` to enable indexing, then try again.
            """
        }

        if !indexingSummary.disabled.isEmpty {
            let disabledPaths = indexingSummary.disabled.map(\.path).joined(separator: ", ")
            return """
            Failed to start Spotlight query for \(desc).
            Spotlight indexing is turned off for: \(disabledPaths).
            Enable indexing for those folders in System Settings ▸ Siri & Spotlight or via `sudo mdutil -i on <path>`, then try again.
            """
        }

        var message = """
        Failed to start Spotlight query for \(desc).
        Spotlight indexing looks enabled, so macOS likely denied Zoontag permission to read the selected folder. Re-pick it or grant Zoontag Full Disk Access (System Settings ▸ Privacy & Security ▸ Full Disk Access), then retry.
        """

        if !indexingSummary.unknown.isEmpty {
            let unknownPaths = indexingSummary.unknown.map(\.0.path).joined(separator: ", ")
            message += "\nCould not verify indexing for: \(unknownPaths)."
        }

        return message
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

    private func summarizeSpotlightIndexing(for scopes: [URL]) -> SpotlightIndexingSummary {
        var summary = SpotlightIndexingSummary()
        let uniqueScopes = Array(Set(scopes.map { $0.resolvingSymlinksInPath() }))

        for scope in uniqueScopes {
            switch checkSpotlightIndexing(at: scope) {
            case .enabled:
                summary.enabled.append(scope)
            case .disabled:
                summary.disabled.append(scope)
            case .serverDisabled:
                summary.serverDisabled = true
            case .unknown(let detail):
                summary.unknown.append((scope, detail))
            }
        }

        return summary
    }

    private func checkSpotlightIndexing(at scope: URL) -> SpotlightIndexingState {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdutil")
        task.arguments = ["-s", scope.path]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            return .unknown("mdutil failed: \(error.localizedDescription)")
        }
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return .unknown(nil)
        }

        if output.localizedCaseInsensitiveContains("Spotlight server is disabled") {
            return .serverDisabled
        }
        if output.localizedCaseInsensitiveContains("Indexing disabled") {
            return .disabled
        }
        if output.localizedCaseInsensitiveContains("Indexing enabled") {
            return .enabled
        }

        return .unknown(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private extension URL {
    var isEntireDiskScope: Bool {
        let resolvedPath = resolvingSymlinksInPath().standardizedFileURL.path
        return resolvedPath == "/" || resolvedPath == "/System/Volumes/Data"
    }
}

private struct SpotlightIndexingSummary {
    var enabled: [URL] = []
    var disabled: [URL] = []
    var unknown: [(URL, String?)] = []
    var serverDisabled: Bool = false
}

private enum SpotlightIndexingState {
    case enabled
    case disabled
    case serverDisabled
    case unknown(String?)
}
