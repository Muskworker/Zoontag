import Combine
import CoreServices
import Darwin
import Foundation

final class MetadataSearchController: ObservableObject {
    @Published private(set) var results: [SearchResultItem] = []
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var lastError: String? = nil
    @Published private(set) var knownTotalResults: Int? = nil
    @Published private(set) var hasMoreResults: Bool = false
    @Published private(set) var resultsSortOption: SearchResultSortOption = .createdNewestFirst
    @Published private(set) var isRefiningResults: Bool = false
    /// Root cause: result-derived suggestions shrink as filters narrow the live result set, so
    /// query autocomplete needs its own scope-wide catalog that stays independent of the current run.
    @Published private(set) var scopeTagCatalog: [String: TagAutocompleteEntry] = [:]

    private let facetCounter = FacetCounter()
    private let pageSize = 5000
    private var currentResultLimit = 5000
    private let enableMetadataQuery = false

    /// Exposed facets (computed from results)
    @Published private(set) var topFacets: [TagFacet] = []

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var securityScopedURLs: [URL] = []
    private var currentRunToken = UUID()
    private var lastRunState: QueryState?
    private var cachedSearchKey: SearchCacheKey?
    private var cachedSortableResults: [SearchResultItem] = []
    private let fallbackQueue = DispatchQueue(label: "MetadataSearchController.mdfind", qos: .userInitiated)
    private let tagIndexQueue = DispatchQueue(label: "MetadataSearchController.tagIndex", qos: .utility)
    private let mdfindTaskLock = NSLock()
    private var mdfindTask: Process?
    private var currentScopeTagIndexToken = UUID()
    private var cachedScopeTagIndexKey: ScopeTagIndexKey?
    private var scopeTagCatalogNeedsRefresh = true
    private let isSandboxed: Bool = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    private lazy var metadataBackend = MetadataQueryBackend(controller: self)
    private lazy var mdfindBackend = MDFindBackend(controller: self)
    private lazy var enumerationBackend = EnumerationBackend(controller: self)

    private enum SearchStrategy {
        case metadataQuery
        case mdfind
        case enumerate
    }

    private struct SearchCacheKey: Equatable {
        let includeTags: Set<String>
        let excludeTags: Set<String>
        let scopePaths: [String]
        let includeSubdirectories: Bool
    }

    private struct ScopeTagIndexKey: Equatable {
        let scopePaths: [String]
        let includeSubdirectories: Bool
    }

    deinit {
        stop()
    }

    func run(state: QueryState) {
        executeRun(state: state, resetPagination: true)
    }

    func loadMoreResults() {
        guard hasMoreResults, let state = lastRunState else { return }
        currentResultLimit += pageSize
        executeRun(state: state, resetPagination: false)
    }

    func invalidateScopeTagCatalog() {
        scopeTagCatalogNeedsRefresh = true
    }

    /// Clears the cached search results so the next `run(state:)` performs a
    /// fresh fetch rather than serving the stale cache.  Call this whenever
    /// file metadata changes externally (e.g. after a tag edit).
    func invalidateResultsCache() {
        clearCachedSortableResults()
    }

    private func executeRun(state: QueryState, resetPagination: Bool) {
        if resetPagination {
            currentResultLimit = pageSize
        }
        lastRunState = state

        let runToken = UUID()
        currentRunToken = runToken

        stop()
        lastError = nil

        let hasTagFilters = !state.includeTags.isEmpty || !state.excludeTags.isEmpty

        guard !state.scopeURLs.isEmpty else {
            clearScopeTagCatalog()
            clearResultsAndCoverage(sortOption: state.sortOption)
            return
        }

        let scopeURLs = beginSecurityScope(for: state.scopeURLs)
        guard !scopeURLs.isEmpty else {
            clearScopeTagCatalog()
            clearResultsAndCoverage(sortOption: state.sortOption)
            lastError = "macOS denied access to the selected folder."
            return
        }

        refreshScopeTagCatalogIfNeeded(for: state)

        let cacheKey = makeCacheKey(for: state)
        if cachedSearchKey != cacheKey {
            clearCachedSortableResults()
        } else if serveCachedResultsIfAvailable(state: state, runToken: runToken) {
            return
        }

        let strategyList = strategies(hasTagFilters: hasTagFilters)
        for strategy in strategyList {
            if execute(strategy,
                       state: state,
                       scopeURLs: scopeURLs,
                       runToken: runToken)
            {
                return
            }
        }

        stop()
        clearResultsAndCoverage(sortOption: state.sortOption)
        lastError = SpotlightDiagnostics.failureMessage(for: scopeURLs)
    }

