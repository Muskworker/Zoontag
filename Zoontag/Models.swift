import Foundation
import AppKit

struct SearchResultItem: Identifiable, Hashable {
    let url: URL
    let displayName: String
    let tags: [FinderTag]

    var id: URL { url }
    var tagNames: [String] { tags.map(\.name) }

    // Placeholder thumbnail: file icon. We'll swap to QuickLook thumbnails later.
    func iconImage(size: CGFloat = 64) -> NSImage {
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: size, height: size)
        return img
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
}
