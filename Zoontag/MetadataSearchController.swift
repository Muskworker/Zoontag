import Foundation
import AppKit
import Combine
import CoreServices
import Darwin

final class MetadataSearchController: ObservableObject {
    @Published private(set) var results: [SearchResultItem] = []
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var lastError: String? = nil

    private let facetCounter = FacetCounter()
    private let resultLimit = 5000
    private let enableMetadataQuery = false

    // Exposed facets (computed from results)
    @Published private(set) var topFacets: [TagFacet] = []

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var securityScopedURLs: [URL] = []
    private var currentRunToken = UUID()
    private let fallbackQueue = DispatchQueue(label: "MetadataSearchController.mdfind", qos: .userInitiated)
    private var mdfindTask: Process?

    deinit {
        stop()
    }

    func run(state: QueryState) {
        let runToken = UUID()
        currentRunToken = runToken

        stop()
        lastError = nil

        let hasTagFilters = !state.includeTags.isEmpty || !state.excludeTags.isEmpty

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

        if enableMetadataQuery {
            let q = NSMetadataQuery()
            query = q

            // Build predicate (nil == match all tags)
            q.predicate = SpotlightTagQueryBuilder.predicate(include: state.includeTags, exclude: state.excludeTags)

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

            stop(releaseSecurityScopedResources: false)
        } else {
            stop(releaseSecurityScopedResources: false)
        }

        if hasTagFilters {
            if runMDFind(scopeURLs: scopeURLs,
                         include: state.includeTags,
                         exclude: state.excludeTags,
                         runToken: runToken) {
                return
            }
        } else if enumerateScopeContents(scopeURLs: scopeURLs, runToken: runToken) {
            return
        }

        stop()
        lastError = spotlightFailureMessage(for: scopeURLs)
    }

    func stop(releaseSecurityScopedResources: Bool = true) {
        if let q = query {
            q.stop()
            query = nil
        }
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
        observers.removeAll()
        isSearching = false

        fallbackQueue.async { [weak self] in
            guard let self else { return }
            self.mdfindTask?.terminate()
            self.mdfindTask = nil
        }

        if releaseSecurityScopedResources {
            for scopedURL in securityScopedURLs {
                scopedURL.stopAccessingSecurityScopedResource()
            }
            securityScopedURLs.removeAll()
        }
    }

    private func runMDFind(scopeURLs: [URL],
                           include: Set<String>,
                           exclude: Set<String>,
                           runToken: UUID) -> Bool {
        guard !scopeURLs.isEmpty else { return false }

        guard let arguments = buildMDFindArguments(scopeURLs: scopeURLs, include: include, exclude: exclude) else {
            return false
        }
        guard !arguments.isEmpty else { return false }

        isSearching = true

        fallbackQueue.async { [weak self] in
            guard let self else { return }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            task.arguments = arguments

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            self.mdfindTask = task

            do {
                try task.run()
            } catch {
                self.mdfindTask = nil
                self.handleMDFindFailure("Failed to run mdfind: \(error.localizedDescription)", runToken: runToken)
                return
            }

            task.waitUntilExit()
            self.mdfindTask = nil

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)

            guard task.terminationStatus == 0 else {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = trimmed.isEmpty ? "" : " Details: \(trimmed)"
                self.handleMDFindFailure("mdfind exited with code \(task.terminationStatus).\(detail)", runToken: runToken)
                return
            }

            let lines = output.split(whereSeparator: \.isNewline)
            var items: [SearchResultItem] = []
            items.reserveCapacity(min(lines.count, self.resultLimit))

            for line in lines {
                if items.count >= self.resultLimit {
                    break
                }
                let path = String(line)
                guard !path.isEmpty else { continue }
                let url = URL(fileURLWithPath: path)
                let resourceValues = try? url.resourceValues(forKeys: [.localizedNameKey, .tagNamesKey])
                let name = resourceValues?.localizedName ?? url.lastPathComponent
                let tags = normalizedTags(primaryTags: nil, fallbackTags: resourceValues?.tagNames, url: url)
                items.append(SearchResultItem(url: url, displayName: name, tags: tags))
            }

            DispatchQueue.main.async {
                guard self.currentRunToken == runToken else { return }
                self.results = items
                self.topFacets = self.facetCounter.topTags(from: items)
                self.isSearching = false
                self.lastError = nil
            }
        }

