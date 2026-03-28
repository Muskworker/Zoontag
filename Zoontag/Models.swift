import AppKit
import Foundation

struct SearchResultItem: Identifiable, Hashable {
    let url: URL
    let displayName: String
    let tags: [FinderTag]
    let contentModificationDate: Date?
    let creationDate: Date?
    let fileSizeBytes: Int64?
    /// Human-readable file kind (e.g. "PDF Document", "JPEG image") from the system's
    /// localized type description. Nil when the kind cannot be determined.
    let fileKind: String?

    init(url: URL,
         displayName: String,
         tags: [FinderTag],
         contentModificationDate: Date? = nil,
         creationDate: Date? = nil,
         fileSizeBytes: Int64? = nil,
         fileKind: String? = nil)
    {
        self.url = url
        self.displayName = displayName
        self.tags = tags
        self.contentModificationDate = contentModificationDate
        self.creationDate = creationDate
        self.fileSizeBytes = fileSizeBytes
        self.fileKind = fileKind
    }

    var id: URL {
        url
    }

    var tagNames: [String] {
        tags.map(\.name)
    }

    /// Placeholder thumbnail: file icon. We'll swap to QuickLook thumbnails later.
    func iconImage(size: CGFloat = 64) -> NSImage {
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: size, height: size)
        return img
    }
}

struct SearchResultsCoverage: Equatable {
    let visibleCount: Int
    let totalCount: Int?
    let hasMoreResults: Bool

    var resultCountText: String {
        if let totalCount {
            if hasMoreResults {
                return String(localized: "Results: \(visibleCount) of \(totalCount)")
            }
            return String(localized: "Results: \(totalCount)")
        }

        if hasMoreResults {
            return String(localized: "Results: \(visibleCount)+")
        }
        return String(localized: "Results: \(visibleCount)")
    }

    var statusText: String? {
        if let totalCount, hasMoreResults {
            return String(localized: "Showing first \(visibleCount) of \(totalCount) results.")
        }
        if hasMoreResults {
            return String(localized: "Showing first \(visibleCount) results. Load more to continue.")
        }
        return nil
    }
}

enum SearchResultPaginator {
    static func page(_ items: [SearchResultItem],
                     sortOption: SearchResultSortOption,
                     limit: Int) -> (visible: [SearchResultItem], totalCount: Int, hasMore: Bool)
    {
        let safeLimit = max(0, limit)
        let sorted = sortOption.sorted(items)
        let visible = Array(sorted.prefix(safeLimit))
        return (visible, sorted.count, sorted.count > safeLimit)
    }
}

enum NewlineDelimitedPathParser {
    private static let newlineByte: UInt8 = 0x0A

    static func consumeAvailableLines(from buffer: inout Data, flush: Bool) -> [String] {
        let consumedEnd: Data.Index
        if flush {
            consumedEnd = buffer.endIndex
        } else if let lastNewlineIndex = buffer.lastIndex(of: newlineByte) {
            consumedEnd = buffer.index(after: lastNewlineIndex)
        } else {
            return []
        }

        let consumedCount = buffer.distance(from: buffer.startIndex, to: consumedEnd)
        guard consumedCount > 0 else { return [] }

        let chunk = buffer[..<consumedEnd]
        let text = String(decoding: chunk, as: UTF8.self)
        buffer.removeFirst(consumedCount)

        return text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

enum SearchResultSortOption: String, CaseIterable, Identifiable {
    case nameAscending
    case nameDescending
    case modifiedNewestFirst
    case modifiedOldestFirst
    case createdNewestFirst
    case createdOldestFirst
    case sizeLargestFirst
    case sizeSmallestFirst
    /// Fewest tags first — surfaces untagged and undertagged files.
    case tagCountFewestFirst
    /// Most tags first — surfaces the most heavily tagged files.
    case tagCountMostFirst

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .nameAscending: String(localized: "Name (A-Z)")
        case .nameDescending: String(localized: "Name (Z-A)")
        case .modifiedNewestFirst: String(localized: "Date Modified (Newest)")
        case .modifiedOldestFirst: String(localized: "Date Modified (Oldest)")
        case .createdNewestFirst: String(localized: "Date Created (Newest)")
        case .createdOldestFirst: String(localized: "Date Created (Oldest)")
        case .sizeLargestFirst: String(localized: "Size (Largest)")
        case .sizeSmallestFirst: String(localized: "Size (Smallest)")
        case .tagCountFewestFirst: String(localized: "Tag Count (Fewest)")
        case .tagCountMostFirst: String(localized: "Tag Count (Most)")
        }
    }

