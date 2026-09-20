import Foundation

public enum OutputPathResolverError: Error, Equatable {
    case destinationIsNotDirectory
    case emptyBaseName
}

public enum OutputPathResolver {
    public static func uniqueOutputURL(
        sourceURL: URL,
        destinationDirectory: URL,
        preferredBaseName: String,
        existingURLs: [URL]
    ) throws -> URL {
        guard destinationDirectory.isFileURL, destinationDirectory.hasDirectoryPath else {
            throw OutputPathResolverError.destinationIsNotDirectory
        }

        let baseName = normalizedBaseName(from: preferredBaseName)
        guard !baseName.isEmpty else {
            throw OutputPathResolverError.emptyBaseName
        }

        let reserved = Set((existingURLs + [sourceURL]).map(normalizedPath))
        var index = 1

        while true {
            let suffix = index == 1 ? "" : " \(index)"
            let candidate = destinationDirectory
                .appending(path: "\(baseName)\(suffix).mp4", directoryHint: .notDirectory)
            if !reserved.contains(normalizedPath(candidate)) {
                return candidate
            }
            index += 1
        }
    }

    private static func normalizedBaseName(from value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.lowercased().hasSuffix(".mkv") || result.lowercased().hasSuffix(".mp4") {
            result = String(result.dropLast(4))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path.lowercased()
    }
}
