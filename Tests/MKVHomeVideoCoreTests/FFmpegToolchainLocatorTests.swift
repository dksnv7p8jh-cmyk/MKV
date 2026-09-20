import Foundation
import Testing
@testable import MKVHomeVideoCore

@Test("custom ffmpeg path resolves its sibling ffprobe")
func customPathFindsSiblingProbe() throws {
    let toolchain = try FFmpegToolchainLocator.toolchain(
        customFFmpegURL: URL(filePath: "/opt/homebrew/bin/ffmpeg"),
        executablePaths: ["/opt/homebrew/bin/ffmpeg", "/opt/homebrew/bin/ffprobe"]
    )

    #expect(toolchain.ffmpegURL.path == "/opt/homebrew/bin/ffmpeg")
    #expect(toolchain.ffprobeURL.path == "/opt/homebrew/bin/ffprobe")
}

@Test("missing tools return setup guidance")
func missingToolsProvideSetupGuidance() {
    #expect(throws: FFmpegToolchainLocatorError.self) {
        try FFmpegToolchainLocator.toolchain(customFFmpegURL: nil, executablePaths: [])
    }
}

@Test("an arbitrary selected FFmpeg location is validated directly")
func selectedCustomPathOutsidePATHIsUsable() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let ffmpeg = directory.appending(path: "ffmpeg")
    let ffprobe = directory.appending(path: "ffprobe")
    FileManager.default.createFile(atPath: ffmpeg.path, contents: Data())
    FileManager.default.createFile(atPath: ffprobe.path, contents: Data())
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpeg.path)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffprobe.path)

    let toolchain = try FFmpegToolchainLocator.locate(customFFmpegURL: ffmpeg, environmentPath: "")

    #expect(toolchain == FFmpegToolchain(ffmpegURL: ffmpeg, ffprobeURL: ffprobe))
}
