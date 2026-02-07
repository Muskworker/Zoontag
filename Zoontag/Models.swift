import Foundation
import AppKit

struct SearchResultItem: Identifiable, Hashable {
    let url: URL
    let displayName: String
    let tags: [FinderTag]
    let contentModificationDate: Date?
    let creationDate: Date?
    let fileSizeBytes: Int64?

    init(url: URL,
         displayName: String,
         tags: [FinderTag],
         contentModificationDate: Date? = nil,
         creationDate: Date? = nil,
         fileSizeBytes: Int64? = nil) {
        self.url = url
        self.displayName = displayName
        self.tags = tags
        self.contentModificationDate = contentModificationDate
        self.creationDate = creationDate
        self.fileSizeBytes = fileSizeBytes
    }

    var id: URL { url }
    var tagNames: [String] { tags.map(\.name) }

    // Placeholder thumbnail: file icon. We'll swap to QuickLook thumbnails later.
    func iconImage(size: CGFloat = 64) -> NSImage {
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: size, height: size)
        return img
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nameAscending: return "Name (A-Z)"
        case .nameDescending: return "Name (Z-A)"
        case .modifiedNewestFirst: return "Date Modified (Newest)"
        case .modifiedOldestFirst: return "Date Modified (Oldest)"
        case .createdNewestFirst: return "Date Created (Newest)"
        case .createdOldestFirst: return "Date Created (Oldest)"
        case .sizeLargestFirst: return "Size (Largest)"
        case .sizeSmallestFirst: return "Size (Smallest)"
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
        }
    }

    private func compareDisplayName(_ lhs: SearchResultItem, _ rhs: SearchResultItem) -> Bool? {
        switch lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) {
        case .orderedAscending:
            return true
        case .orderedDescending:
            return false
        case .orderedSame:
            return nil
        }
    }

    private func compareOptionalDate(_ lhsDate: Date?,
                                     _ rhsDate: Date?,
                                     descending: Bool,
                                     lhs: SearchResultItem,
                                     rhs: SearchResultItem) -> Bool {
        switch (lhsDate, rhsDate) {
        case let (left?, right?) where left != right:
            return descending ? (left > right) : (left < right)
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return compareDisplayName(lhs, rhs) ?? (lhs.url.path < rhs.url.path)
        }
    }

    private func compareOptionalInt(_ lhsValue: Int64?,
                                    _ rhsValue: Int64?,
                                    descending: Bool,
                                    lhs: SearchResultItem,
                                    rhs: SearchResultItem) -> Bool {
        switch (lhsValue, rhsValue) {
        case let (left?, right?) where left != right:
            return descending ? (left > right) : (left < right)
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return compareDisplayName(lhs, rhs) ?? (lhs.url.path < rhs.url.path)
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

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return "No color"
        case .gray: return "Gray"
        case .green: return "Green"
        case .purple: return "Purple"
        case .blue: return "Blue"
        case .yellow: return "Yellow"
        case .red: return "Red"
        case .orange: return "Orange"
        }
    }

    var hexValue: String? {
        switch self {
        case .none: return nil
        case .gray: return "8E8E93"
        case .green: return "32D74B"
        case .purple: return "BF5AF2"
        case .blue: return "0A84FF"
        case .yellow: return "FFD60A"
        case .red: return "FF453A"
        case .orange: return "FF9F0A"
        }
    }

    static func from(hex: String?) -> FinderTagColorOption {
        guard let normalized = FinderTag.normalizedHex(hex) else { return .none }
        return allCases.first(where: { $0.hexValue == normalized }) ?? .none
    }

    static func displayName(forHex hex: String?) -> String? {
        guard let normalized = FinderTag.normalizedHex(hex) else { return nil }
        return allCases.first(where: { $0.hexValue == normalized })?.title
    }

    static func hex(for index: Int) -> String? {
        return FinderTagColorOption(rawValue: index)?.hexValue
    }

    static func colorIndex(forHex hex: String?) -> Int? {
        guard let normalized = FinderTag.normalizedHex(hex) else { return nil }
        return allCases.first(where: { $0.hexValue == normalized })?.rawValue
    }

    static func colorNameLookup(forDescriptor descriptor: String) -> FinderTagColorOption? {
        switch descriptor.lowercased() {
        case "gray", "grey": return .gray
        case "green": return .green
        case "purple": return .purple
        case "blue": return .blue
        case "yellow": return .yellow
        case "red": return .red
        case "orange": return .orange
        default: return nil
        }
    }
}

struct FinderTag: Hashable, Identifiable {
    let name: String
    let colorHex: String?
    var id: String { name }

    init?(rawValue: String) {
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

    init(name: String, colorHex: String? = nil) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colorHex {
            self.colorHex = FinderTag.hexValue(from: colorHex)
        } else {
            self.colorHex = nil
        }
    }

    private static func hexValue(from descriptor: String) -> String? {
        guard !descriptor.isEmpty else { return nil }

        let candidate = descriptor.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty { return nil }

        if let normalized = normalizedHex(candidate) {
            return normalized
        }

        if let index = Int(candidate),
           let hex = FinderTagColorOption.hex(for: index) {
            return hex
        }

        if let color = FinderTagColorOption.colorNameLookup(forDescriptor: candidate) {
            return color.hexValue
        }

        return nil
    }

    func metadataRepresentation() -> String {
        if let index = FinderTagColorOption.colorIndex(forHex: colorHex),
           index != FinderTagColorOption.none.rawValue {
            return "\(name)\n\(index)"
        }
        return name
    }

    static func colorIndex(for hex: String?) -> Int? {
        FinderTagColorOption.colorIndex(forHex: hex)
    }

    static func normalizedHex(_ hex: String?) -> String? {
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

struct SelectionTagSummary: Identifiable, Equatable {
    let normalizedName: String
    let displayName: String
    let colorHex: String?
    let count: Int

    var id: String { normalizedName }
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
                           in catalog: [String: TagAutocompleteEntry]) -> TagAutocompleteEntry? {
        catalog[normalizedName(input)]
    }

    static func resolvedColor(for input: String,
                              in catalog: [String: TagAutocompleteEntry],
                              userOverrodeColor: Bool) -> FinderTagColorOption? {
        if let entry = exactMatch(for: input, in: catalog) {
            return entry.color
        }
        if userOverrodeColor {
            return nil
        }
        return FinderTagColorOption.none
    }

    static func preferredHighlightedSuggestionID(in suggestions: [TagAutocompleteEntry],
                                                 previousID: String?) -> String? {
        guard !suggestions.isEmpty else { return nil }
        if let previousID,
           suggestions.contains(where: { $0.id == previousID }) {
            return previousID
        }
        return suggestions.first?.id
    }

    static func movedHighlightedSuggestionID(in suggestions: [TagAutocompleteEntry],
                                             currentID: String?,
                                             delta: Int) -> String? {
        guard !suggestions.isEmpty else { return nil }
        guard delta != 0 else {
            return preferredHighlightedSuggestionID(in: suggestions, previousID: currentID)
        }

        if let currentID,
           let index = suggestions.firstIndex(where: { $0.id == currentID }) {
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
                                   highlightedID: String?) -> TagAutocompleteEntry? {
        guard !suggestions.isEmpty else { return nil }
        if let highlightedID,
           let match = suggestions.first(where: { $0.id == highlightedID }) {
            return match
        }
        return suggestions.first
    }

    static func suggestions(for input: String,
                            in catalog: [String: TagAutocompleteEntry],
                            limit: Int = 5) -> [TagAutocompleteEntry] {
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
