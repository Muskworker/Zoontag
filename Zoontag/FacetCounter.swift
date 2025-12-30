import Foundation

struct TagFacet: Identifiable, Hashable {
    let tag: String
    let count: Int
    let colorHex: String?
    var id: String { tag }
}

final class FacetCounter {
    /// Compute top tags from the provided results. Optionally sample the first N results.
    func topTags(from results: [SearchResultItem], limit: Int = 50, sample: Int? = 3000) -> [TagFacet] {
        let slice: ArraySlice<SearchResultItem>
        if let sample, results.count > sample {
            slice = results.prefix(sample)
        } else {
            slice = results[...]
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
}
