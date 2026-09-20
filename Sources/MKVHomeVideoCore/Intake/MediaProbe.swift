import Foundation

public enum VideoCodec: String, Codable, Sendable, Equatable {
    case h264
    case hevc
    case unknown

    init(ffprobeName: String) {
        self = Self(rawValue: ffprobeName.lowercased()) ?? .unknown
    }
}

public enum AudioCodec: String, Codable, Sendable, Equatable {
    case aac
    case ac3
    case eac3
    case dts
    case unknown

    init(ffprobeName: String) {
        self = Self(rawValue: ffprobeName.lowercased()) ?? .unknown
    }
}

public enum SubtitleCodec: String, Codable, Sendable, Equatable {
    case subrip
    case ass
    case webVTT
    case pgs
    case unknown

    init(ffprobeName: String) {
        switch ffprobeName.lowercased() {
        case "subrip", "srt": self = .subrip
        case "ass", "ssa": self = .ass
        case "webvtt": self = .webVTT
        case "hdmv_pgs_subtitle", "pgs": self = .pgs
        default: self = .unknown
        }
    }

    var isTextBased: Bool {
        self == .subrip || self == .ass || self == .webVTT
    }
}

public struct VideoStream: Codable, Sendable, Equatable {
    public let codec: VideoCodec

    public init(codec: VideoCodec) {
        self.codec = codec
    }
}

public struct AudioStream: Codable, Sendable, Equatable {
    public let codec: AudioCodec

    public init(codec: AudioCodec) {
        self.codec = codec
    }
}

public struct SubtitleStream: Codable, Sendable, Equatable {
    public let index: Int
    public let codec: SubtitleCodec

    public init(index: Int, codec: SubtitleCodec) {
        self.index = index
        self.codec = codec
    }
}

public struct MediaProbeResult: Codable, Sendable, Equatable {
    public let durationMicroseconds: Int64?
    public let video: [VideoStream]
    public let audio: [AudioStream]
    public let subtitles: [SubtitleStream]

    public init(
        durationMicroseconds: Int64? = nil,
        video: [VideoStream],
        audio: [AudioStream],
        subtitles: [SubtitleStream]
    ) {
        self.durationMicroseconds = durationMicroseconds
        self.video = video
        self.audio = audio
        self.subtitles = subtitles
    }

    public static func decode(json: Data) throws -> MediaProbeResult {
        let document = try JSONDecoder().decode(FFprobeDocument.self, from: json)
        let duration = document.format?.duration.flatMap(Double.init).map { Int64($0 * 1_000_000) }
        let streams = document.streams ?? []
        var subtitleIndex = 0
        let subtitles = streams.compactMap { stream -> SubtitleStream? in
            guard stream.codecType == "subtitle", let codecName = stream.codecName else { return nil }
            defer { subtitleIndex += 1 }
            return SubtitleStream(index: subtitleIndex, codec: SubtitleCodec(ffprobeName: codecName))
        }
        return MediaProbeResult(
            durationMicroseconds: duration,
            video: streams.compactMap { stream in
                guard stream.codecType == "video", let codecName = stream.codecName else { return nil }
                return VideoStream(codec: VideoCodec(ffprobeName: codecName))
            },
            audio: streams.compactMap { stream in
                guard stream.codecType == "audio", let codecName = stream.codecName else { return nil }
                return AudioStream(codec: AudioCodec(ffprobeName: codecName))
            },
            subtitles: subtitles
        )
    }

    private struct FFprobeDocument: Decodable {
        let format: FFprobeFormat?
        let streams: [FFprobeStream]?
    }

    private struct FFprobeFormat: Decodable {
        let duration: String?
    }

    private struct FFprobeStream: Decodable {
        let codecType: String?
        let codecName: String?

        enum CodingKeys: String, CodingKey {
            case codecType = "codec_type"
            case codecName = "codec_name"
        }
    }
}
