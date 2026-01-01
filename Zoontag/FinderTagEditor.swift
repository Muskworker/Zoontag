import Foundation
import CoreServices
import Darwin

enum FinderTagEditorError: LocalizedError {
    case invalidFileURL
    case decodingFailed
    case encodingFailed
    case attributeOperationFailed(errno: Int32)
    case insufficientTagMetadata

    var errorDescription: String? {
        switch self {
        case .invalidFileURL:
            return "Invalid file URL."
        case .decodingFailed:
            return "Could not decode Finder tags."
        case .encodingFailed:
            return "Could not encode Finder tags."
        case .attributeOperationFailed(let code):
            if let cString = strerror(code) {
                return String(cString: cString)
            }
            return "Unknown file attribute error."
        case .insufficientTagMetadata:
            return "macOS did not expose full Finder tag metadata for this file."
        }
    }
}

enum FinderTagEditor {
    private static let attributeName = "com.apple.metadata:_kMDItemUserTags"
    private static let metadataAttributeKey: CFString = "kMDItemUserTags" as CFString

    @discardableResult
    static func addTag(_ tag: FinderTag, to url: URL) throws -> [FinderTag] {
        var payload = try rawTagPayload(for: url)
        try ensureWritable(for: payload)

        if let match = existingTag(named: tag.name, in: payload.values) {
            let current = match.tag
            if current.colorHex == tag.colorHex {
                return payload.values.compactMap(FinderTag.init(rawValue:))
            }
            payload.values[match.index] = FinderTag(name: current.name, colorHex: tag.colorHex).metadataRepresentation()
            try write(payload.values, to: url)
            return payload.values.compactMap(FinderTag.init(rawValue:))
        }

        payload.values.append(tag.metadataRepresentation())
        try write(payload.values, to: url)
        return payload.values.compactMap(FinderTag.init(rawValue:))
    }

    @discardableResult
    static func removeTag(named name: String, from url: URL) throws -> [FinderTag] {
        var payload = try rawTagPayload(for: url)
        try ensureWritable(for: payload)

        let originalCount = payload.values.count
        payload.values.removeAll { matches($0, name: name) }
        if payload.values.count == originalCount {
            return payload.values.compactMap(FinderTag.init(rawValue:))
        }
        try write(payload.values, to: url)
        return payload.values.compactMap(FinderTag.init(rawValue:))
    }

    static func currentTags(for url: URL) throws -> [FinderTag] {
        let payload = try rawTagPayload(for: url)
        return payload.values.compactMap(FinderTag.init(rawValue:))
    }
}

private extension FinderTagEditor {
    struct TagPayload {
        var values: [String]
        var source: TagSource
    }

    enum TagSource {
        case extendedAttribute
        case metadata
        case resourceValues
        case none
    }

    static func matches(_ raw: String, name: String) -> Bool {
        guard let parsed = FinderTag(rawValue: raw) else { return false }
        return parsed.name.caseInsensitiveCompare(name) == .orderedSame
    }

    static func existingTag(named name: String, in values: [String]) -> (index: Int, tag: FinderTag)? {
        for (idx, entry) in values.enumerated() {
            guard let parsed = FinderTag(rawValue: entry) else { continue }
            if parsed.name.caseInsensitiveCompare(name) == .orderedSame {
                return (idx, parsed)
            }
        }
        return nil
    }

    static func ensureWritable(for payload: TagPayload) throws {
        if payload.source == .resourceValues && !payload.values.isEmpty {
            throw FinderTagEditorError.insufficientTagMetadata
        }
    }

    static func rawTagPayload(for url: URL) throws -> TagPayload {
        if let data = try readExtendedAttribute(name: attributeName, url: url),
           let decoded = try decodeTagList(from: data) {
            return TagPayload(values: decoded, source: .extendedAttribute)
        }
        if let metadata = metadataTagValues(for: url) {
            return TagPayload(values: metadata, source: .metadata)
        }
        if let resourceValues = try? url.resourceValues(forKeys: [.tagNamesKey]),
           let tagNames = resourceValues.tagNames {
            return TagPayload(values: tagNames, source: .resourceValues)
        }
        return TagPayload(values: [], source: .none)
    }

    static func metadataTagValues(for url: URL) -> [String]? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
              let tags = MDItemCopyAttribute(item, metadataAttributeKey) as? [String],
              !tags.isEmpty else { return nil }
        return tags
    }

    static func decodeTagList(from data: Data) throws -> [String]? {
        do {
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            return plist as? [String]
        } catch {
            throw FinderTagEditorError.decodingFailed
        }
    }

    static func write(_ values: [String], to url: URL) throws {
        if values.isEmpty {
            try removeExtendedAttribute(name: attributeName, url: url)
            return
        }
        let data: Data
        do {
            data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        } catch {
            throw FinderTagEditorError.encodingFailed
        }
        try setExtendedAttribute(name: attributeName, data: data, url: url)
    }

    static func readExtendedAttribute(name: String, url: URL) throws -> Data? {
        return try url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { throw FinderTagEditorError.invalidFileURL }
            let size = getxattr(path, name, nil, 0, 0, 0)
            if size == -1 {
                if errno == ENOATTR {
                    return nil
                }
                throw FinderTagEditorError.attributeOperationFailed(errno: errno)
            }
            var data = Data(count: Int(size))
            let result = data.withUnsafeMutableBytes { buffer in
                getxattr(path, name, buffer.baseAddress, buffer.count, 0, 0)
            }
            if result == -1 {
                throw FinderTagEditorError.attributeOperationFailed(errno: errno)
            }
            return data
        }
    }

    static func setExtendedAttribute(name: String, data: Data, url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw FinderTagEditorError.invalidFileURL }
            let result = data.withUnsafeBytes { buffer in
                setxattr(path, name, buffer.baseAddress, buffer.count, 0, 0)
            }
            if result == -1 {
                throw FinderTagEditorError.attributeOperationFailed(errno: errno)
            }
        }
    }

    static func removeExtendedAttribute(name: String, url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw FinderTagEditorError.invalidFileURL }
            let result = removexattr(path, name, 0)
            if result == -1 && errno != ENOATTR {
                throw FinderTagEditorError.attributeOperationFailed(errno: errno)
            }
        }
    }
}
