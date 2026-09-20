import Foundation
import Testing
@testable import MKVHomeVideoCore

@Test("per-job metadata overrides shared movie values")
func overrideWinsOverSharedValue() {
    let shared = VideoMetadataPatch(title: "Shared title", genre: "Drama")
    let override = VideoMetadataPatch(title: "Arrival")

    let resolved = ResolvedVideoMetadata(
        profile: .movie,
        shared: shared,
        override: override
    )

    #expect(resolved.title == "Arrival")
    #expect(resolved.genre == "Drama")
    #expect(resolved.mediaKind == .homeVideo)
}

@Test("episode metadata retains sorting values")
func episodeMetadataRetainsOrdering() {
    let metadata = ResolvedVideoMetadata(
        profile: .tvEpisode,
        shared: .init(showName: "Severance", seasonNumber: 2),
        override: .init(episodeTitle: "Hello, Ms. Cobel", episodeNumber: 1)
    )

    #expect(metadata.showName == "Severance")
    #expect(metadata.seasonNumber == 2)
    #expect(metadata.episodeNumber == 1)
}

@Test("an explicit field clear wins over a shared metadata value")
func explicitClearWinsOverSharedValue() {
    let resolved = ResolvedVideoMetadata(
        profile: .movie,
        shared: .init(title: "Shared title"),
        override: .init(clearedFields: [.title])
    )

    #expect(resolved.title == nil)
}

@Test("a queued job round-trips through Codable")
func conversionJobRoundTrips() throws {
    let original = ConversionJob(
        sourceURL: URL(filePath: "/Movies/Arrival.mkv"),
        destinationURL: URL(filePath: "/Output/Arrival.mp4")
    )
    let decoded = try JSONDecoder().decode(
        ConversionJob.self,
        from: JSONEncoder().encode(original)
    )

    #expect(decoded == original)
}
