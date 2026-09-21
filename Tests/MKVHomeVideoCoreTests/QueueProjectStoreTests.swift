import Foundation
import Testing
@testable import MKVHomeVideoCore

private struct TemporaryDirectory {
    let url: URL

    static func make() throws -> Self {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return Self(url: url)
    }
}

@Test("queue project saves and loads atomically")
func projectRoundTrips() throws {
    let directory = try TemporaryDirectory.make()
    let store = QueueProjectStore(fileURL: directory.url.appending(path: "queue.json"))
    let project = QueueProject(
        destinationDirectory: URL(filePath: "/Exports", directoryHint: .isDirectory),
        jobs: [ConversionJob(
            sourceURL: URL(filePath: "/Media/Test.mkv"),
            destinationURL: URL(filePath: "/Exports/Test.mp4")
        )]
    )

    try store.save(project)
    #expect(try store.load() == project)
}

@Test("saved conversion queues without an operation field remain conversion jobs")
func legacyJobDefaultsToConversionOperation() throws {
    let job = ConversionJob(
        sourceURL: URL(filePath: "/Media/Test.mkv"),
        destinationURL: URL(filePath: "/Exports/Test.mp4")
    )
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as? [String: Any])
    object.removeValue(forKey: "operation")
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(ConversionJob.self, from: legacyData)

    #expect(decoded.operation == .conversion)
}

@Test("interrupted running work becomes queued on load")
func loadRequeuesInterruptedRunningJob() throws {
    let directory = try TemporaryDirectory.make()
    let store = QueueProjectStore(fileURL: directory.url.appending(path: "queue.json"))
    var job = ConversionJob(
        sourceURL: URL(filePath: "/Media/Test.mkv"),
        destinationURL: URL(filePath: "/Exports/Test.mp4")
    )
    job.status = .running
    job.progress = 0.62
    try store.save(QueueProject(
        destinationDirectory: URL(filePath: "/Exports", directoryHint: .isDirectory),
        jobs: [job]
    ))

    let restored = try store.load()
    #expect(restored.jobs[0].status == .queued)
    #expect(restored.jobs[0].progress == 0)
}

@Test("a corrupt project is preserved before reporting a recovery error")
func corruptProjectIsPreserved() throws {
    let directory = try TemporaryDirectory.make()
    defer { try? FileManager.default.removeItem(at: directory.url) }
    let store = QueueProjectStore(fileURL: directory.url.appending(path: "queue.json"))
    try Data("not a queue project".utf8).write(to: store.fileURL)

    #expect(throws: QueueProjectStoreError.corruptProject) {
        _ = try store.load()
    }
    #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.url.path)
    #expect(names.contains(where: { $0.hasPrefix("queue.corrupt-") && $0.hasSuffix(".json") }))
}
