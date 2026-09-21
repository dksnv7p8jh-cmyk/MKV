@preconcurrency import Foundation

public protocol MediaProbing: Sendable {
    func probe(sourceURL: URL, ffprobeURL: URL) async throws -> MediaProbeResult
}

public protocol FFmpegCommandRunning: Sendable {
    func run(
        _ command: FFmpegCommand,
        durationMicroseconds: Int64?,
        onProgress: @escaping @Sendable (FFmpegProgressEvent) -> Void
    ) async throws -> ProcessOutcome
}

extension FFmpegProcessRunner: FFmpegCommandRunning {}

public struct FFprobeRunner: MediaProbing {
    public init() {}

    public func probe(sourceURL: URL, ffprobeURL: URL) async throws -> MediaProbeResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = ffprobeURL
            process.arguments = [
                "-v", "error",
                "-show_entries", "format=duration:stream=codec_type,codec_name",
                "-of", "json",
                sourceURL.path,
            ]
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw FFprobeRunnerError.failed(exitCode: process.terminationStatus)
            }
            return try MediaProbeResult.decode(json: data)
        }.value
    }
}

public enum FFprobeRunnerError: Error, Sendable, Equatable {
    case failed(exitCode: Int32)
}

public final class FFmpegJobRunner: @unchecked Sendable, ConversionRunning {
    private let toolchain: FFmpegToolchain
    private let prober: any MediaProbing
    private let commandRunner: any FFmpegCommandRunning
    private let commandBuilder: FFmpegCommandBuilder
    private let fileManager: FileManager

    public init(
        toolchain: FFmpegToolchain,
        prober: any MediaProbing = FFprobeRunner(),
        commandRunner: any FFmpegCommandRunning = FFmpegProcessRunner(),
        commandBuilder: FFmpegCommandBuilder = FFmpegCommandBuilder(),
        fileManager: FileManager = .default
    ) {
        self.toolchain = toolchain
        self.prober = prober
        self.commandRunner = commandRunner
        self.commandBuilder = commandBuilder
        self.fileManager = fileManager
    }

    public func run(
        _ job: ConversionJob,
        onProgress: @escaping @Sendable (FFmpegProgressEvent) -> Void
    ) async -> ProcessOutcome {
        do {
            if job.operation == .metadataEdit {
                return try await editMetadata(job, onProgress: onProgress)
            }
            guard !fileManager.fileExists(atPath: job.destinationURL.path) else {
                throw FFmpegJobRunnerError.outputAlreadyExists(job.destinationURL)
            }
            let probe = try await prober.probe(sourceURL: job.sourceURL, ffprobeURL: toolchain.ffprobeURL)
            let command = try commandBuilder.makeCommand(
                toolchain: toolchain,
                sourceURL: job.sourceURL,
                outputURL: job.destinationURL,
                metadata: job.resolvedMetadata,
                probe: probe
            )
            return try await commandRunner.run(
                command,
                durationMicroseconds: probe.durationMicroseconds,
                onProgress: onProgress
            )
        } catch let error as FFmpegJobRunnerError {
            return .failed(exitCode: -2, diagnostic: error.errorDescription)
        } catch {
            let diagnostic = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return .failed(exitCode: -1, diagnostic: diagnostic)
        }
    }

    private func editMetadata(
        _ job: ConversionJob,
        onProgress: @escaping @Sendable (FFmpegProgressEvent) -> Void
    ) async throws -> ProcessOutcome {
        guard fileManager.fileExists(atPath: job.sourceURL.path) else {
            throw FFmpegJobRunnerError.sourceMissing(job.sourceURL)
        }
        let temporaryOutput = job.sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent(".metadata-edit-\(UUID().uuidString).mp4")
        defer { try? fileManager.removeItem(at: temporaryOutput) }

        let command = try commandBuilder.makeMetadataEditCommand(
            toolchain: toolchain,
            sourceURL: job.sourceURL,
            outputURL: temporaryOutput,
            metadata: job.resolvedMetadata
        )
        let outcome = try await commandRunner.run(
            command,
            durationMicroseconds: nil,
            onProgress: onProgress
        )
        guard outcome == .succeeded else { return outcome }
        do {
            _ = try fileManager.replaceItemAt(job.sourceURL, withItemAt: temporaryOutput)
            return .succeeded
        } catch {
            throw FFmpegJobRunnerError.unableToReplaceSource(job.sourceURL)
        }
    }
}

public enum FFmpegJobRunnerError: LocalizedError, Sendable, Equatable {
    case outputAlreadyExists(URL)
    case sourceMissing(URL)
    case unableToReplaceSource(URL)

    public var errorDescription: String? {
        switch self {
        case .outputAlreadyExists(let url): "Output already exists: \(url.path)"
        case .sourceMissing(let url): "Source file is missing: \(url.path)"
        case .unableToReplaceSource(let url): "Could not safely replace the edited file: \(url.path)"
        }
    }
}

public final class ToolchainConversionRunner: @unchecked Sendable, ConversionRunning {
    private let lock = NSLock()
    private var selectedToolchain: FFmpegToolchain?
    private let runnerFactory: @Sendable (FFmpegToolchain) -> any ConversionRunning

    public init(
        toolchain: FFmpegToolchain? = nil,
        runnerFactory: @escaping @Sendable (FFmpegToolchain) -> any ConversionRunning = { FFmpegJobRunner(toolchain: $0) }
    ) {
        selectedToolchain = toolchain
        self.runnerFactory = runnerFactory
    }

    public func selectToolchain(_ toolchain: FFmpegToolchain?) {
        lock.lock()
        defer { lock.unlock() }
        selectedToolchain = toolchain
    }

    public func run(
        _ job: ConversionJob,
        onProgress: @escaping @Sendable (FFmpegProgressEvent) -> Void
    ) async -> ProcessOutcome {
        let toolchain = currentToolchain()
        guard let toolchain else {
            return .failed(exitCode: -127, diagnostic: "FFmpeg is not configured.")
        }
        return await runnerFactory(toolchain).run(job, onProgress: onProgress)
    }

    private func currentToolchain() -> FFmpegToolchain? {
        lock.lock()
        defer { lock.unlock() }
        return selectedToolchain
    }
}