    private func strategies(hasTagFilters: Bool) -> [SearchStrategy] {
        var list: [SearchStrategy] = []
        if enableMetadataQuery {
            list.append(.metadataQuery)
        }
        list.append(hasTagFilters ? .mdfind : .enumerate)
        return list
    }

    private func execute(_ strategy: SearchStrategy,
                         state: QueryState,
                         scopeURLs: [URL],
                         runToken: UUID) -> Bool
    {
        switch strategy {
        case .metadataQuery:
            metadataBackend.start(state: state, scopeURLs: scopeURLs, runToken: runToken)
        case .mdfind:
            mdfindBackend.start(state: state, scopeURLs: scopeURLs, runToken: runToken)
        case .enumerate:
            enumerationBackend.start(state: state, scopeURLs: scopeURLs, runToken: runToken)
        }
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

        cancelMDFindTask()

        if releaseSecurityScopedResources {
            for scopedURL in securityScopedURLs {
                scopedURL.stopAccessingSecurityScopedResource()
            }
            securityScopedURLs.removeAll()
        }
    }

    private func cancelMDFindTask() {
        let task = withMDFindTaskLock { () -> Process? in
            defer { mdfindTask = nil }
            return mdfindTask
        }
        task?.interrupt()
        task?.terminate()
    }

    private func setMDFindTask(_ task: Process?) {
        withMDFindTaskLock {
            mdfindTask = task
        }
    }

    @discardableResult
    private func withMDFindTaskLock<T>(_ action: () -> T) -> T {
        mdfindTaskLock.lock()
        defer { mdfindTaskLock.unlock() }
        return action()
    }

    private func applyResults(_ items: [SearchResultItem],
                              totalCount: Int?,
                              hasMore: Bool,
                              sortOption: SearchResultSortOption,
                              isPreview: Bool = false)
    {
        // Client-side filter: mdfind uses the Spotlight index which may lag
        // behind xattr writes, so a file can appear in results even after its
        // tags no longer satisfy the current include/exclude filters.  Dropping
        // such items here keeps facet counts consistent with what's on disk.
        let filtered = clientSideFilter(items)
        results = filtered
        topFacets = facetCounter.topTags(from: filtered)
        knownTotalResults = totalCount
        hasMoreResults = hasMore
        resultsSortOption = sortOption
        isRefiningResults = isPreview
    }

    /// Returns only the items whose on-disk tags still satisfy the current
    /// include and exclude filters, using the same case-insensitive comparison
    /// that tag normalization uses elsewhere in the app.
    private func clientSideFilter(_ items: [SearchResultItem]) -> [SearchResultItem] {
        guard let state = lastRunState,
              !state.includeTags.isEmpty || !state.excludeTags.isEmpty
        else {
            return items
        }
        let normalize: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let includeLower = state.includeTags.map(normalize)
        let excludeLower = state.excludeTags.map(normalize)
        return items.filter { item in
            let itemNames = item.tags.map { normalize($0.name) }
            return includeLower.allSatisfy { itemNames.contains($0) }
                && excludeLower.allSatisfy { !itemNames.contains($0) }
        }
    }

    private func clearResultsAndCoverage(sortOption: SearchResultSortOption? = nil) {
        let effectiveSort = sortOption ?? lastRunState?.sortOption ?? resultsSortOption
        applyResults([],
                     totalCount: nil,
                     hasMore: false,
                     sortOption: effectiveSort,
                     isPreview: false)
    }

    private func makeCacheKey(for state: QueryState) -> SearchCacheKey {
        let scopePaths = normalizedScopePaths(for: state.scopeURLs)
        return SearchCacheKey(includeTags: state.includeTags,
                              excludeTags: state.excludeTags,
                              scopePaths: scopePaths,
                              includeSubdirectories: state.includeSubdirectories)
    }

    private func makeScopeTagIndexKey(for state: QueryState) -> ScopeTagIndexKey {
        ScopeTagIndexKey(scopePaths: normalizedScopePaths(for: state.scopeURLs),
                         includeSubdirectories: state.includeSubdirectories)
    }

