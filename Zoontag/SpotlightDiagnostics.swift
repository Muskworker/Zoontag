import Foundation

enum SpotlightDiagnostics {
    static func failureMessage(for scopes: [URL]) -> String {
        let desc = scopes.map(\.path).joined(separator: ", ")
        let indexingSummary = summarizeSpotlightIndexing(for: scopes)

        if indexingSummary.serverDisabled || (!indexingSummary.disabled.isEmpty && indexingSummary.enabled.isEmpty) {
            return """
            Failed to start Spotlight query for \(desc).
            Spotlight indexing appears to be disabled. Open System Settings ▸ Siri & Spotlight or run `sudo mdutil -i on /` to enable indexing, then try again.
            """
        }

        if !indexingSummary.disabled.isEmpty {
            let disabledPaths = indexingSummary.disabled.map(\.path).joined(separator: ", ")
            return """
            Failed to start Spotlight query for \(desc).
            Spotlight indexing is turned off for: \(disabledPaths).
            Enable indexing for those folders in System Settings ▸ Siri & Spotlight or via `sudo mdutil -i on <path>`, then try again.
            """
        }

        var message = """
        Failed to start Spotlight query for \(desc).
        Spotlight indexing looks enabled, so macOS likely denied Zoontag permission to read the selected folder. Re-pick it or grant Zoontag Full Disk Access (System Settings ▸ Privacy & Security ▸ Full Disk Access), then retry.
        """

        if !indexingSummary.unknown.isEmpty {
            let unknownPaths = indexingSummary.unknown.map(\.0.path).joined(separator: ", ")
            message += "\nCould not verify indexing for: \(unknownPaths)."
        }

        return message
    }

    static func fallbackScopes(for urls: [URL]) -> [Any]? {
        var scopes: [Any] = []
        var addedFallback = false

        for url in urls {
            if url.isEntireDiskScope {
                addedFallback = true
                if !scopes.contains(where: { ($0 as? String) == NSMetadataQueryLocalComputerScope }) {
                    scopes.append(NSMetadataQueryLocalComputerScope)
                }
            } else {
                scopes.append(url.resolvingSymlinksInPath().path)
            }
        }

        return addedFallback ? scopes : nil
    }

    private static func summarizeSpotlightIndexing(for scopes: [URL]) -> SpotlightIndexingSummary {
        var summary = SpotlightIndexingSummary()
        let uniqueScopes = Array(Set(scopes.map { $0.resolvingSymlinksInPath() }))

        for scope in uniqueScopes {
            switch checkSpotlightIndexing(at: scope) {
            case .enabled:
                summary.enabled.append(scope)
            case .disabled:
                summary.disabled.append(scope)
            case .serverDisabled:
                summary.serverDisabled = true
            case .unknown(let detail):
                summary.unknown.append((scope, detail))
            }
        }

        return summary
    }

    private static func checkSpotlightIndexing(at scope: URL) -> SpotlightIndexingState {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdutil")
        task.arguments = ["-s", scope.path]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            return .unknown("mdutil failed: \(error.localizedDescription)")
        }
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return .unknown(nil)
        }

        if output.localizedCaseInsensitiveContains("Spotlight server is disabled") {
            return .serverDisabled
        }
        if output.localizedCaseInsensitiveContains("Indexing disabled") {
            return .disabled
        }
        if output.localizedCaseInsensitiveContains("Indexing enabled") {
            return .enabled
        }

        return .unknown(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private struct SpotlightIndexingSummary {
    var enabled: [URL] = []
    var disabled: [URL] = []
    var unknown: [(URL, String?)] = []
    var serverDisabled: Bool = false
}

private enum SpotlightIndexingState {
    case enabled
    case disabled
    case serverDisabled
    case unknown(String?)
}

private extension URL {
    var isEntireDiskScope: Bool {
        let resolvedPath = resolvingSymlinksInPath().standardizedFileURL.path
        return resolvedPath == "/" || resolvedPath == "/System/Volumes/Data"
    }
}
