import Foundation
import Testing
@testable import MKVHomeVideoCore

private final class LockIsolated<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storage)
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@Test("progress parser reports the measured fraction at a progress marker")
func parserReportsFraction() {
    var parser = FFmpegProgressParser(totalDurationMicroseconds: 10_000_000)
    let events = parser.feed("out_time_ms=2500000\nprogress=continue\n")

    #expect(events == [.updated(fraction: 0.25)])
}

@Test("partial records wait for their progress marker")
func parserBuffersPartialRecordsUntilProgressMarker() {
    var parser = FFmpegProgressParser(totalDurationMicroseconds: 10_000_000)
    #expect(parser.feed("out_time_ms=2500000\n") == [])
    #expect(parser.feed("progress=continue\n") == [.updated(fraction: 0.25)])
}

@Test("end marker is reported as completion")
func parserReportsCompletion() {
    var parser = FFmpegProgressParser(totalDurationMicroseconds: 1)
    #expect(parser.feed("progress=end\n") == [.completed])
}

private final class RecordingLauncher: @unchecked Sendable, ProcessLaunching {
    let stdoutChunks: [String]
    let stderrChunks: [String]
    let outcome: ProcessOutcome

    init(stdoutChunks: [String], stderrChunks: [String] = [], outcome: ProcessOutcome) {
        self.stdoutChunks = stdoutChunks
        self.stderrChunks = stderrChunks
        self.outcome = outcome
    }

    func run(
        _ command: FFmpegCommand,
        onStdout: @escaping @Sendable (String) -> Void,
        onStderr: @escaping @Sendable (String) -> Void
    ) async throws -> ProcessOutcome {
        stdoutChunks.forEach(onStdout)
        stderrChunks.forEach(onStderr)
        return outcome
    }

    func cancel() {}
}

@Test("runner forwards parsed progress and exposes a cancellation seam")
func runnerForwardsProgress() async throws {
    let launcher = RecordingLauncher(
        stdoutChunks: ["out_time_ms=5000000\nprogress=continue\n"],
        outcome: .succeeded
    )
    let runner = FFmpegProcessRunner(launcher: launcher)
    let events = LockIsolated<[FFmpegProgressEvent]>([])
    let command = FFmpegCommand(
        executableURL: URL(filePath: "/opt/homebrew/bin/ffmpeg"),
        arguments: ["-progress", "pipe:1"]
    )

    let outcome = try await runner.run(command, durationMicroseconds: 10_000_000) { event in
        events.withValue { $0.append(event) }
    }

    #expect(outcome == .succeeded)
    #expect(events.value == [.updated(fraction: 0.5)])
}

@Test("the process runner returns bounded FFmpeg diagnostics on failure")
func runnerReturnsProcessDiagnostic() async throws {
    let command = FFmpegCommand(
        executableURL: URL(filePath: "/bin/sh"),
        arguments: ["-c", "printf 'missing encoder' >&2; exit 7"]
    )

    let outcome = try await FFmpegProcessRunner().run(command, durationMicroseconds: nil) { _ in }

    #expect(outcome == .failed(exitCode: 7, diagnostic: "missing encoder"))
}