    private func normalizedScopePaths(for scopeURLs: [URL]) -> [String] {
        scopeURLs
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
            .sorted()
    }

    private func clearCachedSortableResults() {
        cachedSearchKey = nil
        cachedSortableResults = []
    }

    private func clearScopeTagCatalog() {
        currentScopeTagIndexToken = UUID()
        cachedScopeTagIndexKey = nil
        scopeTagCatalogNeedsRefresh = true
        scopeTagCatalog = [:]
    }

    private func cacheSortableResults(_ items: [SearchResultItem], for state: QueryState) {
        cachedSearchKey = makeCacheKey(for: state)
        cachedSortableResults = items
    }

    private func serveCachedResultsIfAvailable(state: QueryState, runToken: UUID) -> Bool {
        guard cachedSearchKey == makeCacheKey(for: state),
              !cachedSortableResults.isEmpty else { return false }

        let cachedItems = cachedSortableResults
        let sortOption = state.sortOption
        let limit = currentResultLimit
        let existingResults = Dictionary(uniqueKeysWithValues: results.map { ($0.url, $0) })

        isSearching = true
        fallbackQueue.async { [weak self] in
            guard let self else { return }
            let page = SearchResultPaginator.page(cachedItems, sortOption: sortOption, limit: limit)
            let hydrated = hydrateVisibleResults(page.visible, existingResults: existingResults)

            DispatchQueue.main.async {
                guard self.currentRunToken == runToken else { return }
                self.applyResults(hydrated,
                                  totalCount: page.totalCount,
                                  hasMore: page.hasMore,
                                  sortOption: sortOption,
                                  isPreview: false)
                self.isSearching = false
                self.lastError = nil
            }
        }

        return true
    }

    private func refreshScopeTagCatalogIfNeeded(for state: QueryState) {
        let key = makeScopeTagIndexKey(for: state)

        if cachedScopeTagIndexKey != key {
            cachedScopeTagIndexKey = key
            scopeTagCatalogNeedsRefresh = true
            scopeTagCatalog = [:]
        }

        guard scopeTagCatalogNeedsRefresh else { return }
        scopeTagCatalogNeedsRefresh = false

        let indexToken = UUID()
        currentScopeTagIndexToken = indexToken
        let includeSubdirectories = state.includeSubdirectories

        tagIndexQueue.async { [weak self] in
            guard let self else { return }

            let accessibleScopeURLs = beginTransientSecurityScope(for: state.scopeURLs)
            guard !accessibleScopeURLs.isEmpty else {
                DispatchQueue.main.async {
                    guard self.currentScopeTagIndexToken == indexToken,
                          self.cachedScopeTagIndexKey == key else { return }
                    self.scopeTagCatalogNeedsRefresh = true
                    self.scopeTagCatalog = [:]
                }
                return
            }

            defer { self.endSecurityScope(for: accessibleScopeURLs) }

            let catalog = buildScopeTagCatalog(scopeURLs: accessibleScopeURLs,
                                               includeSubdirectories: includeSubdirectories)
            DispatchQueue.main.async {
                guard self.currentScopeTagIndexToken == indexToken,
                      self.cachedScopeTagIndexKey == key else { return }
                self.scopeTagCatalog = catalog
            }
        }
    }

    private func normalizedTags(primaryTags: [String]?, fallbackTags: [String]? = nil, url: URL) -> [FinderTag] {
        if let tags = primaryTags,
           let parsed = parseFinderTags(from: tags)
        {
            return parsed
        }

        if let mdTags = finderMetadataTags(for: url),
           let parsed = parseFinderTags(from: mdTags)
        {
            return parsed
        }

        if let fallback = fallbackTags,
           let parsed = parseFinderTags(from: fallback)
        {
            return parsed
        }

        if fallbackTags == nil,
           let resourceValues = try? url.resourceValues(forKeys: [.tagNamesKey]),
           let tagNames = resourceValues.tagNames,
           let parsed = parseFinderTags(from: tagNames)
        {
            return parsed
        }

        return []
    }