    func sorted(_ items: [SearchResultItem]) -> [SearchResultItem] {
        items.sorted(by: comparator)
    }

    private func comparator(_ lhs: SearchResultItem, _ rhs: SearchResultItem) -> Bool {
        switch self {
        case .nameAscending:
            return compareDisplayName(lhs, rhs) ?? (lhs.url.path < rhs.url.path)
        case .nameDescending:
            if let nameOrder = compareDisplayName(lhs, rhs) {
                return !nameOrder
            }
            return lhs.url.path < rhs.url.path
        case .modifiedNewestFirst:
            return compareOptionalDate(lhs.contentModificationDate,
                                       rhs.contentModificationDate,
                                       descending: true,
                                       lhs: lhs,
                                       rhs: rhs)
        case .modifiedOldestFirst:
            return compareOptionalDate(lhs.contentModificationDate,
                                       rhs.contentModificationDate,
                                       descending: false,
                                       lhs: lhs,
                                       rhs: rhs)
        case .createdNewestFirst:
            return compareOptionalDate(lhs.creationDate,
                                       rhs.creationDate,
                                       descending: true,
                                       lhs: lhs,
                                       rhs: rhs)
        case .createdOldestFirst:
            return compareOptionalDate(lhs.creationDate,
                                       rhs.creationDate,
                                       descending: false,
                                       lhs: lhs,
                                       rhs: rhs)
        case .sizeLargestFirst:
            return compareOptionalInt(lhs.fileSizeBytes,
                                      rhs.fileSizeBytes,
                                      descending: true,
                                      lhs: lhs,
                                      rhs: rhs)
        case .sizeSmallestFirst:
            return compareOptionalInt(lhs.fileSizeBytes,
                                      rhs.fileSizeBytes,
                                      descending: false,
                                      lhs: lhs,
                                      rhs: rhs)
        case .tagCountFewestFirst:
            let lCount = lhs.tags.count
            let rCount = rhs.tags.count
            if lCount != rCount { return lCount < rCount }
            return compareDisplayName(lhs, rhs) ?? (lhs.url.path < rhs.url.path)
        case .tagCountMostFirst:
            let lCount = lhs.tags.count
            let rCount = rhs.tags.count
            if lCount != rCount { return lCount > rCount }
            return compareDisplayName(lhs, rhs) ?? (lhs.url.path < rhs.url.path)
        }
    }

    private func compareDisplayName(_ lhs: SearchResultItem, _ rhs: SearchResultItem) -> Bool? {
        switch lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) {
        case .orderedAscending:
            true
        case .orderedDescending:
            false
        case .orderedSame:
            nil
        }
    }

    private func compareOptionalDate(_ lhsDate: Date?,
                                     _ rhsDate: Date?,
                                     descending: Bool,
                                     lhs: SearchResultItem,
                                     rhs: SearchResultItem) -> Bool
    {
        switch (lhsDate, rhsDate) {
        case let (left?, right?) where left != right:
            descending ? (left > right) : (left < right)
        case (.some, .none):
            true
        case (.none, .some):
            false
        default:
            compareDisplayName(lhs, rhs) ?? (lhs.url.path < rhs.url.path)
        }
    }

    private func compareOptionalInt(_ lhsValue: Int64?,
                                    _ rhsValue: Int64?,
                                    descending: Bool,
                                    lhs: SearchResultItem,
                                    rhs: SearchResultItem) -> Bool
    {
        switch (lhsValue, rhsValue) {
        case let (left?, right?) where left != right:
            descending ? (left > right) : (left < right)
        case (.some, .none):
            true
        case (.none, .some):
            false
        default:
            compareDisplayName(lhs, rhs) ?? (lhs.url.path < rhs.url.path)
        }
    }
}

enum FinderTagColorOption: Int, CaseIterable, Identifiable {
    case none = 0
    case gray = 1
    case green = 2
    case purple = 3
    case blue = 4
    case yellow = 5
    case red = 6
    case orange = 7

    nonisolated var id: Int {
        rawValue
    }

    nonisolated var title: String {
        switch self {
        case .none: String(localized: "No color")
        case .gray: String(localized: "Gray")
        case .green: String(localized: "Green")
        case .purple: String(localized: "Purple")
        case .blue: String(localized: "Blue")
        case .yellow: String(localized: "Yellow")
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        }
    }

    nonisolated var hexValue: String? {
        switch self {
        case .none: nil
        case .gray: "8E8E93"
        case .green: "32D74B"
        case .purple: "BF5AF2"
        case .blue: "0A84FF"
        case .yellow: "FFD60A"
        case .red: "FF453A"
        case .orange: "FF9F0A"
        }
    }

