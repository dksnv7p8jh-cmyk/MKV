import Foundation
import Testing
@testable import MKVHomeVideoCore

private struct TestToolchainProvider: ToolchainProviding {
    let result: Result<FFmpegToolchain, FFmpegToolchainLocatorError>

    func locateToolchain() -> Result<FFmpegToolchain, FFmpegToolchainLocatorError> {
        result
    }

    static let fixture = TestToolchainProvider(result: .success(.fixture))
    static let missing = TestToolchainProvider(
        result: .failure(.notInstalled(setupCommand: "brew install ffmpeg"))
    )
}

@Test("missing toolchain enters setup state with Homebrew guidance")
@MainActor
func missingToolchainShowsSetup() {
    let model = AppViewModel(toolchainProvider: TestToolchainProvider.missing)
    model.refreshToolchain()

    #expect(model.screen == .setup)
    #expect(model.setupCommand == "brew install ffmpeg")
}

@Test("adding sources creates queued jobs with safe destinations")
@MainActor
func addingSourcesCreatesQueuedJobs() throws {
    let model = AppViewModel(
        toolchainProvider: TestToolchainProvider.fixture,
        destinationDirectory: URL(filePath: "/Exports", directoryHint: .isDirectory)
    )
    try model.addSources([URL(filePath: "/Media/Arrival.mkv")])

    #expect(model.jobs.count == 1)
    #expect(model.jobs[0].status == .queued)
    #expect(model.jobs[0].destinationURL.path == "/Exports/Arrival.mp4")
}

@Test("metadata editing changes only the selected queued job")
@MainActor
func updatingJobMetadataPreservesQueueSources() throws {
    let model = AppViewModel(
        toolchainProvider: TestToolchainProvider.fixture,
        destinationDirectory: URL(filePath: "/Exports", directoryHint: .isDirectory)
    )
    try model.addSources([
        URL(filePath: "/Media/One.mkv"),
        URL(filePath: "/Media/Two.mkv"),
    ])
    let firstID = model.jobs[0].id
    let secondSource = model.jobs[1].sourceURL

    model.updateJobMetadata(
        id: firstID,
        profile: .tvEpisode,
        metadataOverride: .init(showName: "Severance", episodeTitle: "Pilot", seasonNumber: 1, episodeNumber: 1)
    )

    #expect(model.jobs[0].profile == .tvEpisode)
    #expect(model.jobs[0].metadataOverride.showName == "Severance")
    #expect(model.jobs[1].sourceURL == secondSource)
}

@Test("adding a source reserves an MP4 that already exists on disk")
@MainActor
func addingSourceSkipsExistingDiskOutput() throws {
    let directory = try makeAppViewModelTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let existingOutput = directory.appending(path: "Arrival.mp4")
    FileManager.default.createFile(atPath: existingOutput.path, contents: Data())
    let model = AppViewModel(
        toolchainProvider: TestToolchainProvider.fixture,
        destinationDirectory: directory
    )

    try model.addSources([URL(filePath: "/Media/Arrival.mkv")])

    #expect(model.jobs.map(\.destinationURL) == [directory.appending(path: "Arrival 2.mp4")])
}

@Test("changing the destination reallocates pending jobs into the selected folder")
@MainActor
func changingDestinationReallocatesPendingJobs() throws {
    let firstDirectory = try makeAppViewModelTemporaryDirectory()
    let secondDirectory = try makeAppViewModelTemporaryDirectory()
    defer {
        try? FileManager.default.removeItem(at: firstDirectory)
        try? FileManager.default.removeItem(at: secondDirectory)
    }
    let model = AppViewModel(toolchainProvider: TestToolchainProvider.fixture, destinationDirectory: firstDirectory)
    try model.addSources([URL(filePath: "/Media/Arrival.mkv")])

    model.setDestinationDirectory(secondDirectory)

    #expect(model.destinationDirectory == secondDirectory)
    #expect(model.jobs[0].destinationURL == secondDirectory.appending(path: "Arrival.mp4"))
}

@Test("batch metadata can set TV profile and shared TV fields")
@MainActor
func batchMetadataSetsTVProfileAndFields() throws {
    let model = AppViewModel(
        toolchainProvider: TestToolchainProvider.fixture,
        destinationDirectory: URL(filePath: "/Exports", directoryHint: .isDirectory)
    )
    try model.addSources([URL(filePath: "/Media/One.mkv"), URL(filePath: "/Media/Two.mkv")])
    let ids = Set(model.jobs.map(\.id))

    model.setSharedMetadata(
        .init(showName: "Severance", seasonNumber: 2, network: "Apple TV+"),
        profile: .tvEpisode,
        for: ids
    )

    #expect(model.jobs.allSatisfy { $0.profile == .tvEpisode })
    #expect(model.jobs.allSatisfy { $0.sharedMetadata.showName == "Severance" })
    #expect(model.jobs.allSatisfy { $0.sharedMetadata.seasonNumber == 2 })
}

@Test("adding MP4s queues metadata edits without an output destination")
@MainActor
func addingMP4sCreatesInPlaceMetadataJobs() throws {
    let model = AppViewModel(toolchainProvider: TestToolchainProvider.fixture)
    let file = URL(filePath: "/Media/Arrival.mp4")

    try model.addMP4MetadataFiles([file])

    #expect(model.jobs.count == 1)
    #expect(model.jobs[0].operation == .metadataEdit)
    #expect(model.jobs[0].sourceURL == file)
    #expect(model.jobs[0].destinationURL == file)
}

@Test("changing the conversion destination does not redirect queued MP4 metadata edits")
@MainActor
func changingDestinationPreservesMetadataEditSource() throws {
    let firstDirectory = try makeAppViewModelTemporaryDirectory()
    let secondDirectory = try makeAppViewModelTemporaryDirectory()
    defer {
        try? FileManager.default.removeItem(at: firstDirectory)
        try? FileManager.default.removeItem(at: secondDirectory)
    }
    let model = AppViewModel(toolchainProvider: TestToolchainProvider.fixture, destinationDirectory: firstDirectory)
    let file = URL(filePath: "/Media/Arrival.mp4")
    try model.addMP4MetadataFiles([file])

    model.setDestinationDirectory(secondDirectory)

    #expect(model.jobs[0].operation == .metadataEdit)
    #expect(model.jobs[0].destinationURL == file)
}

private func makeAppViewModelTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
