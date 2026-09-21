import Foundation

public enum JobStatus: String, Codable, Sendable, Equatable {
    case queued
    case running
    case paused
    case completed
    case failed
    case skipped
}

public enum JobOperation: String, Codable, Sendable, Equatable {
    case conversion
    case metadataEdit
}

public struct ConversionJob: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var sourceURL: URL
    public var destinationURL: URL
    public var profile: MediaProfile
    public var sharedMetadata: VideoMetadataPatch
    public var metadataOverride: VideoMetadataPatch
    public var status: JobStatus
    public var progress: Double
    public var lastError: String?
    public var operation: JobOperation

    private enum CodingKeys: String, CodingKey {
        case id, sourceURL, destinationURL, profile, sharedMetadata, metadataOverride
        case status, progress, lastError, operation
    }

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        destinationURL: URL,
        profile: MediaProfile = .movie,
        sharedMetadata: VideoMetadataPatch = .init(),
        metadataOverride: VideoMetadataPatch = .init(),
        status: JobStatus = .queued,
        progress: Double = 0,
        lastError: String? = nil,
        operation: JobOperation = .conversion
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.profile = profile
        self.sharedMetadata = sharedMetadata
        self.metadataOverride = metadataOverride
        self.status = status
        self.progress = progress
        self.lastError = lastError
        self.operation = operation
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceURL = try container.decode(URL.self, forKey: .sourceURL)
        destinationURL = try container.decode(URL.self, forKey: .destinationURL)
        profile = try container.decode(MediaProfile.self, forKey: .profile)
        sharedMetadata = try container.decode(VideoMetadataPatch.self, forKey: .sharedMetadata)
        metadataOverride = try container.decode(VideoMetadataPatch.self, forKey: .metadataOverride)
        status = try container.decode(JobStatus.self, forKey: .status)
        progress = try container.decode(Double.self, forKey: .progress)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        operation = try container.decodeIfPresent(JobOperation.self, forKey: .operation) ?? .conversion
    }

    public var resolvedMetadata: ResolvedVideoMetadata {
        ResolvedVideoMetadata(
            profile: profile,
            shared: sharedMetadata,
            override: metadataOverride
        )
    }
}
