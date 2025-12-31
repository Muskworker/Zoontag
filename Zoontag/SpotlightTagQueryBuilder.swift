import Foundation

enum SpotlightTagQueryBuilder {
    static let metadataUserTagsAttribute = "kMDItemUserTags"

    static func predicate(include: Set<String>, exclude: Set<String>) -> NSPredicate? {
        var predicates: [NSPredicate] = []

        for tag in include.sorted() {
            predicates.append(NSPredicate(format: "ANY %K BEGINSWITH %@", metadataUserTagsAttribute, tag))
        }

        for tag in exclude.sorted() {
            let predicate = NSPredicate(format: "NOT (ANY %K BEGINSWITH %@)", metadataUserTagsAttribute, tag)
            predicates.append(predicate)
        }

        guard !predicates.isEmpty else { return nil }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    static func queryString(include: Set<String>, exclude: Set<String>) -> String? {
        var clauses: [String] = []

        for tag in include.sorted() {
            clauses.append("\(metadataUserTagsAttribute) == '\(prefixPattern(for: tag))'")
        }

        for tag in exclude.sorted() {
            clauses.append("!(\(metadataUserTagsAttribute) == '\(prefixPattern(for: tag))')")
        }

        guard !clauses.isEmpty else { return nil }
        return clauses.joined(separator: " && ")
    }

    private static func escape(_ tag: String) -> String {
        var escaped = tag.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "'", with: "\\'")
        return escaped
    }

    private static func prefixPattern(for tag: String) -> String {
        return "\(escape(tag))*"
    }
}
