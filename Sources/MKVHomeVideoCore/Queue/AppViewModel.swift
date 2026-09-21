import Foundation
import Observation

public protocol ToolchainProviding: Sendable {
    func locateToolchain() -> Result<FFmpegToolchain, FFmpegToolchainLocatorError>
    func locateToolchain(customFFmpegURL: URL?) -> Result<FFmpegToolchain, FFmpegToolchainLocatorError>
}

public extension ToolchainProviding {
    func locateToolchain(customFFmpegURL: URL?) -> Result<FFmpegToolchain, FFmpegToolchainLocatorError> {
        locateToolchain()
    }
}

public struct SystemToolchainProvider: ToolchainProviding {
    public init() {}

    public func locateToolchain() -> Result<FFmpegToolchain, FFmpegToolchainLocatorError> {
        locateToolchain(customFFmpegURL: nil)
    }

    public func locateToolchain(customFFmpegURL: URL?) -> Result<FFmpegToolchain, FFmpegToolchainLocatorError> {
        do {
            return .success(try FFmpegToolchainLocator.locate(customFFmpegURL: customFFmpegURL))
        } catch let error as FFmpegToolchainLocatorError {
            return .failure(error)
        } catch {
            return .failure(.notInstalled(setupCommand: FFmpegToolchainLocator.setupCommand))
        }
    }
}

public enum AppScreen: Sendable, Equatable {
    case setup
    case queue
}

public enum AppViewModelError: Error, Sendable, Equatable {
    case destinationNotSelected
    case queueIsExecuting
}

extension AppViewModelError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .destinationNotSelected: "Choose an output destination before adding video files."
        case .queueIsExecuting: "Wait for the current conversion to finish before changing the queue."
        }
    }
}

@MainActor
@Observable
public final class AppViewModel {
    public private(set) var screen: AppScreen = .setup
    public private(set) var setupCommand = FFmpegToolchainLocator.setupCommand
    public private(set) var toolchain: FFmpegToolchain?
    public private(set) var customFFmpegURL: URL?
    public let controller: ConversionQueueController

    private let toolchainProvider: any ToolchainProviding
    private let toolchainRunner: ToolchainConversionRunner?
    private var didRestoreProject = false

    public init(
        toolchainProvider: any ToolchainProviding = SystemToolchainProvider(),
        destinationDirectory: URL? = nil,
        runner: (any ConversionRunning)? = nil,
        store: QueueProjectStore? = nil
    ) {
        self.toolchainProvider = toolchainProvider
        let selectedRunner = runner == nil ? ToolchainConversionRunner() : nil
        self.toolchainRunner = selectedRunner
        self.controller = ConversionQueueController(
            project: QueueProject(destinationDirectory: destinationDirectory),
            runner: runner ?? selectedRunner!,
            store: store
        )
        refreshToolchain()
        restoreProject()
    }

    public var jobs: [ConversionJob] {
        controller.jobs
    }

    public var destinationDirectory: URL? {
        controller.project.destinationDirectory
    }

    public func refreshToolchain() {
        switch toolchainProvider.locateToolchain(customFFmpegURL: customFFmpegURL) {
        case .success(let toolchain):
            self.toolchain = toolchain
            toolchainRunner?.selectToolchain(toolchain)
            screen = .queue
        case .failure(let error):
            toolchain = nil
            toolchainRunner?.selectToolchain(nil)
            screen = .setup
            switch error {
            case .notInstalled(let command):
                setupCommand = command
            case .customPathMissingSiblingProbe:
                setupCommand = FFmpegToolchainLocator.setupCommand
            }
        }
    }

    public func setDestinationDirectory(_ url: URL?) {
        guard !controller.isExecuting else { return }
        guard let url else {
            controller.replaceJobs(controller.jobs, destinationDirectory: nil)
            return
        }
        var jobs = controller.jobs
        var reserved = outputURLsOnDisk(in: url)
            + jobs.filter { $0.status == .completed || $0.status == .running }.map(\.destinationURL)
        for index in jobs.indices where jobs[index].operation == .conversion && jobs[index].status != .completed && jobs[index].status != .running {
            guard let outputURL = try? OutputPathResolver.uniqueOutputURL(
                sourceURL: jobs[index].sourceURL,
                destinationDirectory: url,
                preferredBaseName: jobs[index].sourceURL.deletingPathExtension().lastPathComponent,
                existingURLs: reserved
            ) else { continue }
            jobs[index].destinationURL = outputURL
            reserved.append(outputURL)
        }
        controller.replaceJobs(jobs, destinationDirectory: url)
    }

    public func setCustomFFmpegURL(_ url: URL?) {
        customFFmpegURL = url
        refreshToolchain()
    }

    public func addSources(_ urls: [URL]) throws {
        guard !controller.isExecuting else { throw AppViewModelError.queueIsExecuting }
        guard let destinationDirectory else {
            throw AppViewModelError.destinationNotSelected
        }
        let sourceURLs = MediaFileIntake.mkvFiles(in: urls)
        var jobs = controller.jobs
        var reserved = outputURLsOnDisk(in: destinationDirectory) + jobs.map(\.destinationURL)

        for sourceURL in sourceURLs {
            let outputURL = try OutputPathResolver.uniqueOutputURL(
                sourceURL: sourceURL,
                destinationDirectory: destinationDirectory,
                preferredBaseName: sourceURL.deletingPathExtension().lastPathComponent,
                existingURLs: reserved
            )
            jobs.append(ConversionJob(sourceURL: sourceURL, destinationURL: outputURL))
            reserved.append(outputURL)
        }
        controller.replaceJobs(jobs, destinationDirectory: destinationDirectory)
    }

    public func addMP4MetadataFiles(_ urls: [URL]) throws {
        guard !controller.isExecuting else { throw AppViewModelError.queueIsExecuting }
        let sourceURLs = MediaFileIntake.mp4Files(in: urls)
        var jobs = controller.jobs
        for sourceURL in sourceURLs {
            jobs.append(ConversionJob(
                sourceURL: sourceURL,
                destinationURL: sourceURL,
                operation: .metadataEdit
            ))
        }
        controller.replaceJobs(jobs, destinationDirectory: destinationDirectory)
    }

    public func updateJobMetadata(
        id: UUID,
        profile: MediaProfile,
        metadataOverride: VideoMetadataPatch
    ) {
        var jobs = controller.jobs
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].status != .running else { return }
        jobs[index].profile = profile
        jobs[index].metadataOverride = metadataOverride
        controller.replaceJobs(jobs, destinationDirectory: destinationDirectory)
    }

    public func setSharedMetadata(
        _ metadata: VideoMetadataPatch,
        profile: MediaProfile? = nil,
        for ids: Set<UUID>
    ) {
        let jobs = controller.jobs.map { job in
            guard ids.contains(job.id), job.status != .running else { return job }
            var updated = job
            updated.sharedMetadata = metadata
            if let profile { updated.profile = profile }
            return updated
        }
        controller.replaceJobs(jobs, destinationDirectory: destinationDirectory)
    }

    public func restoreProject() {
        guard !didRestoreProject else { return }
        didRestoreProject = true
        _ = controller.restore()
    }

    private func outputURLsOnDisk(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}

public struct UnavailableConversionRunner: ConversionRunning {
    public init() {}

    public func run(
        _ job: ConversionJob,
        onProgress: @escaping @Sendable (FFmpegProgressEvent) -> Void
    ) async -> ProcessOutcome {
        .failed(exitCode: -127, diagnostic: "FFmpeg is not configured.")
    }
}
