import Foundation
import Testing
@testable import MKVHomeVideoCore

extension FFmpegToolchain {
    static let fixture = FFmpegToolchain(
        ffmpegURL: URL(filePath: "/opt/homebrew/bin/ffmpeg"),
        ffprobeURL: URL(filePath: "/opt/homebrew/bin/ffprobe")
    )
}

extension MediaProbeResult {
    static func fixture(
        video: VideoCodec,
        audio: [AudioCodec],
        subtitles: [SubtitleCodec]
    ) -> Self {
        .init(
            durationMicroseconds: 10_000_000,
            video: [.init(codec: video)],
            audio: audio.map { .init(codec: $0) },
            subtitles: subtitles.enumerated().map { .init(index: $0.offset, codec: $0.element) }
        )
    }
}

extension Array where Element == String {
    func containsSubsequence(_ sequence: [String]) -> Bool {
        guard !sequence.isEmpty, sequence.count <= count else { return false }
        return indices.contains { index in
            let remaining = distance(from: index, to: endIndex)
            guard remaining >= sequence.count else { return false }
            return Array(self[index..<index + sequence.count]) == sequence
        }
    }
}

@Test("movie command uses Apple-compatible video, audio, and Home Video tags")
func movieCommandUsesCompatibilityPreset() throws {
    let metadata = ResolvedVideoMetadata(
        profile: .movie,
        shared: .init(title: "Arrival", description: "First contact", genre: "Science Fiction"),
        override: .init()
    )
    let command = try FFmpegCommandBuilder().makeCommand(
        toolchain: .fixture,
        sourceURL: URL(filePath: "/Media/Arrival.mkv"),
        outputURL: URL(filePath: "/Output/Arrival.mp4"),
        metadata: metadata,
        probe: .fixture(video: .h264, audio: [.aac], subtitles: [])
    )

    #expect(command.arguments.contains("libx264"))
    #expect(command.arguments.contains("aac"))
    #expect(command.arguments.contains("-n"))
    #expect(!command.arguments.contains("-y"))
    #expect(command.arguments.contains("+faststart"))
    #expect(command.arguments.containsSubsequence(["-metadata", "media_type=10"]))
    #expect(command.arguments.containsSubsequence(["-metadata", "title=Arrival"]))
}

@Test("text subtitles are mapped while bitmap subtitles are excluded")
func commandMapsOnlyTextSubtitleStreams() throws {
    let metadata = ResolvedVideoMetadata(
        profile: .tvEpisode,
        shared: .init(showName: "Severance", episodeTitle: "Hello, Ms. Cobel"),
        override: .init()
    )
    let command = try FFmpegCommandBuilder().makeCommand(
        toolchain: .fixture,
        sourceURL: URL(filePath: "/Media/show.mkv"),
        outputURL: URL(filePath: "/Output/show.mp4"),
        metadata: metadata,
        probe: .fixture(video: .hevc, audio: [.ac3], subtitles: [.subrip, .pgs])
    )

    #expect(command.arguments.containsSubsequence(["-map", "0:s:0?"]))
    #expect(!command.arguments.contains("0:s:1?"))
    #expect(command.arguments.containsSubsequence(["-c:s", "mov_text"]))
}

@Test("empty optional episode metadata is omitted")
func commandOmitsEmptyOptionalTVMetadata() throws {
    let command = try FFmpegCommandBuilder().makeCommand(
        toolchain: .fixture,
        sourceURL: URL(filePath: "/Media/episode.mkv"),
        outputURL: URL(filePath: "/Output/episode.mp4"),
        metadata: ResolvedVideoMetadata(
            profile: .tvEpisode,
            shared: .init(episodeTitle: "Pilot"),
            override: .init()
        ),
        probe: .fixture(video: .h264, audio: [.aac], subtitles: [])
    )

    #expect(!command.arguments.contains(where: { $0 == "show=" || $0 == "network=" }))
}

@Test("ffprobe subtitle indexes are relative to the subtitle stream selector")
func decodedSubtitleIndexesUseSubtitleOrdinal() throws {
    let json = Data("""
    {
      "format": { "duration": "60.0" },
      "streams": [
        { "codec_type": "video", "codec_name": "h264" },
        { "codec_type": "audio", "codec_name": "aac" },
        { "codec_type": "subtitle", "codec_name": "subrip" },
        { "codec_type": "subtitle", "codec_name": "hdmv_pgs_subtitle" }
      ]
    }
    """.utf8)
    let probe = try MediaProbeResult.decode(json: json)
    let command = try FFmpegCommandBuilder().makeCommand(
        toolchain: .fixture,
        sourceURL: URL(filePath: "/Media/episode.mkv"),
        outputURL: URL(filePath: "/Output/episode.mp4"),
        metadata: ResolvedVideoMetadata(profile: .tvEpisode, shared: .init(episodeTitle: "Pilot"), override: .init()),
        probe: probe
    )

    #expect(command.arguments.containsSubsequence(["-map", "0:s:0?"]))
    #expect(!command.arguments.contains("0:s:2?"))
}
