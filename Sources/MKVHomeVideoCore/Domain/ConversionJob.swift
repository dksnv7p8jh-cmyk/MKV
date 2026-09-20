import Foundation

public enum JobStatus: String, Codable, Sendable, Equatable {
    case queued
    case running
    case paused
    case completed
    case failed
    case skipped
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

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        destinationURL: URL,
        profile: MediaProfile = .movie,
        sharedMetadata: VideoMetadataPatch = .init(),
        metadataOverride: VideoMetadataPatch = .init(),
        status: JobStatus = .queued,
        progress: Double = 0,
        lastError: String? = nil
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
    }

    public var resolvedMetadata: ResolvedVideoMetadata {
        ResolvedVideoMetadata(
            profile: profile,
            shared: sharedMetadata,
            override: metadataOverride
        )
    }
}
