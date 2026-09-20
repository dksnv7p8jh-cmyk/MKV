import Foundation

public struct QueueProject: Codable, Sendable, Equatable {
    public var destinationDirectory: URL?
    public var jobs: [ConversionJob]
    public var savedAt: Date

    public init(
        destinationDirectory: URL? = nil,
        jobs: [ConversionJob] = [],
        savedAt: Date = Date()
    ) {
        self.destinationDirectory = destinationDirectory
        self.jobs = jobs
        self.savedAt = savedAt
    }
}

public enum QueueProjectStoreError: Error, Sendable, Equatable {
    case corruptProject
}

extension QueueProjectStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .corruptProject: "The saved queue was unreadable. A preserved copy was created before starting a new queue."
        }
    }
}

public struct QueueProjectStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = Self.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appending(path: "MKVHomeVideo", directoryHint: .isDirectory)
            .appending(path: "queue.json")
    }

    public func save(_ project: QueueProject) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() throws -> QueueProject {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return QueueProject()
        }

        let decoder = JSONDecoder()
        let decoded: QueueProject
        do {
            decoded = try decoder.decode(QueueProject.self, from: Data(contentsOf: fileURL))
        } catch {
            preserveCorruptProject()
            throw QueueProjectStoreError.corruptProject
        }

        var project = decoded
        project.jobs = project.jobs.map { job in
            guard job.status == .running else { return job }
            var requeued = job
            requeued.status = .queued
            requeued.progress = 0
            requeued.lastError = nil
            return requeued
        }
        return project
    }

    private func preserveCorruptProject() {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let preservedURL = fileURL.deletingLastPathComponent()
            .appending(path: "\(baseName).corrupt-\(stamp)-\(UUID().uuidString).json")
        try? FileManager.default.moveItem(at: fileURL, to: preservedURL)
    }
}
