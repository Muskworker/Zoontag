import Foundation

struct WorkspaceSession: Equatable {
    var queryState: QueryState
    var isDetailPaneVisible: Bool
}

final class WorkspaceSessionStore {
    struct BookmarkResolution {
        let url: URL
        let isStale: Bool
    }

    private struct PersistedSession: Codable {
        struct PersistedScope: Codable {
            let bookmarkData: Data
        }

        let includeTags: [String]
        let excludeTags: [String]
        let sortOptionRawValue: String
        let isDetailPaneVisible: Bool
        let scopes: [PersistedScope]
        /// Nil in sessions saved before this field was introduced; treated as true on restore.
        let includeSubdirectories: Bool?
        /// Nil in sessions saved before file-type filters were introduced; treated as empty on restore.
        let includeFileTypes: [String]?
        /// Nil in sessions saved before file-type filters were introduced; treated as empty on restore.
        let excludeFileTypes: [String]?
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let createBookmark: (URL) throws -> Data
    private let resolveBookmark: (Data) throws -> BookmarkResolution
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard,
         storageKey: String = "workspaceSession.v1",
         createBookmark: @escaping (URL) throws -> Data = WorkspaceSessionStore.createSecurityScopedBookmark(for:),
         resolveBookmark: @escaping (Data) throws -> BookmarkResolution = WorkspaceSessionStore.resolveSecurityScopedBookmark(from:))
    {
        self.defaults = defaults
        self.storageKey = storageKey
        self.createBookmark = createBookmark
        self.resolveBookmark = resolveBookmark
    }

    func save(queryState: QueryState, isDetailPaneVisible: Bool) {
        let persistedScopes = queryState.scopeURLs.compactMap { url -> PersistedSession.PersistedScope? in
            guard let bookmark = try? createBookmark(url.standardizedFileURL) else { return nil }
            return PersistedSession.PersistedScope(bookmarkData: bookmark)
        }

        let payload = PersistedSession(includeTags: Array(queryState.includeTags).sorted(),
                                       excludeTags: Array(queryState.excludeTags).sorted(),
                                       sortOptionRawValue: queryState.sortOption.rawValue,
                                       isDetailPaneVisible: isDetailPaneVisible,
                                       scopes: persistedScopes,
                                       includeSubdirectories: queryState.includeSubdirectories,
                                       includeFileTypes: Array(queryState.includeFileTypes).sorted(),
                                       excludeFileTypes: Array(queryState.excludeFileTypes).sorted())
        persist(payload)
    }

    func restore() -> WorkspaceSession? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        guard let persisted = try? decoder.decode(PersistedSession.self, from: data) else {
            defaults.removeObject(forKey: storageKey)
            return nil
        }

        var restoredURLs: [URL] = []
        var updatedScopes: [PersistedSession.PersistedScope] = []
        var seenPaths: Set<String> = []
        var shouldRewrite = false

        for scope in persisted.scopes {
            guard let resolution = try? resolveBookmark(scope.bookmarkData) else {
                shouldRewrite = true
                continue
            }

            let standardizedURL = resolution.url.standardizedFileURL
            if seenPaths.insert(standardizedURL.path).inserted {
                restoredURLs.append(standardizedURL)
            }

            if resolution.isStale,
               let refreshedBookmark = try? createBookmark(standardizedURL)
            {
                updatedScopes.append(PersistedSession.PersistedScope(bookmarkData: refreshedBookmark))
                shouldRewrite = true
            } else {
                updatedScopes.append(scope)
            }
        }

        let restoredSortOption = SearchResultSortOption(rawValue: persisted.sortOptionRawValue) ?? .createdNewestFirst
        if restoredSortOption.rawValue != persisted.sortOptionRawValue {
            shouldRewrite = true
        }

        let restoredState = QueryState(includeTags: Set(persisted.includeTags),
                                       excludeTags: Set(persisted.excludeTags),
                                       includeFileTypes: Set(persisted.includeFileTypes ?? []),
                                       excludeFileTypes: Set(persisted.excludeFileTypes ?? []),
                                       scopeURLs: restoredURLs,
                                       sortOption: restoredSortOption,
                                       includeSubdirectories: persisted.includeSubdirectories ?? true)
        let session = WorkspaceSession(queryState: restoredState,
                                       isDetailPaneVisible: persisted.isDetailPaneVisible)

        if shouldRewrite {
            let normalized = PersistedSession(includeTags: Array(restoredState.includeTags).sorted(),
                                              excludeTags: Array(restoredState.excludeTags).sorted(),
                                              sortOptionRawValue: restoredState.sortOption.rawValue,
                                              isDetailPaneVisible: session.isDetailPaneVisible,
                                              scopes: updatedScopes,
                                              includeSubdirectories: restoredState.includeSubdirectories,
                                              includeFileTypes: Array(restoredState.includeFileTypes).sorted(),
                                              excludeFileTypes: Array(restoredState.excludeFileTypes).sorted())
            persist(normalized)
        }

        return session
    }

    private func persist(_ payload: PersistedSession) {
        guard let data = try? encoder.encode(payload) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private nonisolated static func createSecurityScopedBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope],
                             includingResourceValuesForKeys: nil,
                             relativeTo: nil)
    }

    private nonisolated static func resolveSecurityScopedBookmark(from data: Data) throws -> BookmarkResolution {
        var isStale = false
        let resolvedURL = try URL(resolvingBookmarkData: data,
                                  options: [.withSecurityScope],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &isStale)
        return BookmarkResolution(url: resolvedURL, isStale: isStale)
    }
}
