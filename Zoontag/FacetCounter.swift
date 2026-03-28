import Foundation

struct TagFacet: Identifiable, Hashable {
    let tag: String
    let count: Int
    let colorHex: String?
    var id: String {
        tag
    }
}

/// One row in the "File type" sidebar section — a distinct file kind and how many
/// results carry that kind in the current result set.
struct FileTypeFacet: Identifiable, Hashable {
    let fileType: String
    let count: Int
    var id: String {
        fileType
    }
}

final class FacetCounter {
    /// Compute top tags from the provided results. Optionally sample the first N results.
    func topTags(from results: [SearchResultItem], limit: Int = 50, sample: Int? = 3000) -> [TagFacet] {
        let slice: ArraySlice<SearchResultItem> = if let sample, results.count > sample {
            results.prefix(sample)
        } else {
            results[...]
        }

        var counts: [String: (count: Int, colorHex: String?)] = [:]
        counts.reserveCapacity(256)

        for item in slice {
            for tag in item.tags {
                var entry = counts[tag.name] ?? (0, nil)
                entry.count += 1
                if entry.colorHex == nil {
                    entry.colorHex = tag.colorHex
                }
                counts[tag.name] = entry
            }
        }

        return counts
            .map { TagFacet(tag: $0.key, count: $0.value.count, colorHex: $0.value.colorHex) }
            .sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                return a.tag.localizedCaseInsensitiveCompare(b.tag) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Compute the top file kinds from the provided results.
    /// Counts are based on each item's `fileKind` string; items with no `fileKind` are skipped.
    func topFileTypes(from results: [SearchResultItem], limit: Int = 50) -> [FileTypeFacet] {
        var counts: [String: Int] = [:]
        counts.reserveCapacity(64)

        for item in results {
            guard let kind = item.fileKind else { continue }
            counts[kind, default: 0] += 1
        }

        return counts
            .map { FileTypeFacet(fileType: $0.key, count: $0.value) }
            .sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                return a.fileType.localizedCaseInsensitiveCompare(b.fileType) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }
}