    private func buildScopeTagCatalog(scopeURLs: [URL],
                                      includeSubdirectories: Bool) -> [String: TagAutocompleteEntry]
    {
        if let indexed = buildScopeTagCatalogUsingMDFind(scopeURLs: scopeURLs,
                                                         includeSubdirectories: includeSubdirectories)
        {
            return indexed
        }
        return buildScopeTagCatalogByEnumeration(scopeURLs: scopeURLs,
                                                 includeSubdirectories: includeSubdirectories)
    }

    private func buildScopeTagCatalogUsingMDFind(scopeURLs: [URL],
                                                 includeSubdirectories: Bool) -> [String: TagAutocompleteEntry]?
    {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")

        var arguments: [String] = []
        for url in scopeURLs {
            arguments.append(contentsOf: ["-onlyin", url.path])
        }
        arguments.append("kMDItemUserTags == '*'")
        task.arguments = arguments

        let stdoutPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return nil
        }

        let output = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else { return nil }

        var catalog: [String: TagAutocompleteEntry] = [:]
        let paths = String(decoding: output, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }

        // Standardize scope URLs once for efficient parent-path comparison.
        let standardizedScopes = includeSubdirectories ? [] : scopeURLs.map(\.standardizedFileURL)

        for path in paths {
            let url = URL(fileURLWithPath: path)
            if !includeSubdirectories {
                let parent = url.deletingLastPathComponent().standardizedFileURL
                guard standardizedScopes.contains(parent) else { continue }
            }
            TagAutocompleteCatalogBuilder.add(normalizedTags(primaryTags: nil, url: url), into: &catalog)
        }

