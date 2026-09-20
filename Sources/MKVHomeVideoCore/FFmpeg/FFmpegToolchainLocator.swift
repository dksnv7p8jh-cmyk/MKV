import Foundation

public struct FFmpegToolchain: Sendable, Equatable {
    public let ffmpegURL: URL
    public let ffprobeURL: URL

    public init(ffmpegURL: URL, ffprobeURL: URL) {
        self.ffmpegURL = ffmpegURL
        self.ffprobeURL = ffprobeURL
    }
}

public enum FFmpegToolchainLocatorError: Error, Sendable, Equatable {
    case notInstalled(setupCommand: String)
    case customPathMissingSiblingProbe
}

public enum FFmpegToolchainLocator {
    public static let setupCommand = "brew install ffmpeg"

    public static func toolchain(
        customFFmpegURL: URL?,
        executablePaths: [String]
    ) throws -> FFmpegToolchain {
        let availablePaths = Set(executablePaths.map {
            URL(filePath: $0).standardizedFileURL.path
        })

        if let customFFmpegURL {
            let ffmpegURL = customFFmpegURL.standardizedFileURL
            let ffprobeURL = ffmpegURL.deletingLastPathComponent().appending(path: "ffprobe")
            guard availablePaths.contains(ffmpegURL.path), availablePaths.contains(ffprobeURL.path) else {
                throw FFmpegToolchainLocatorError.customPathMissingSiblingProbe
            }
            return FFmpegToolchain(ffmpegURL: ffmpegURL, ffprobeURL: ffprobeURL)
        }

        let directories = ["/opt/homebrew/bin", "/usr/local/bin"]
            + pathDirectories(from: executablePaths)
        for directory in directories {
            let ffmpegURL = URL(filePath: directory).appending(path: "ffmpeg")
            let ffprobeURL = URL(filePath: directory).appending(path: "ffprobe")
            if availablePaths.contains(ffmpegURL.path), availablePaths.contains(ffprobeURL.path) {
                return FFmpegToolchain(ffmpegURL: ffmpegURL, ffprobeURL: ffprobeURL)
            }
        }

        throw FFmpegToolchainLocatorError.notInstalled(setupCommand: setupCommand)
    }

    public static func locate(
        customFFmpegURL: URL? = nil,
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
        fileManager: FileManager = .default
    ) throws -> FFmpegToolchain {
        if let customFFmpegURL {
            let ffmpegURL = customFFmpegURL.standardizedFileURL
            let ffprobeURL = ffmpegURL.deletingLastPathComponent().appending(path: "ffprobe")
            let executablePaths = [ffmpegURL, ffprobeURL]
                .filter { fileManager.isExecutableFile(atPath: $0.path) }
                .map(\.path)
            return try toolchain(customFFmpegURL: ffmpegURL, executablePaths: executablePaths)
        }
        let directories = ["/opt/homebrew/bin", "/usr/local/bin"]
            + (environmentPath?.split(separator: ":").map(String.init) ?? [])
        let executablePaths = directories.flatMap { directory in
            ["\(directory)/ffmpeg", "\(directory)/ffprobe"]
        }.filter(fileManager.isExecutableFile(atPath:))

        return try toolchain(customFFmpegURL: customFFmpegURL, executablePaths: executablePaths)
    }

    private static func pathDirectories(from executablePaths: [String]) -> [String] {
        executablePaths.map { URL(filePath: $0).deletingLastPathComponent().path }
    }
}