    nonisolated static func from(hex: String?) -> FinderTagColorOption {
        guard let normalized = FinderTag.normalizedHex(hex) else { return .none }
        return allCases.first(where: { $0.hexValue == normalized }) ?? .none
    }

    nonisolated static func displayName(forHex hex: String?) -> String? {
        guard let normalized = FinderTag.normalizedHex(hex) else { return nil }
        return allCases.first(where: { $0.hexValue == normalized })?.title
    }

    nonisolated static func hex(for index: Int) -> String? {
        FinderTagColorOption(rawValue: index)?.hexValue
    }

    nonisolated static func colorIndex(forHex hex: String?) -> Int? {
        guard let normalized = FinderTag.normalizedHex(hex) else { return nil }
        return allCases.first(where: { $0.hexValue == normalized })?.rawValue
    }

    nonisolated static func colorNameLookup(forDescriptor descriptor: String) -> FinderTagColorOption? {
        switch descriptor.lowercased() {
        case "gray", "grey": .gray
        case "green": .green
        case "purple": .purple
        case "blue": .blue
        case "yellow": .yellow
        case "red": .red
        case "orange": .orange
        default: nil
        }
    }
}

struct FinderTag: Hashable, Identifiable {
    let name: String
    let colorHex: String?
    nonisolated var id: String {
        name
    }

    nonisolated init?(rawValue: String) {
        let components = rawValue.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let nameComponent = components.first else { return nil }
        let trimmedName = nameComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        name = trimmedName

        if components.count == 2 {
            let colorPart = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            colorHex = FinderTag.hexValue(from: colorPart)
        } else {
            colorHex = nil
        }
    }

    nonisolated init(name: String, colorHex: String? = nil) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colorHex {
            self.colorHex = FinderTag.hexValue(from: colorHex)
        } else {
            self.colorHex = nil
        }
    }

    private nonisolated static func hexValue(from descriptor: String) -> String? {
        guard !descriptor.isEmpty else { return nil }

        let candidate = descriptor.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty { return nil }

        if let normalized = normalizedHex(candidate) {
            return normalized
        }

        if let index = Int(candidate),
           let hex = FinderTagColorOption.hex(for: index)
        {
            return hex
        }

        if let color = FinderTagColorOption.colorNameLookup(forDescriptor: candidate) {
            return color.hexValue
        }

        return nil
    }

    nonisolated func metadataRepresentation() -> String {
        if let index = FinderTagColorOption.colorIndex(forHex: colorHex),
           index != FinderTagColorOption.none.rawValue
        {
            return "\(name)\n\(index)"
        }
        return name
    }

    nonisolated static func colorIndex(for hex: String?) -> Int? {
        FinderTagColorOption.colorIndex(forHex: hex)
    }

    nonisolated static func normalizedHex(_ hex: String?) -> String? {
        guard var hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6 else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEFabcdef")
        guard hex.rangeOfCharacter(from: allowed.inverted) == nil else { return nil }
        return hex.uppercased()
    }
}

struct TagAutocompleteEntry: Identifiable, Equatable {
    let id: String
    let displayName: String
    let color: FinderTagColorOption
}

enum TagAutocompleteCatalogBuilder {
    static func catalog(from tags: some Sequence<FinderTag>) -> [String: TagAutocompleteEntry] {
        var catalog: [String: TagAutocompleteEntry] = [:]
        add(tags, into: &catalog)
        return catalog
    }

    static func catalog(from facets: some Sequence<TagFacet>) -> [String: TagAutocompleteEntry] {
        var catalog: [String: TagAutocompleteEntry] = [:]
        add(facets, into: &catalog)
        return catalog
    }

    static func catalog(from results: [SearchResultItem],
                        facets: [TagFacet] = []) -> [String: TagAutocompleteEntry]
    {
        var catalog: [String: TagAutocompleteEntry] = [:]
        add(results, into: &catalog)
        add(facets, into: &catalog)
        return catalog
    }

    static func add(_ tags: some Sequence<FinderTag>,
                    into catalog: inout [String: TagAutocompleteEntry])
    {
        for tag in tags {
            store(name: tag.name, colorHex: tag.colorHex, into: &catalog)
        }
    }

    static func add(_ facets: some Sequence<TagFacet>,
                    into catalog: inout [String: TagAutocompleteEntry])
    {
        for facet in facets {
            store(name: facet.tag, colorHex: facet.colorHex, into: &catalog)
        }
    }

    static func add(_ results: some Sequence<SearchResultItem>,
                    into catalog: inout [String: TagAutocompleteEntry])
    {
        for item in results {
            add(item.tags, into: &catalog)
        }
    }

