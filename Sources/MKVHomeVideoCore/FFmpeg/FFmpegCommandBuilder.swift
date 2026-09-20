import Foundation

public struct FFmpegCommand: Sendable, Equatable {
    public let executableURL: URL
    public let arguments: [String]

    public init(executableURL: URL, arguments: [String]) {
        self.executableURL = executableURL
        self.arguments = arguments
    }
}

public enum FFmpegCommandBuilderError: Error, Sendable, Equatable {
    case invalidFileURL
    case noVideoStream
}

public struct FFmpegCommandBuilder: Sendable {
    public init() {}

    public func makeCommand(
        toolchain: FFmpegToolchain,
        sourceURL: URL,
        outputURL: URL,
        metadata: ResolvedVideoMetadata,
        probe: MediaProbeResult
    ) throws -> FFmpegCommand {
        guard sourceURL.isFileURL, outputURL.isFileURL else {
            throw FFmpegCommandBuilderError.invalidFileURL
        }
        guard !probe.video.isEmpty else {
            throw FFmpegCommandBuilderError.noVideoStream
        }

        var arguments = [
            "-hide_banner", "-n",
            "-i", sourceURL.path,
        ]
        if let artworkURL = metadata.artworkURL {
            arguments += ["-i", artworkURL.path]
        }

        arguments += ["-map", "0:v:0", "-map", "0:a?"]
        for subtitle in probe.subtitles where subtitle.codec.isTextBased {
            arguments += ["-map", "0:s:\(subtitle.index)?"]
        }

        if metadata.artworkURL != nil {
            arguments += [
                "-map", "1:v:0",
                "-c:v:0", "libx264",
                "-c:v:1", "mjpeg",
                "-disposition:v:1", "attached_pic",
            ]
        } else {
            arguments += ["-c:v", "libx264"]
        }

        arguments += [
            "-pix_fmt", "yuv420p",
            "-crf", "18",
            "-c:a", "aac",
            "-b:a", "192k",
        ]
        if probe.subtitles.contains(where: { $0.codec.isTextBased }) {
            arguments += ["-c:s", "mov_text"]
        }
        arguments += [
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "-nostats",
        ]
        arguments += FFmpegMetadataTagMapper.arguments(for: metadata)
        arguments.append(outputURL.path)

        return FFmpegCommand(executableURL: toolchain.ffmpegURL, arguments: arguments)
    }
}
