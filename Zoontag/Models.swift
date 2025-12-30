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

struct FinderTag: Hashable, Identifiable {
    let name: String
    let colorHex: String?
    var id: String { name }

    private static let colorIndexHex: [Int: String] = [
        1: "8E8E93", // gray
        2: "32D74B", // green
        3: "BF5AF2", // purple
        4: "0A84FF", // blue
        5: "FFD60A", // yellow
        6: "FF453A", // red
        7: "FF9F0A"  // orange
    ]

    private static let colorNameHex: [String: String] = [
        "gray": "8E8E93",
        "grey": "8E8E93",
        "green": "32D74B",
        "purple": "BF5AF2",
        "blue": "0A84FF",
        "yellow": "FFD60A",
        "red": "FF453A",
        "orange": "FF9F0A"
    ]

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
        self.name = name
        self.colorHex = colorHex
    }

    private static func hexValue(from descriptor: String) -> String? {
        guard !descriptor.isEmpty else { return nil }

        var candidate = descriptor.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty { return nil }

        if candidate.hasPrefix("#") {
            candidate.removeFirst()
        }

        if candidate.count == 6,
           candidate.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789ABCDEFabcdef").inverted) == nil {
            return candidate.uppercased()
        }

        if let index = Int(candidate),
           let hex = colorIndexHex[index] {
            return hex
        }

        if candidate.unicodeScalars.count == 1,
           let scalar = candidate.unicodeScalars.first {
            let value = Int(scalar.value)
            if let hex = colorIndexHex[value] {
                return hex
            }
        }

        if let hex = colorNameHex[candidate.lowercased()] {
            return hex
        }

        return nil
    }
}
