import Foundation
import Testing
@testable import MKVHomeVideoCore

private extension ConversionJob {
    static func fixture(status: JobStatus = .queued, progress: Double = 0) -> Self {
        ConversionJob(
            sourceURL: URL(filePath: "/Media/\(UUID().uuidString).mkv"),
            destinationURL: URL(filePath: "/Exports/\(UUID().uuidString).mp4"),
            status: status,
            progress: progress
        )
    }
}

private extension QueueProject {
    static func fixture(twoQueuedJobs: Bool) -> Self {
        QueueProject(
            destinationDirectory: URL(filePath: "/Exports", directoryHint: .isDirectory),
            jobs: twoQueuedJobs ? [.fixture(), .fixture()] : [.fixture()]
        )
    }
}

private actor ControlledRunner: ConversionRunning {
    private var outcomes: [ProcessOutcome]
    private var activeRuns = 0
    private var recordedMaximumConcurrentRuns = 0

    init(outcomes: [ProcessOutcome] = [.succeeded]) {
        self.outcomes = outcomes
    }

    func run(
        _ job: ConversionJob,
        onProgress: @escaping @Sendable (FFmpegProgressEvent) -> Void
    ) async -> ProcessOutcome {
        activeRuns += 1
        recordedMaximumConcurrentRuns = max(recordedMaximumConcurrentRuns, activeRuns)
        defer { activeRuns -= 1 }
        return outcomes.isEmpty ? .succeeded : outcomes.removeFirst()
    }

    func maximumConcurrentRuns() -> Int {
        recordedMaximumConcurrentRuns
    }
}

@Test("queue runs one job at a time and continues after success")
@MainActor
func queueRunsSequentially() async {
    let runner = ControlledRunner(outcomes: [.succeeded, .succeeded])
    let controller = ConversionQueueController(project: .fixture(twoQueuedJobs: true), runner: runner)

    await controller.start()

    #expect(controller.jobs.map(\.status) == [.completed, .completed])
    #expect(await runner.maximumConcurrentRuns() == 1)
}

@Test("retry makes a failed job eligible without changing its metadata")
@MainActor
func retryPreservesJobMetadata() {
    var project = QueueProject.fixture(twoQueuedJobs: false)
    project.jobs[0].status = .failed
    project.jobs[0].lastError = "AAC encoder failed"
    project.jobs[0].metadataOverride = .init(title: "Arrival")
    let controller = ConversionQueueController(project: project, runner: ControlledRunner())

    let expectedMetadata = controller.jobs[0].metadataOverride
    controller.retry(controller.jobs[0].id)

    #expect(controller.jobs[0].status == .queued)
    #expect(controller.jobs[0].lastError == nil)
    #expect(controller.jobs[0].metadataOverride == expectedMetadata)
}

private struct DiagnosticFailureRunner: ConversionRunning {
    func run(
        _ job: ConversionJob,
        onProgress: @escaping @Sendable (FFmpegProgressEvent) -> Void
    ) async -> ProcessOutcome {
        .failed(exitCode: 1, diagnostic: "Unknown encoder 'libx264'.")
    }
}

@Test("queue retains actionable conversion diagnostics")
@MainActor
func queueShowsProcessDiagnosticOnFailure() async {
    let controller = ConversionQueueController(
        project: .fixture(twoQueuedJobs: false),
        runner: DiagnosticFailureRunner()
    )

    await controller.start()

    #expect(controller.jobs[0].status == .failed)
    #expect(controller.jobs[0].lastError == "Unknown encoder 'libx264'.")
}

private actor BlockingRunner: ConversionRunning {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didStart = false

    func run(
        _ job: ConversionJob,
        onProgress: @escaping @Sendable (FFmpegProgressEvent) -> Void
    ) async -> ProcessOutcome {
        didStart = true
        await withCheckedContinuation { continuation = $0 }
        return .succeeded
    }

    func hasStarted() -> Bool { didStart }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

@Test("restore cannot replace active queue state")
@MainActor
func restoreDoesNotReplaceAnActiveQueue() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = QueueProjectStore(fileURL: directory.appending(path: "queue.json"))
    let activeJob = ConversionJob(
        sourceURL: URL(filePath: "/Media/Active.mkv"),
        destinationURL: URL(filePath: "/Exports/Active.mp4")
    )
    let replacementJob = ConversionJob(
        sourceURL: URL(filePath: "/Media/Replacement.mkv"),
        destinationURL: URL(filePath: "/Exports/Replacement.mp4")
    )
    let runner = BlockingRunner()
    let controller = ConversionQueueController(
        project: QueueProject(jobs: [activeJob]),
        runner: runner,
        store: store
    )
    let execution = Task { await controller.start() }
    for _ in 0..<100 where !(await runner.hasStarted()) {
        await Task.yield()
    }
    #expect(await runner.hasStarted())
    try store.save(QueueProject(jobs: [replacementJob]))

    #expect(controller.restore() == false)
    #expect(controller.jobs.map { $0.sourceURL } == [activeJob.sourceURL])

    await runner.finish()
    await execution.value
}