    private static func store(name: String,
                              colorHex: String?,
                              into catalog: inout [String: TagAutocompleteEntry])
    {
        let normalized = TagAutocompleteLogic.normalizedName(name)
        guard !normalized.isEmpty else { return }

        let color = FinderTagColorOption.from(hex: colorHex)
        if let existing = catalog[normalized] {
            if existing.color == .none, color != .none {
                catalog[normalized] = TagAutocompleteEntry(id: normalized,
                                                           displayName: name,
                                                           color: color)
            }
            return
        }

        catalog[normalized] = TagAutocompleteEntry(id: normalized,
                                                   displayName: name,
                                                   color: color)
    }
}

struct SelectionTagSummary: Identifiable, Equatable {
    let normalizedName: String
    let displayName: String
    let colorHex: String?
    let count: Int

    var id: String {
        normalizedName
    }
}

enum SelectionTagSummaryBuilder {
    static func build(from items: [SearchResultItem]) -> [SelectionTagSummary] {
        struct Bucket {
            var displayName: String
            var colorHex: String?
            var itemIDs: Set<SearchResultItem.ID>
        }

        var buckets: [String: Bucket] = [:]

        for item in items {
            var seenInItem: Set<String> = []

            for tag in item.tags {
                let normalizedName = TagAutocompleteLogic.normalizedName(tag.name)
                guard !normalizedName.isEmpty else { continue }
                guard seenInItem.insert(normalizedName).inserted else { continue }

                let normalizedColor = FinderTag.normalizedHex(tag.colorHex)

                if var existing = buckets[normalizedName] {
                    existing.itemIDs.insert(item.id)
                    // Prefer any explicit color over "no color" when available.
                    if existing.colorHex == nil, let normalizedColor {
                        existing.colorHex = normalizedColor
                        existing.displayName = tag.name
                    }
                    buckets[normalizedName] = existing
                } else {
                    buckets[normalizedName] = Bucket(displayName: tag.name,
                                                     colorHex: normalizedColor,
                                                     itemIDs: [item.id])
                }
            }
        }

        return buckets.map { key, bucket in
            SelectionTagSummary(normalizedName: key,
                                displayName: bucket.displayName,
                                colorHex: bucket.colorHex,
                                count: bucket.itemIDs.count)
        }
        .sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}

enum TagAutocompleteLogic {
    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func exactMatch(for input: String,
                           in catalog: [String: TagAutocompleteEntry]) -> TagAutocompleteEntry?
    {
        catalog[normalizedName(input)]
    }

    static func resolvedColor(for input: String,
                              in catalog: [String: TagAutocompleteEntry],
                              userOverrodeColor: Bool) -> FinderTagColorOption?
    {
        if let entry = exactMatch(for: input, in: catalog) {
            return entry.color
        }
        if userOverrodeColor {
            return nil
        }
        return FinderTagColorOption.none
    }

    static func preferredHighlightedSuggestionID(in suggestions: [TagAutocompleteEntry],
                                                 previousID: String?) -> String?
    {
        guard !suggestions.isEmpty else { return nil }
        if let previousID,
           suggestions.contains(where: { $0.id == previousID })
        {
            return previousID
        }
        return suggestions.first?.id
    }

    static func movedHighlightedSuggestionID(in suggestions: [TagAutocompleteEntry],
                                             currentID: String?,
                                             delta: Int) -> String?
    {
        guard !suggestions.isEmpty else { return nil }
        guard delta != 0 else {
            return preferredHighlightedSuggestionID(in: suggestions, previousID: currentID)
        }

        if let currentID,
           let index = suggestions.firstIndex(where: { $0.id == currentID })
        {
            let count = suggestions.count
            let nextIndex = (index + delta % count + count) % count
            return suggestions[nextIndex].id
        }

        if delta > 0 {
            return suggestions.first?.id
        }
        return suggestions.last?.id
    }

    static func acceptedSuggestion(in suggestions: [TagAutocompleteEntry],
                                   highlightedID: String?) -> TagAutocompleteEntry?
    {
        guard !suggestions.isEmpty else { return nil }
        if let highlightedID,
           let match = suggestions.first(where: { $0.id == highlightedID })
        {
            return match
        }
        return suggestions.first
    }

    static func suggestions(for input: String,
                            in catalog: [String: TagAutocompleteEntry],
                            limit: Int = 5) -> [TagAutocompleteEntry]
    {
        let query = normalizedName(input)
        guard !query.isEmpty else { return [] }

        return catalog.values
            .filter {
                let normalizedDisplayName = normalizedName($0.displayName)
                return normalizedDisplayName.contains(query) && normalizedDisplayName != query
            }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }
}
