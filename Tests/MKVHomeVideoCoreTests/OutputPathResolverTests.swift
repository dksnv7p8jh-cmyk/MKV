import Foundation
import Testing
@testable import MKVHomeVideoCore

@Test("output uses an mp4 extension without changing the source")
func outputUsesMP4Extension() throws {
    let source = URL(filePath: "/Media/Arrival.mkv")
    let output = try OutputPathResolver.uniqueOutputURL(
        sourceURL: source,
        destinationDirectory: URL(filePath: "/Exports", directoryHint: .isDirectory),
        preferredBaseName: "Arrival",
        existingURLs: []
    )

    #expect(output.path == "/Exports/Arrival.mp4")
    #expect(source.path == "/Media/Arrival.mkv")
}

@Test("a collision receives a deterministic numbered suffix")
func collisionGetsNumberedSuffix() throws {
    let result = try OutputPathResolver.uniqueOutputURL(
        sourceURL: URL(filePath: "/Media/Arrival.mkv"),
        destinationDirectory: URL(filePath: "/Exports", directoryHint: .isDirectory),
        preferredBaseName: "Arrival",
        existingURLs: [URL(filePath: "/Exports/Arrival.mp4")]
    )

    #expect(result.lastPathComponent == "Arrival 2.mp4")
}

@Test("output never reuses a source or existing output")
func uniqueOutputURLSkipsSourceAndExistingOutputs() throws {
    let source = URL(filePath: "/Exports/Arrival.mp4")
    let result = try OutputPathResolver.uniqueOutputURL(
        sourceURL: source,
        destinationDirectory: URL(filePath: "/Exports", directoryHint: .isDirectory),
        preferredBaseName: "Arrival",
        existingURLs: [URL(filePath: "/Exports/Arrival 2.mp4")]
    )

    #expect(result.lastPathComponent == "Arrival 3.mp4")
}

@Test("only mkv files are accepted regardless of extension case")
func filtersMKVFiles() {
    let accepted = MediaFileIntake.mkvFiles(in: [
        URL(filePath: "/Media/a.mkv"),
        URL(filePath: "/Media/b.MKV"),
        URL(filePath: "/Media/c.mp4"),
    ])

    #expect(accepted.map(\.lastPathComponent) == ["a.mkv", "b.MKV"])
}

@Test("only mp4 files are accepted for metadata editing regardless of extension case")
func filtersMP4Files() {
    let accepted = MediaFileIntake.mp4Files(in: [
        URL(filePath: "/Media/a.mp4"),
        URL(filePath: "/Media/b.MP4"),
        URL(filePath: "/Media/c.mkv"),
    ])

    #expect(accepted.map(\.lastPathComponent) == ["a.mp4", "b.MP4"])
}
