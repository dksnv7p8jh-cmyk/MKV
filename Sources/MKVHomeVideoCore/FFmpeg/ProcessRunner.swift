@preconcurrency import Foundation

public enum ProcessOutcome: Sendable, Equatable {
    case succeeded
    case failed(exitCode: Int32, diagnostic: String? = nil)
    case cancelled
}

public protocol ProcessLaunching: Sendable {
    func run(
        _ command: FFmpegCommand,
        onStdout: @escaping @Sendable (String) -> Void,
        onStderr: @escaping @Sendable (String) -> Void
    ) async throws -> ProcessOutcome
    func cancel()
}

public final class FoundationProcessLauncher: @unchecked Sendable, ProcessLaunching {
    private let state = ProcessState()

    public init() {}

    public func run(
        _ command: FFmpegCommand,
        onStdout: @escaping @Sendable (String) -> Void,
        onStderr: @escaping @Sendable (String) -> Void
    ) async throws -> ProcessOutcome {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let diagnostics = BoundedDiagnostic()
        let stderrReadGroup = DispatchGroup()
        stderrReadGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let chunk = String(decoding: data, as: UTF8.self)
            diagnostics.append(chunk)
            if !chunk.isEmpty {
                onStderr(chunk)
            }
            stderrReadGroup.leave()
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            onStdout(String(decoding: data, as: UTF8.self))
        }
        state.begin(process)
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { [state] completedProcess in
                stdout.fileHandleForReading.readabilityHandler = nil
                let remainingStdout = stdout.fileHandleForReading.readDataToEndOfFile()
                if !remainingStdout.isEmpty {
                    onStdout(String(decoding: remainingStdout, as: UTF8.self))
                }
                stderrReadGroup.notify(queue: .global(qos: .userInitiated)) {
                    let outcome = state.finish(completedProcess, diagnostic: diagnostics.value)
                    continuation.resume(returning: outcome)
                }
            }

            do {
                try process.run()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                state.clear(process)
                stderr.fileHandleForWriting.closeFile()
                continuation.resume(returning: .failed(exitCode: -1, diagnostic: error.localizedDescription))
            }
        }
    }

    public func cancel() {
        state.cancelCurrentProcess()
    }
}

public final class FFmpegProcessRunner: @unchecked Sendable {
    private let launcher: any ProcessLaunching

    public init(launcher: any ProcessLaunching = FoundationProcessLauncher()) {
        self.launcher = launcher
    }

    public func run(
        _ command: FFmpegCommand,
        durationMicroseconds: Int64?,
        onProgress: @escaping @Sendable (FFmpegProgressEvent) -> Void
    ) async throws -> ProcessOutcome {
        let parser = ProgressBox(totalDurationMicroseconds: durationMicroseconds)
        return try await launcher.run(
            command,
            onStdout: { chunk in parser.feed(chunk).forEach(onProgress) },
            onStderr: { _ in }
        )
    }

    public func cancel() {
        launcher.cancel()
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var parser: FFmpegProgressParser

    init(totalDurationMicroseconds: Int64?) {
        parser = FFmpegProgressParser(totalDurationMicroseconds: totalDurationMicroseconds)
    }

    func feed(_ chunk: String) -> [FFmpegProgressEvent] {
        lock.lock()
        defer { lock.unlock() }
        return parser.feed(chunk)
    }
}

private final class ProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var wasCancelled = false

    func begin(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        self.process = process
        wasCancelled = false
    }

    func cancelCurrentProcess() {
        lock.lock()
        let currentProcess = process
        wasCancelled = true
        lock.unlock()
        currentProcess?.terminate()
    }

    func finish(_ completedProcess: Process, diagnostic: String?) -> ProcessOutcome {
        lock.lock()
        defer { lock.unlock() }
        let outcome: ProcessOutcome
        if wasCancelled {
            outcome = .cancelled
        } else if completedProcess.terminationStatus == 0 {
            outcome = .succeeded
        } else {
            outcome = .failed(exitCode: completedProcess.terminationStatus, diagnostic: diagnostic)
        }
        process = nil
        wasCancelled = false
        return outcome
    }

    func clear(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        if self.process === process {
            self.process = nil
            wasCancelled = false
        }
    }
}

private final class BoundedDiagnostic: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    private let maximumLength = 4_096

    func append(_ chunk: String) {
        lock.lock()
        defer { lock.unlock() }
        text += chunk
        if text.count > maximumLength {
            text = String(text.suffix(maximumLength))
        }
    }

    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