        return true
    }

    private func handleMDFindFailure(_ message: String, runToken: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentRunToken == runToken else { return }
            self.results = []
            self.topFacets = []
            self.isSearching = false
            self.lastError = message
        }
    }

    private func buildMDFindArguments(scopeURLs: [URL],
                                      include: Set<String>,
                                      exclude: Set<String>) -> [String]? {
        guard !scopeURLs.isEmpty else { return nil }
        guard let query = SpotlightTagQueryBuilder.queryString(include: include, exclude: exclude) else {
            return nil
        }

        var args: [String] = []
        for url in scopeURLs {
            args.append(contentsOf: ["-onlyin", url.path])
        }

        args.append(query)
        return args
    }

    private func enumerateScopeContents(scopeURLs: [URL], runToken: UUID) -> Bool {
        guard !scopeURLs.isEmpty else { return false }

        isSearching = true
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .localizedNameKey, .tagNamesKey]
        let fm = FileManager.default

        fallbackQueue.async { [weak self] in
            guard let self else { return }

            var collected: [SearchResultItem] = []
            collected.reserveCapacity(self.resultLimit)

            scopeLoop: for scope in scopeURLs {
                if collected.count >= self.resultLimit { break }

                let scopeValues = try? scope.resourceValues(forKeys: resourceKeys)
                if scopeValues?.isRegularFile == true {
                    let name = scopeValues?.localizedName ?? scope.lastPathComponent
                    let tags = self.normalizedTags(primaryTags: nil, fallbackTags: scopeValues?.tagNames, url: scope)
                    collected.append(SearchResultItem(url: scope, displayName: name, tags: tags))
                    continue
                }

                guard scopeValues?.isDirectory ?? true,
                      let enumerator = fm.enumerator(at: scope,
                                                     includingPropertiesForKeys: Array(resourceKeys),
                                                     options: [.skipsHiddenFiles],
                                                     errorHandler: nil) else {
                    continue
                }

                for case let fileURL as URL in enumerator {
                    if collected.count >= self.resultLimit {
                        break scopeLoop
                    }

                    let values = try? fileURL.resourceValues(forKeys: resourceKeys)

                    if values?.isDirectory == true {
                        continue
                    }

                    let name = values?.localizedName ?? fileURL.lastPathComponent
                    let tags = self.normalizedTags(primaryTags: nil, fallbackTags: values?.tagNames, url: fileURL)
                    collected.append(SearchResultItem(url: fileURL, displayName: name, tags: tags))
                }
            }

            DispatchQueue.main.async {
                guard self.currentRunToken == runToken else { return }
                self.results = collected
                self.topFacets = self.facetCounter.topTags(from: collected)
                self.isSearching = false
                self.lastError = nil
            }
        }

        return true
    }

    private func normalizedTags(primaryTags: [String]?, fallbackTags: [String]? = nil, url: URL) -> [FinderTag] {
        if let tags = primaryTags,
           let parsed = parseFinderTags(from: tags) {
            return parsed
        }

        if let mdTags = finderMetadataTags(for: url),
           let parsed = parseFinderTags(from: mdTags) {
            return parsed
        }

        if let fallback = fallbackTags,
           let parsed = parseFinderTags(from: fallback) {
            return parsed
        }

        if fallbackTags == nil,
           let resourceValues = try? url.resourceValues(forKeys: [.tagNamesKey]),
           let tagNames = resourceValues.tagNames,
           let parsed = parseFinderTags(from: tagNames) {
            return parsed
        }

        return []
    }

    private func parseFinderTags(from rawValues: [String]) -> [FinderTag]? {
        let parsed = rawValues.compactMap(FinderTag.init(rawValue:))
        return parsed.isEmpty ? nil : parsed
    }

    private func finderMetadataTags(for url: URL) -> [String]? {
        if let mdTags = mdItemTags(for: url) {
            if mdTags.contains(where: { $0.contains("\n") }) {
                return mdTags
            }

            if let xattrTags = extendedAttributeTags(for: url) {
                return xattrTags
            }

            return mdTags
        }

        if let xattrTags = extendedAttributeTags(for: url) {
            return xattrTags
        }

        return nil
    }

    private func mdItemTags(for url: URL) -> [String]? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else {
            return nil
        }
        let attribute = SpotlightTagQueryBuilder.metadataUserTagsAttribute as CFString
        guard let values = MDItemCopyAttribute(item, attribute) as? [String], !values.isEmpty else {
            return nil
        }
        return values
    }

    private func extendedAttributeTags(for url: URL) -> [String]? {
        let attrName = "com.apple.metadata:_kMDItemUserTags"
        return url.withUnsafeFileSystemRepresentation { fileSystemPath in
            guard let path = fileSystemPath else { return nil }

            let size = getxattr(path, attrName, nil, 0, 0, 0)
            guard size > 0 else { return nil }

            var data = Data(count: Int(size))
            let readResult: Int = data.withUnsafeMutableBytes { rawBufferPointer in
                guard let baseAddress = rawBufferPointer.baseAddress else { return -1 }
                return getxattr(path, attrName, baseAddress, Int(size), 0, 0)
            }

            guard readResult >= 0 else { return nil }

            guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let tags = plist as? [String],
                  !tags.isEmpty else {
                return nil
            }

            return tags
        }
    }

    private func refreshFromQuery() {
        guard let q = query else { return }

        // Convert query results to SearchResultItems
        let items = (q.results as? [NSMetadataItem]) ?? []

        var newResults: [SearchResultItem] = []
        newResults.reserveCapacity(min(items.count, resultLimit))

        // Cap for now to keep UI snappy; later we can paginate/infinite scroll.
        for item in items.prefix(resultLimit) {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let name = (item.value(forAttribute: kMDItemFSName as String) as? String) ?? url.lastPathComponent

            let metadataTags = item.value(forAttribute: SpotlightTagQueryBuilder.metadataUserTagsAttribute) as? [String]
            let tags = normalizedTags(primaryTags: metadataTags, fallbackTags: nil, url: url)

            newResults.append(SearchResultItem(url: url, displayName: name, tags: tags))
        }

        results = newResults
        topFacets = facetCounter.topTags(from: newResults)
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

enum SpotlightTagQueryBuilder {
    static let metadataUserTagsAttribute = "kMDItemUserTags"

    static func predicate(include: Set<String>, exclude: Set<String>) -> NSPredicate? {
        var predicates: [NSPredicate] = []

        for tag in include.sorted() {
            predicates.append(NSPredicate(format: "%K == %@", metadataUserTagsAttribute, tag))
        }

        for tag in exclude.sorted() {
            let predicate = NSPredicate(format: "%K == %@", metadataUserTagsAttribute, tag)
            predicates.append(NSCompoundPredicate(notPredicateWithSubpredicate: predicate))
        }

        guard !predicates.isEmpty else { return nil }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    static func queryString(include: Set<String>, exclude: Set<String>) -> String? {
        var clauses: [String] = []

        for tag in include.sorted() {
            clauses.append("\(metadataUserTagsAttribute) == '\(escape(tag))'")
        }

        for tag in exclude.sorted() {
            clauses.append("!(\(metadataUserTagsAttribute) == '\(escape(tag))')")
        }

        guard !clauses.isEmpty else { return nil }
        return clauses.joined(separator: " && ")
    }

    private static func escape(_ tag: String) -> String {
        var escaped = tag.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "'", with: "\\'")
        return escaped
    }
}
