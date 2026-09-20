import Foundation
import Observation

public protocol ConversionRunning: Sendable {
    func run(
        _ job: ConversionJob,
        onProgress: @escaping @Sendable (FFmpegProgressEvent) -> Void
    ) async -> ProcessOutcome
}

@MainActor
@Observable
public final class ConversionQueueController {
    public private(set) var project: QueueProject
    public private(set) var isExecuting = false
    public private(set) var pauseRequested = false
    public private(set) var persistenceError: String?

    private let runner: any ConversionRunning
    private let store: QueueProjectStore?

    public init(
        project: QueueProject = QueueProject(),
        runner: any ConversionRunning,
        store: QueueProjectStore? = nil
    ) {
        self.project = project
        self.runner = runner
        self.store = store
    }

    public var jobs: [ConversionJob] {
        project.jobs
    }

    public var aggregateProgress: Double {
        guard !project.jobs.isEmpty else { return 0 }
        let finishedUnits = project.jobs.reduce(0.0) { partial, job in
            switch job.status {
            case .completed:
                return partial + 1
            case .running:
                return partial + job.progress
            default:
                return partial
            }
        }
        return finishedUnits / Double(project.jobs.count)
    }

    public func start() async {
        guard !isExecuting else { return }
        isExecuting = true
        pauseRequested = false
        defer { isExecuting = false }

        while !pauseRequested, let index = project.jobs.firstIndex(where: { $0.status == .queued }) {
            project.jobs[index].status = .running
            project.jobs[index].progress = 0
            project.jobs[index].lastError = nil
            persist()

            let job = project.jobs[index]
            let outcome = await runner.run(job) { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.record(event, for: job.id)
                }
            }
            apply(outcome, to: job.id)
            persist()
        }
    }

    public func pauseAfterCurrent() {
        guard isExecuting else { return }
        pauseRequested = true
    }

    public func skip(_ id: UUID) {
        guard let index = project.jobs.firstIndex(where: { $0.id == id }) else { return }
        guard project.jobs[index].status == .queued || project.jobs[index].status == .failed else { return }
        project.jobs[index].status = .skipped
        project.jobs[index].progress = 0
        project.jobs[index].lastError = nil
        persist()
    }

    public func retry(_ id: UUID) {
        guard let index = project.jobs.firstIndex(where: { $0.id == id }) else { return }
        guard project.jobs[index].status == .failed || project.jobs[index].status == .skipped || project.jobs[index].status == .paused else { return }
        project.jobs[index].status = .queued
        project.jobs[index].progress = 0
        project.jobs[index].lastError = nil
        persist()
    }

    public func remove(_ id: UUID) {
        guard let index = project.jobs.firstIndex(where: { $0.id == id }) else { return }
        guard project.jobs[index].status != .running else { return }
        project.jobs.remove(at: index)
        persist()
    }

    public func replaceJobs(_ jobs: [ConversionJob], destinationDirectory: URL?) {
        guard !isExecuting else { return }
        project.jobs = jobs
        project.destinationDirectory = destinationDirectory
        persist()
    }

    @discardableResult
    public func restore() -> Bool {
        guard !isExecuting else { return false }
        guard let store else { return true }
        do {
            project = try store.load()
            persistenceError = nil
            return true
        } catch {
            persistenceError = (error as? LocalizedError)?.errorDescription ?? "The saved queue could not be restored."
            return false
        }
    }

    public func clearPersistenceError() {
        persistenceError = nil
    }

    private func record(_ event: FFmpegProgressEvent, for id: UUID) {
        guard let index = project.jobs.firstIndex(where: { $0.id == id }), project.jobs[index].status == .running else { return }
        switch event {
        case .updated(let fraction):
            project.jobs[index].progress = fraction
        case .completed:
            project.jobs[index].progress = 1
        }
    }

    private func apply(_ outcome: ProcessOutcome, to id: UUID) {
        guard let index = project.jobs.firstIndex(where: { $0.id == id }) else { return }
        switch outcome {
        case .succeeded:
            project.jobs[index].status = .completed
            project.jobs[index].progress = 1
        case .failed(let exitCode, let diagnostic):
            project.jobs[index].status = .failed
            project.jobs[index].lastError = diagnostic ?? "FFmpeg exited with status \(exitCode)."
        case .cancelled:
            project.jobs[index].status = .paused
        }
    }

    private func persist() {
        guard let store else { return }
        project.savedAt = Date()
        do {
            try store.save(project)
            persistenceError = nil
        } catch {
            persistenceError = (error as? LocalizedError)?.errorDescription ?? "The queue could not be saved."
        }
    }
}
