import Foundation
import AppKit

struct SearchResultItem: Identifiable, Hashable {
    let url: URL
    let displayName: String
    let tags: [String]

    var id: URL { url }

    // Placeholder thumbnail: file icon. We'll swap to QuickLook thumbnails later.
    func iconImage(size: CGFloat = 64) -> NSImage {
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: size, height: size)
        return img
    }
}