        return catalog
    }

    private func buildScopeTagCatalogByEnumeration(scopeURLs: [URL],
                                                   includeSubdirectories: Bool) -> [String: TagAutocompleteEntry]
    {
        let fm = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .tagNamesKey]
        var catalog: [String: TagAutocompleteEntry] = [:]

        for scope in scopeURLs {
            let scopeValues = try? scope.resourceValues(forKeys: resourceKeys)
            if scopeValues?.isRegularFile == true {
                TagAutocompleteCatalogBuilder.add(normalizedTags(primaryTags: nil,
                                                                 fallbackTags: scopeValues?.tagNames,
                                                                 url: scope),
                                                  into: &catalog)
                continue
            }

            if !includeSubdirectories {
                // List only immediate children; no recursive descent.
                let children = (try? fm.contentsOfDirectory(at: scope,
                                                            includingPropertiesForKeys: Array(resourceKeys),
                                                            options: [.skipsHiddenFiles,
                                                                      .skipsPackageDescendants])) ?? []
                for fileURL in children {
                    let values = try? fileURL.resourceValues(forKeys: resourceKeys)
                    guard values?.isRegularFile == true else { continue }
                    TagAutocompleteCatalogBuilder.add(normalizedTags(primaryTags: nil,
                                                                     fallbackTags: values?.tagNames,
                                                                     url: fileURL),
                                                      into: &catalog)
                }
                continue
            }

            guard scopeValues?.isDirectory ?? true,
                  let enumerator = fm.enumerator(at: scope,
                                                 includingPropertiesForKeys: Array(resourceKeys),
                                                 options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                 errorHandler: nil)
            else {
                continue
            }

            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: resourceKeys)
                if values?.isDirectory == true {
                    continue
                }

                TagAutocompleteCatalogBuilder.add(normalizedTags(primaryTags: nil,
                                                                 fallbackTags: values?.tagNames,
                                                                 url: fileURL),
                                                  into: &catalog)
            }
        }

        return catalog
    }

    private func makeResult(url: URL,
                            preferredName: String? = nil,
                            fallbackName: String? = nil,
                            primaryTags: [String]? = nil,
                            fallbackTags: [String]? = nil,
                            resourceValues: URLResourceValues? = nil) -> SearchResultItem
    {
        let displayName = preferredName ?? fallbackName ?? url.lastPathComponent
        let tags = normalizedTags(primaryTags: primaryTags, fallbackTags: fallbackTags, url: url)
        let metadata = resourceValues
            ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey]))

        return SearchResultItem(url: url,
                                displayName: displayName,
                                tags: tags,
                                contentModificationDate: metadata?.contentModificationDate,
                                creationDate: metadata?.creationDate,
                                fileSizeBytes: metadata?.fileSize.map(Int64.init))
    }

    private func makeSortableResult(url: URL,
                                    preferredName: String? = nil,
                                    fallbackName: String? = nil,
                                    resourceValues: URLResourceValues? = nil) -> SearchResultItem
    {
        let displayName = preferredName ?? fallbackName ?? url.lastPathComponent
        let metadata = resourceValues
            ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey]))

        return SearchResultItem(url: url,
                                displayName: displayName,
                                tags: [],
                                contentModificationDate: metadata?.contentModificationDate,
                                creationDate: metadata?.creationDate,
                                fileSizeBytes: metadata?.fileSize.map(Int64.init))
    }

    private func hydrateVisibleResults(_ items: [SearchResultItem],
                                       existingResults: [URL: SearchResultItem] = [:]) -> [SearchResultItem]
    {
        items.map { item in
            let tags = existingResults[item.url]?.tags ?? normalizedTags(primaryTags: nil,
                                                                         fallbackTags: nil,
                                                                         url: item.url)
            return SearchResultItem(url: item.url,
                                    displayName: item.displayName,
                                    tags: tags,
                                    contentModificationDate: item.contentModificationDate,
                                    creationDate: item.creationDate,
                                    fileSizeBytes: item.fileSizeBytes)
        }
    }

    private func resourceKeysForSort(_ sortOption: SearchResultSortOption) -> Set<URLResourceKey> {
        var keys: Set<URLResourceKey> = [.localizedNameKey]

        switch sortOption {
        case .nameAscending, .nameDescending:
            break
        case .modifiedNewestFirst, .modifiedOldestFirst:
            keys.insert(.contentModificationDateKey)
        case .createdNewestFirst, .createdOldestFirst:
            keys.insert(.creationDateKey)
        case .sizeLargestFirst, .sizeSmallestFirst:
            keys.insert(.fileSizeKey)
        case .tagCountFewestFirst, .tagCountMostFirst:
            // Tag count is derived from the tags array populated during hydration;
            // no extra URL resource keys are required.
            break
        }

        return keys
    }

    private protocol SearchBackend {
        func start(state: QueryState, scopeURLs: [URL], runToken: UUID) -> Bool
    }

    private final class MetadataQueryBackend: SearchBackend {
        weak var controller: MetadataSearchController?

        init(controller: MetadataSearchController) {
            self.controller = controller
        }

        func start(state: QueryState, scopeURLs: [URL], runToken _: UUID) -> Bool {
            guard let controller, controller.enableMetadataQuery else { return false }

            let q = NSMetadataQuery()
            controller.query = q
            q.predicate = SpotlightTagQueryBuilder.predicate(include: state.includeTags, exclude: state.excludeTags)
            q.sortDescriptors = controller.metadataSortDescriptors(for: state.sortOption)
            q.notificationBatchingInterval = 0.2

            controller.isSearching = true

            let nc = NotificationCenter.default
            controller.observers.append(nc.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak controller] _ in
                controller?.refreshFromQuery()
                controller?.isSearching = false
            })

            controller.observers.append(nc.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { [weak controller] _ in
                controller?.refreshFromQuery()
            })

            let primaryScopes = scopeURLs.map { $0 as NSURL }
            if controller.startQuery(q, scopes: primaryScopes) {
                return true
            }

            if let fallbackScopes = SpotlightDiagnostics.fallbackScopes(for: scopeURLs),
               controller.startQuery(q, scopes: fallbackScopes)
            {
                return true
            }

            controller.stop(releaseSecurityScopedResources: false)
            return false
        }
    }

    private final class MDFindBackend: SearchBackend {
        weak var controller: MetadataSearchController?

        init(controller: MetadataSearchController) {
            self.controller = controller
        }

        func start(state: QueryState, scopeURLs: [URL], runToken: UUID) -> Bool {
            guard let controller else { return false }
            guard !scopeURLs.isEmpty else { return false }
            guard let arguments = buildMDFindArguments(scopeURLs: scopeURLs,
                                                       include: state.includeTags,
                                                       exclude: state.excludeTags),
                !arguments.isEmpty else { return false }

            controller.isSearching = true
            let resourceKeys = controller.resourceKeysForSort(state.sortOption)

            controller.fallbackQueue.async { [weak self] in
                guard let self, let controller = self.controller else { return }

                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
                task.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                task.standardOutput = stdoutPipe
                task.standardError = stderrPipe
                controller.setMDFindTask(task)

                do {
                    try task.run()
                } catch {
                    controller.setMDFindTask(nil)
                    handleFailure("Failed to run mdfind: \(error.localizedDescription)", runToken: runToken)
                    return
                }

                let limit = controller.currentResultLimit
                var items: [SearchResultItem] = []
                items.reserveCapacity(limit)
                var previewHydratedByURL: [URL: SearchResultItem] = [:]
                var sentPreview = false
                var stdoutBuffer = Data()
                var stderrData = Data()
                let outputGroup = DispatchGroup()
                let outputQueue = DispatchQueue.global(qos: .userInitiated)

                outputGroup.enter()
                outputQueue.async {
                    stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    outputGroup.leave()
                }

                // Standardize scope URLs once for efficient parent-path comparison.
                let standardizedScopes = state.includeSubdirectories
                    ? []
                    : scopeURLs.map(\.standardizedFileURL)

                func appendPath(_ path: String) {
                    let url = URL(fileURLWithPath: path)
                    if !state.includeSubdirectories {
                        let parent = url.deletingLastPathComponent().standardizedFileURL
                        guard standardizedScopes.contains(parent) else { return }
                    }
                    let resourceValues = try? url.resourceValues(forKeys: resourceKeys)
                    let item = controller.makeSortableResult(url: url,
                                                             preferredName: resourceValues?.localizedName,
                                                             resourceValues: resourceValues)
                    items.append(item)

                    if !sentPreview, items.count >= limit {
                        let previewPage = SearchResultPaginator.page(items,
                                                                     sortOption: state.sortOption,
                                                                     limit: limit)
                        let previewResults = controller.hydrateVisibleResults(previewPage.visible)
                        previewHydratedByURL = Dictionary(uniqueKeysWithValues: previewResults.map { ($0.url, $0) })
                        sentPreview = true

                        DispatchQueue.main.async {
                            guard let controller = self.controller,
                                  controller.currentRunToken == runToken else { return }
                            controller.applyResults(previewResults,
                                                    totalCount: nil,
                                                    hasMore: true,
                                                    sortOption: state.sortOption,
                                                    isPreview: true)
                        }
                    }
                }

                while true {
                    let chunk = stdoutPipe.fileHandleForReading.availableData
                    if chunk.isEmpty {
                        break
                    }
                    stdoutBuffer.append(chunk)
                    let paths = NewlineDelimitedPathParser.consumeAvailableLines(from: &stdoutBuffer, flush: false)
                    for path in paths {
                        appendPath(path)
                    }
                }
                let remainingPaths = NewlineDelimitedPathParser.consumeAvailableLines(from: &stdoutBuffer, flush: true)
                for path in remainingPaths {
                    appendPath(path)
                }

                task.waitUntilExit()
                outputGroup.wait()
                controller.setMDFindTask(nil)

                let errorOutput = String(decoding: stderrData, as: UTF8.self)

                guard task.terminationStatus == 0 else {
                    let trimmed = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    let detail = trimmed.isEmpty ? "" : " Details: \(trimmed)"
                    handleFailure("mdfind exited with code \(task.terminationStatus).\(detail)", runToken: runToken)
                    return
                }

                let page = SearchResultPaginator.page(items,
                                                      sortOption: state.sortOption,
                                                      limit: limit)
                let visibleResults = controller.hydrateVisibleResults(page.visible,
                                                                      existingResults: previewHydratedByURL)

                DispatchQueue.main.async {
                    guard let controller = self.controller,
                          controller.currentRunToken == runToken else { return }
                    controller.cacheSortableResults(items, for: state)
                    controller.applyResults(visibleResults,
                                            totalCount: page.totalCount,
                                            hasMore: page.hasMore,
                                            sortOption: state.sortOption,
                                            isPreview: false)
                    controller.isSearching = false
                    controller.lastError = nil
                }
            }

            return true
        }

        private func buildMDFindArguments(scopeURLs: [URL],
                                          include: Set<String>,
                                          exclude: Set<String>) -> [String]?
        {
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

        private func handleFailure(_ message: String, runToken: UUID) {
            DispatchQueue.main.async { [weak controller] in
                guard let controller, controller.currentRunToken == runToken else { return }
                controller.clearResultsAndCoverage()
                controller.isSearching = false
                controller.lastError = message
            }
        }
    }

    private final class EnumerationBackend: SearchBackend {
        weak var controller: MetadataSearchController?

        init(controller: MetadataSearchController) {
            self.controller = controller
        }

        func start(state: QueryState, scopeURLs: [URL], runToken: UUID) -> Bool {
            guard let controller else { return false }
            guard !scopeURLs.isEmpty else { return false }

            controller.isSearching = true
            var resourceKeys: Set<URLResourceKey> = [.isRegularFileKey,
                                                     .isDirectoryKey,
                                                     .localizedNameKey]
            resourceKeys.formUnion(controller.resourceKeysForSort(state.sortOption))
            let fm = FileManager.default

            controller.fallbackQueue.async { [weak self] in
                guard let self, let controller = self.controller else { return }

                var collected: [SearchResultItem] = []
                collected.reserveCapacity(controller.currentResultLimit)
                var sentPreview = false
                var previewHydratedByURL: [URL: SearchResultItem] = [:]

                for scope in scopeURLs {
                    let scopeValues = try? scope.resourceValues(forKeys: resourceKeys)
                    if scopeValues?.isRegularFile == true {
                        let item = controller.makeSortableResult(url: scope,
                                                                 preferredName: scopeValues?.localizedName,
                                                                 resourceValues: scopeValues)
                        collected.append(item)
                        continue
                    }

                    if !state.includeSubdirectories {
                        // List only immediate children; no recursive descent.
                        let children = (try? fm.contentsOfDirectory(at: scope,
                                                                    includingPropertiesForKeys: Array(resourceKeys),
                                                                    options: [.skipsHiddenFiles,
                                                                              .skipsPackageDescendants])) ?? []
                        for fileURL in children {
                            let values = try? fileURL.resourceValues(forKeys: resourceKeys)
                            guard values?.isRegularFile == true else { continue }
                            let item = controller.makeSortableResult(url: fileURL,
                                                                     preferredName: values?.localizedName,
                                                                     resourceValues: values)
                            collected.append(item)
                        }
                        continue
                    }

                    guard scopeValues?.isDirectory ?? true,
                          let enumerator = fm.enumerator(at: scope,
                                                         includingPropertiesForKeys: Array(resourceKeys),
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                         errorHandler: nil)
                    else {
                        continue
                    }

                    for case let fileURL as URL in enumerator {
                        let values = try? fileURL.resourceValues(forKeys: resourceKeys)
                        if values?.isDirectory == true {
                            continue
                        }

                        let item = controller.makeSortableResult(url: fileURL,
                                                                 preferredName: values?.localizedName,
                                                                 resourceValues: values)
                        collected.append(item)

                        if !sentPreview,
                           collected.count >= controller.currentResultLimit
                        {
                            let previewPage = SearchResultPaginator.page(collected,
                                                                         sortOption: state.sortOption,
                                                                         limit: controller.currentResultLimit)
                            let previewResults = controller.hydrateVisibleResults(previewPage.visible)
                            previewHydratedByURL = Dictionary(uniqueKeysWithValues: previewResults.map { ($0.url, $0) })
                            sentPreview = true

                            DispatchQueue.main.async {
                                guard let controller = self.controller,
                                      controller.currentRunToken == runToken else { return }
                                controller.applyResults(previewResults,
                                                        totalCount: nil,
                                                        hasMore: true,
                                                        sortOption: state.sortOption,
                                                        isPreview: true)
                            }
                        }
                    }
                }

                let page = SearchResultPaginator.page(collected,
                                                      sortOption: state.sortOption,
                                                      limit: controller.currentResultLimit)
                let visibleResults = controller.hydrateVisibleResults(page.visible,
                                                                      existingResults: previewHydratedByURL)

                DispatchQueue.main.async {
                    guard let controller = self.controller,
                          controller.currentRunToken == runToken else { return }
                    controller.cacheSortableResults(collected, for: state)
                    controller.applyResults(visibleResults,
                                            totalCount: page.totalCount,
                                            hasMore: page.hasMore,
                                            sortOption: state.sortOption,
                                            isPreview: false)
                    controller.isSearching = false
                    controller.lastError = nil
                }
            }

            return true
        }
    }

    private func parseFinderTags(from rawValues: [String]) -> [FinderTag]? {
        let parsed = rawValues.compactMap(FinderTag.init(rawValue:))
        return parsed.isEmpty ? nil : parsed
    }

    private func finderMetadataTags(for url: URL) -> [String]? {
        // Prefer xattr: FinderTagEditor writes directly there, so it reflects
        // tag edits immediately without waiting for Spotlight to re-index.
        if let xattrTags = extendedAttributeTags(for: url) {
            return xattrTags
        }
        if let mdTags = mdItemTags(for: url) {
            return mdTags
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
                  !tags.isEmpty
            else {
                return nil
            }

            return tags
        }
    }

    private func refreshFromQuery() {
        guard let q = query else { return }

        // Convert query results to SearchResultItems
        let items = (q.results as? [NSMetadataItem]) ?? []
        let limit = currentResultLimit

        var newResults: [SearchResultItem] = []
        newResults.reserveCapacity(min(items.count, limit))

        // Render only up to the current page limit; users can request additional pages.
        for item in items.prefix(limit) {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let name = (item.value(forAttribute: kMDItemFSName as String) as? String)
            let metadataTags = item.value(forAttribute: SpotlightTagQueryBuilder.metadataUserTagsAttribute) as? [String]
            let result = makeResult(url: url,
                                    preferredName: name,
                                    primaryTags: metadataTags,
                                    fallbackTags: nil)
            newResults.append(result)
        }

        applyResults(newResults,
                     totalCount: items.count,
                     hasMore: items.count > limit,
                     sortOption: lastRunState?.sortOption ?? resultsSortOption,
                     isPreview: false)
    }

    private func metadataSortDescriptors(for sortOption: SearchResultSortOption) -> [NSSortDescriptor] {
        switch sortOption {
        case .nameAscending:
            [NSSortDescriptor(key: kMDItemFSName as String, ascending: true,
                              selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))]
        case .nameDescending:
            [NSSortDescriptor(key: kMDItemFSName as String, ascending: false,
                              selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))]
        case .modifiedNewestFirst:
            [NSSortDescriptor(key: kMDItemContentModificationDate as String, ascending: false)]
        case .modifiedOldestFirst:
            [NSSortDescriptor(key: kMDItemContentModificationDate as String, ascending: true)]
        case .createdNewestFirst:
            [NSSortDescriptor(key: kMDItemFSCreationDate as String, ascending: false)]
        case .createdOldestFirst:
            [NSSortDescriptor(key: kMDItemFSCreationDate as String, ascending: true)]
        case .sizeLargestFirst:
            [NSSortDescriptor(key: kMDItemFSSize as String, ascending: false)]
        case .sizeSmallestFirst:
            [NSSortDescriptor(key: kMDItemFSSize as String, ascending: true)]
        case .tagCountFewestFirst, .tagCountMostFirst:
            // Spotlight has no native tag-count key; fall back to name order.
            // The display sort in SearchResultSortOption.sorted(_:) applies the
            // correct tag-count ordering after results are fetched and hydrated.
            [NSSortDescriptor(key: kMDItemFSName as String, ascending: true,
                              selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))]
        }
    }

    @discardableResult
    private func beginSecurityScope(for urls: [URL]) -> [URL] {
        var accessible: [URL] = []

        for scopedURL in securityScopedURLs {
            scopedURL.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs.removeAll()

        if !isSandboxed {
            securityScopedURLs = urls
            return urls
        }

        for url in urls {
            if url.startAccessingSecurityScopedResource() {
                securityScopedURLs.append(url)
                accessible.append(url)
            }
        }

        return accessible
    }

    @discardableResult
    private func beginTransientSecurityScope(for urls: [URL]) -> [URL] {
        guard isSandboxed else { return urls }

        var accessible: [URL] = []
        for url in urls {
            if url.startAccessingSecurityScopedResource() {
                accessible.append(url)
            }
        }
        return accessible
    }

    private func endSecurityScope(for urls: [URL]) {
        guard isSandboxed else { return }
        for url in urls {
            url.stopAccessingSecurityScopedResource()
        }
    }

    private func startQuery(_ query: NSMetadataQuery, scopes: [Any]) -> Bool {
        guard !scopes.isEmpty else { return false }
        query.searchScopes = scopes
        return query.start()
    }
}
