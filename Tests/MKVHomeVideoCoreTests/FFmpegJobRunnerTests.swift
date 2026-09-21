import Foundation
import Testing
@testable import MKVHomeVideoCore

private struct FixedProber: MediaProbing {
    let result: MediaProbeResult

    func probe(sourceURL: URL, ffprobeURL: URL) async throws -> MediaProbeResult {
        result
    }
}

private actor RecordingCommandRunner: FFmpegCommandRunning {
    private(set) var command: FFmpegCommand?

    func run(
        _ command: FFmpegCommand,
        durationMicroseconds: Int64?,
        onProgress: @escaping @Sendable (FFmpegProgressEvent) -> Void
    ) async -> ProcessOutcome {
        self.command = command
        onProgress(.updated(fraction: 0.5))
        return .succeeded
    }
}

private actor MetadataWritingCommandRunner: FFmpegCommandRunning {
    func run(
        _ command: FFmpegCommand,
        durationMicroseconds: Int64?,
        onProgress: @escaping @Sendable (FFmpegProgressEvent) -> Void
    ) async throws -> ProcessOutcome {
        try Data("edited metadata".utf8).write(to: URL(filePath: try #require(command.arguments.last)))
        onProgress(.completed)
        return .succeeded
    }
}

@Test("job runner probes source and passes Apple-compatible command to FFmpeg")
func jobRunnerBuildsAndRunsCommand() async {
    let commandRunner = RecordingCommandRunner()
    let runner = FFmpegJobRunner(
        toolchain: .fixture,
        prober: FixedProber(result: .init(
            durationMicroseconds: 10_000_000,
            video: [.init(codec: .h264)],
            audio: [.init(codec: .aac)],
            subtitles: []
        )),
        commandRunner: commandRunner
    )
    var job = ConversionJob(
        sourceURL: URL(filePath: "/Media/Arrival.mkv"),
        destinationURL: URL(filePath: "/Output/Arrival.mp4")
    )
    job.sharedMetadata = .init(title: "Arrival", genre: "Science Fiction")
    let events = LockedEvents()

    let outcome = await runner.run(job) { events.append($0) }
    let command = await commandRunner.command

    #expect(outcome == .succeeded)
    #expect(command?.arguments.containsSubsequence(["-metadata", "title=Arrival"]) == true)
    #expect(events.value == [.updated(fraction: 0.5)])
}

@Test("job runner refuses to replace an output that appears before execution")
func jobRunnerRefusesExistingOutput() async throws {
    let output = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
    FileManager.default.createFile(atPath: output.path, contents: Data())
    defer { try? FileManager.default.removeItem(at: output) }
    let commandRunner = RecordingCommandRunner()
    let runner = FFmpegJobRunner(
        toolchain: .fixture,
        prober: FixedProber(result: .init(durationMicroseconds: 1, video: [.init(codec: .h264)], audio: [], subtitles: [])),
        commandRunner: commandRunner
    )
    let job = ConversionJob(sourceURL: URL(filePath: "/Media/Arrival.mkv"), destinationURL: output)

    let outcome = await runner.run(job) { _ in }

    #expect(outcome == .failed(exitCode: -2, diagnostic: "Output already exists: \(output.path)"))
    #expect(await commandRunner.command == nil)
}

@Test("metadata edit replaces its source only after the temporary output succeeds")
func metadataEditReplacesOriginalAfterSuccessfulWrite() async throws {
    let source = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
    try Data("original metadata".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: source) }
    let runner = FFmpegJobRunner(
        toolchain: .fixture,
        commandRunner: MetadataWritingCommandRunner()
    )
    let job = ConversionJob(sourceURL: source, destinationURL: source, operation: .metadataEdit)

    let outcome = await runner.run(job) { _ in }

    #expect(outcome == .succeeded)
    #expect(try Data(contentsOf: source) == Data("edited metadata".utf8))
}

private final class ToolchainRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: FFmpegToolchain?

    func record(_ toolchain: FFmpegToolchain) {
        lock.lock()
        defer { lock.unlock() }
        storage = toolchain
    }

    var value: FFmpegToolchain? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private struct SuccessfulConversionRunner: ConversionRunning {
    func run(
        _ job: ConversionJob,
        onProgress: @escaping @Sendable (FFmpegProgressEvent) -> Void
    ) async -> ProcessOutcome {
        .succeeded
    }
}

@Test("selected toolchain is the toolchain used for conversion")
func selectedToolchainDrivesConversion() async {
    let selected = FFmpegToolchain(
        ffmpegURL: URL(filePath: "/custom/bin/ffmpeg"),
        ffprobeURL: URL(filePath: "/custom/bin/ffprobe")
    )
    let recorder = ToolchainRecorder()
    let runner = ToolchainConversionRunner(toolchain: selected) { toolchain in
        recorder.record(toolchain)
        return SuccessfulConversionRunner()
    }
    let job = ConversionJob(
        sourceURL: URL(filePath: "/Media/Arrival.mkv"),
        destinationURL: URL(filePath: "/Exports/Arrival.mp4")
    )

    let outcome = await runner.run(job) { _ in }

    #expect(outcome == .succeeded)
    #expect(recorder.value == selected)
}

private final class LockedEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [FFmpegProgressEvent] = []

    func append(_ event: FFmpegProgressEvent) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    var value: [FFmpegProgressEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}
