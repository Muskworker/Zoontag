import Foundation
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
    private let mdfindTaskLock = NSLock()
    private var mdfindTask: Process?
    private let isSandboxed: Bool = {
        return ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }()
    private lazy var metadataBackend = MetadataQueryBackend(controller: self)
    private lazy var mdfindBackend = MDFindBackend(controller: self)
    private lazy var enumerationBackend = EnumerationBackend(controller: self)

    private enum SearchStrategy {
        case metadataQuery
        case mdfind
        case enumerate
    }

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

        let strategyList = strategies(hasTagFilters: hasTagFilters)
        for strategy in strategyList {
            if execute(strategy,
                       state: state,
                       scopeURLs: scopeURLs,
                       runToken: runToken) {
                return
            }
        }

        stop()
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
                         runToken: UUID) -> Bool {
        switch strategy {
        case .metadataQuery:
            return metadataBackend.start(state: state, scopeURLs: scopeURLs, runToken: runToken)
        case .mdfind:
            return mdfindBackend.start(state: state, scopeURLs: scopeURLs, runToken: runToken)
        case .enumerate:
            return enumerationBackend.start(state: state, scopeURLs: scopeURLs, runToken: runToken)
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

    private func makeResult(url: URL,
                            preferredName: String? = nil,
                            fallbackName: String? = nil,
                            primaryTags: [String]? = nil,
                            fallbackTags: [String]? = nil,
                            resourceValues: URLResourceValues? = nil) -> SearchResultItem {
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

    private protocol SearchBackend {
        func start(state: QueryState, scopeURLs: [URL], runToken: UUID) -> Bool
    }

    private final class MetadataQueryBackend: SearchBackend {
        weak var controller: MetadataSearchController?

        init(controller: MetadataSearchController) {
            self.controller = controller
        }

        func start(state: QueryState, scopeURLs: [URL], runToken: UUID) -> Bool {
            guard let controller, controller.enableMetadataQuery else { return false }

            let q = NSMetadataQuery()
            controller.query = q
            q.predicate = SpotlightTagQueryBuilder.predicate(include: state.includeTags, exclude: state.excludeTags)
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
               controller.startQuery(q, scopes: fallbackScopes) {
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
            let resourceKeys: Set<URLResourceKey> = [.localizedNameKey,
                                                     .tagNamesKey,
                                                     .contentModificationDateKey,
                                                     .creationDateKey,
                                                     .fileSizeKey]

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
                    self.handleFailure("Failed to run mdfind: \(error.localizedDescription)", runToken: runToken)
                    return
                }

                var stdoutData = Data()
                var stderrData = Data()
                let outputGroup = DispatchGroup()
                let outputQueue = DispatchQueue.global(qos: .userInitiated)

                // Drain both streams while the process is running to avoid pipe backpressure deadlocks.
                outputGroup.enter()
                outputQueue.async {
                    stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    outputGroup.leave()
                }

                outputGroup.enter()
                outputQueue.async {
                    stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    outputGroup.leave()
                }

                task.waitUntilExit()
                outputGroup.wait()
                controller.setMDFindTask(nil)

                let output = String(decoding: stdoutData, as: UTF8.self)
                let errorOutput = String(decoding: stderrData, as: UTF8.self)

                guard task.terminationStatus == 0 else {
                    let trimmed = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    let detail = trimmed.isEmpty ? "" : " Details: \(trimmed)"
                    self.handleFailure("mdfind exited with code \(task.terminationStatus).\(detail)", runToken: runToken)
                    return
                }

                let lines = output.split(whereSeparator: \.isNewline)
                var items: [SearchResultItem] = []
                items.reserveCapacity(min(lines.count, controller.resultLimit))

                for line in lines {
                    if items.count >= controller.resultLimit {
                        break
                    }
                    let path = String(line)
                    guard !path.isEmpty else { continue }
                    let url = URL(fileURLWithPath: path)
                    let resourceValues = try? url.resourceValues(forKeys: resourceKeys)
                    let item = controller.makeResult(url: url,
                                                     preferredName: resourceValues?.localizedName,
                                                     primaryTags: nil,
                                                     fallbackTags: resourceValues?.tagNames,
                                                     resourceValues: resourceValues)
                    items.append(item)
                }

                DispatchQueue.main.async {
                    guard let controller = self.controller,
                          controller.currentRunToken == runToken else { return }
                    controller.results = items
                    controller.topFacets = controller.facetCounter.topTags(from: items)
                    controller.isSearching = false
                    controller.lastError = nil
                }
            }

            return true
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

        private func handleFailure(_ message: String, runToken: UUID) {
            DispatchQueue.main.async { [weak controller] in
                guard let controller, controller.currentRunToken == runToken else { return }
                controller.results = []
                controller.topFacets = []
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
            let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey,
                                                     .isDirectoryKey,
                                                     .localizedNameKey,
                                                     .tagNamesKey,
                                                     .contentModificationDateKey,
                                                     .creationDateKey,
                                                     .fileSizeKey]
            let fm = FileManager.default

            controller.fallbackQueue.async { [weak self] in
                guard let self, let controller = self.controller else { return }

                var collected: [SearchResultItem] = []
                collected.reserveCapacity(controller.resultLimit)

                scopeLoop: for scope in scopeURLs {
                    if collected.count >= controller.resultLimit { break }

                    let scopeValues = try? scope.resourceValues(forKeys: resourceKeys)
                    if scopeValues?.isRegularFile == true {
                        let item = controller.makeResult(url: scope,
                                                         preferredName: scopeValues?.localizedName,
                                                         primaryTags: nil,
                                                         fallbackTags: scopeValues?.tagNames,
                                                         resourceValues: scopeValues)
                        collected.append(item)
                        continue
                    }

                    guard scopeValues?.isDirectory ?? true,
                          let enumerator = fm.enumerator(at: scope,
                                                         includingPropertiesForKeys: Array(resourceKeys),
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                         errorHandler: nil) else {
                        continue
                    }

                    for case let fileURL as URL in enumerator {
                        if collected.count >= controller.resultLimit {
                            break scopeLoop
                        }

                        let values = try? fileURL.resourceValues(forKeys: resourceKeys)
                        if values?.isDirectory == true {
                            continue
                        }

                        let item = controller.makeResult(url: fileURL,
                                                         preferredName: values?.localizedName,
                                                         primaryTags: nil,
                                                         fallbackTags: values?.tagNames,
                                                         resourceValues: values)
                        collected.append(item)
                    }
                }

                DispatchQueue.main.async {
                    guard let controller = self.controller,
                          controller.currentRunToken == runToken else { return }
                    controller.results = collected
                    controller.topFacets = controller.facetCounter.topTags(from: collected)
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
            let name = (item.value(forAttribute: kMDItemFSName as String) as? String)
            let metadataTags = item.value(forAttribute: SpotlightTagQueryBuilder.metadataUserTagsAttribute) as? [String]
            let result = makeResult(url: url,
                                    preferredName: name,
                                    primaryTags: metadataTags,
                                    fallbackTags: nil)
            newResults.append(result)
        }

        results = newResults
        topFacets = facetCounter.topTags(from: newResults)
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

    private func startQuery(_ query: NSMetadataQuery, scopes: [Any]) -> Bool {
        guard !scopes.isEmpty else { return false }
        query.searchScopes = scopes
        return query.start()
    }

}
