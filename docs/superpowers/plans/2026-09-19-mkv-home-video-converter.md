# MKV Home Video Converter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a private, native macOS application that queues local MKVs, applies Apple TV Home Video metadata, previews supported files, and converts batches to compatible MP4s through a user-installed FFmpeg toolchain.

**Architecture:** A Swift Package splits pure conversion policy from the SwiftUI application. `MKVHomeVideoCore` owns models, metadata resolution, tool discovery, FFmpeg/ffprobe command construction, progress parsing, persistence, and the queue state machine; `MKVHomeVideoApp` binds those services to the macOS interface and AVFoundation preview. A packaging script turns the release executable into a clickable `.app` without adding third-party dependencies.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, Foundation `Process`, Swift Testing/XCTest as supported by the installed toolchain, FFmpeg and ffprobe installed with Homebrew, Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-09-19-mkv-home-video-design.md`

## Global Constraints

- Target macOS 26 or later and use a native SwiftUI application.
- Work entirely offline: do not add accounts, analytics, cloud services, metadata scraping, or artwork download.
- Require an externally installed FFmpeg executable; show `brew install ffmpeg` and allow a custom path when it is absent.
- Do not change, rename, delete, or overwrite source MKVs.
- Export every result with Apple TV Home Video media kind using H.264, AAC, and `+faststart` MP4 layout.
- Keep queue projects and metadata drafts in local Application Support JSON storage.
- Initial batch execution is sequential; include per-job progress, aggregate progress, retry, skip, pause-after-current, and resume.
- Do not claim native preview supports every MKV codec. Use AVFoundation when it can decode the selected source and always preview created MP4s.
- The app prepares files for Apple TV import but does not automate importing them into the TV library.

## Review Focus

1. A source whose output filename equals an existing source or completed output must receive a non-destructive numbered output name (Task 3 test `testUniqueOutputURLSkipsSourceAndExistingOutputs`).
2. A TV job with empty optional fields must omit empty FFmpeg metadata flags rather than emit malformed `key=` tags (Task 4 test `testCommandOmitsEmptyOptionalTVMetadata`).
3. Bitmap subtitle streams (for example PGS) must be excluded instead of causing a MOV text-subtitle conversion failure (Task 4 test `testCommandMapsOnlyTextSubtitleStreams`).
4. A malformed, partial, or split FFmpeg `-progress pipe:1` line must not set progress to 100% or fail a running job (Task 5 test `testParserBuffersPartialRecordsUntilProgressMarker`).
5. A restart with a persisted `running` job must restore that job as retryable/queued, never incorrectly report a finished output (Task 6 test `testLoadRequeuesInterruptedRunningJob`).

---

## File Structure

```
Package.swift                                      # package products and macOS platform
Sources/MKVHomeVideoCore/
  Domain/VideoMetadata.swift                       # movie/episode metadata and inheritance
  Domain/ConversionJob.swift                       # queue job/status/project values
  Domain/PackagingInfo.swift                       # Info.plist fields used by package validation
  Intake/OutputPathResolver.swift                  # safe, collision-free MP4 names
  Intake/MediaFileIntake.swift                     # MKV-only import filtering
  Intake/MediaProbe.swift                          # ffprobe stream/duration model and decoder
  FFmpeg/FFmpegToolchainLocator.swift              # find/validate ffmpeg + ffprobe
  FFmpeg/FFmpegMetadataTagMapper.swift             # Home Video/iTunes metadata arguments
  FFmpeg/FFmpegCommandBuilder.swift                # compatibility conversion arguments
  FFmpeg/FFmpegProgressParser.swift                # structured FFmpeg progress parser
  FFmpeg/ProcessRunner.swift                       # injectable Process wrapper
  Queue/QueueProjectStore.swift                    # atomic JSON save/load
  Queue/ConversionQueueController.swift            # sequential state machine
  Queue/AppViewModel.swift                         # UI-facing queue/toolchain state
Sources/MKVHomeVideoApp/
  MKVHomeVideoApp.swift                            # SwiftUI entry point
  Views/SetupView.swift                            # missing-FFmpeg guidance/path picker
  Views/QueueView.swift                            # import controls, table, batch controls
  Views/MetadataEditorView.swift                   # shared and per-job metadata editing
  Views/PreviewView.swift                          # AVPlayer sheet/fallback message
  Views/QueueRowView.swift                         # job row/progress/actions
Resources/Info.plist                               # bundle metadata
Scripts/build-app.sh                               # release build and .app assembly
Tests/MKVHomeVideoCoreTests/
  VideoMetadataTests.swift
  OutputPathResolverTests.swift
  FFmpegToolchainLocatorTests.swift
  FFmpegCommandBuilderTests.swift
  FFmpegProgressParserTests.swift
  QueueProjectStoreTests.swift
  ConversionQueueControllerTests.swift
  AppViewModelTests.swift
  TestFixtures.swift                               # local test-only values and runners
```

## Task 1: Bootstrap the Native App Package

**Files:**
- Create: `Package.swift`
- Create: `Sources/MKVHomeVideoApp/MKVHomeVideoApp.swift`
- Create: `Resources/Info.plist`
- Create: `Scripts/build-app.sh`
- Create: `Tests/MKVHomeVideoCoreTests/PackageSmokeTests.swift`

**Interfaces:**
- Consumes: no project code.
- Produces: the `MKVHomeVideoCore` library target, `MKVHomeVideoApp` executable target, and an executable test target for all later tasks.

- [ ] **Step 1: Create the package configuration and non-functional executable scaffold**

Create a Swift tools version 6 manifest with `.macOS(.v26)`, a library product named `MKVHomeVideoCore`, an executable product named `MKVHomeVideoApp`, and a test target `MKVHomeVideoCoreTests` depending on the core library. The minimal app entry point must create a SwiftUI `WindowGroup` showing `ContentUnavailableView("MKV Home Video", systemImage: "film")`; this is package scaffolding, not conversion behavior.

Create an `Info.plist` with `CFBundleIdentifier` `com.peterbertella.MKVHomeVideo`, `CFBundleName` `MKV Home Video`, `CFBundleExecutable` `MKVHomeVideoApp`, `CFBundlePackageType` `APPL`, and `LSMinimumSystemVersion` `26.0`.

Create an executable `Scripts/build-app.sh` that runs `swift build -c release`, recreates `dist/MKV Home Video.app/Contents/{MacOS,Resources}`, copies the release executable and `Resources/Info.plist` into those locations, then prints the full bundle path. It must use paths based on its own script directory, not the caller’s working directory.

- [ ] **Step 2: Write the failing package smoke test**

```swift
import Testing
@testable import MKVHomeVideoCore

@Test("the core package exposes its app identity")
func appIdentityIsStable() {
    #expect(AppIdentity.bundleIdentifier == "com.peterbertella.MKVHomeVideo")
}
```

- [ ] **Step 3: Run the smoke test to verify the expected failure**

Run: `swift test --filter PackageSmokeTests/appIdentityIsStable`

Expected: compilation fails because `AppIdentity` is not defined.

- [ ] **Step 4: Add the smallest production identity type**

Create `Sources/MKVHomeVideoCore/Domain/AppIdentity.swift`:

```swift
public enum AppIdentity {
    public static let bundleIdentifier = "com.peterbertella.MKVHomeVideo"
}
```

- [ ] **Step 5: Verify the test and package build**

Run: `swift test --filter PackageSmokeTests/appIdentityIsStable && swift build`

Expected: one passing test and a successful debug build with no warnings.

- [ ] **Step 6: Record the checkpoint**

This workspace is not a Git repository, so record the exact test/build command output in the implementation handoff rather than attempting a commit.

## Task 2: Model Metadata and Resolve Batch Overrides

**Files:**
- Create: `Sources/MKVHomeVideoCore/Domain/VideoMetadata.swift`
- Create: `Sources/MKVHomeVideoCore/Domain/ConversionJob.swift`
- Create: `Tests/MKVHomeVideoCoreTests/VideoMetadataTests.swift`

**Interfaces:**
- Consumes: `AppIdentity` only through the same core target.
- Produces: `MediaProfile`, `VideoMetadata`, `VideoMetadataPatch`, `ResolvedVideoMetadata`, `ConversionJob`, `JobStatus`, and `VideoMetadata.resolving(_:)` for command building, persistence, and the UI.

- [ ] **Step 1: Write failing metadata-resolution tests**

```swift
import Testing
@testable import MKVHomeVideoCore

@Test("per-job metadata overrides shared movie values")
func overrideWinsOverSharedValue() {
    let shared = VideoMetadataPatch(title: "Shared title", genre: "Drama")
    let override = VideoMetadataPatch(title: "Arrival")

    let resolved = ResolvedVideoMetadata(profile: .movie,
                                         shared: shared,
                                         override: override)

    #expect(resolved.title == "Arrival")
    #expect(resolved.genre == "Drama")
    #expect(resolved.mediaKind == .homeVideo)
}

@Test("episode metadata retains sorting values")
func episodeMetadataRetainsOrdering() {
    let metadata = ResolvedVideoMetadata(profile: .tvEpisode,
                                         shared: .init(showName: "Severance", seasonNumber: 2),
                                         override: .init(episodeTitle: "Hello, Ms. Cobel", episodeNumber: 1))

    #expect(metadata.showName == "Severance")
    #expect(metadata.seasonNumber == 2)
    #expect(metadata.episodeNumber == 1)
}
```

- [ ] **Step 2: Run the metadata tests to verify the expected failure**

Run: `swift test --filter VideoMetadataTests`

Expected: compilation fails because the metadata types are not defined.

- [ ] **Step 3: Implement the smallest Codable metadata model**

Implement a `MediaProfile: String, Codable, CaseIterable, Sendable` with `.movie` and `.tvEpisode`, and `AppleMediaKind` with `.homeVideo` raw value `10`. Define `VideoMetadataPatch` with optional text/integer URLs fields for every approved field: `title`, `sortTitle`, `description`, `genre`, `releaseDate`, `collectionName`, `director`, `cast`, `studio`, `rating`, `copyright`, `artworkURL`, `showName`, `showSortName`, `episodeTitle`, `seasonNumber`, `episodeNumber`, `episodeSort`, `airDate`, and `network`.

`ResolvedVideoMetadata` takes `(profile: MediaProfile, shared: VideoMetadataPatch, override: VideoMetadataPatch)` and chooses a non-`nil` override before its shared value. Expose `mediaKind` as `.homeVideo`, ensuring the batch is always a Home Video even when the profile is Movie or TV Episode.

Define a Codable `ConversionJob` with stable `UUID id`, `sourceURL`, `destinationURL`, `profile`, `sharedMetadata`, `metadataOverride`, `status`, `progress`, and optional `lastError`. `JobStatus` is a plain Codable enum with `queued`, `running`, `paused`, `completed`, `failed`, and `skipped` cases; failure text remains in `lastError` so it persists safely.

- [ ] **Step 4: Verify the metadata tests pass**

Run: `swift test --filter VideoMetadataTests`

Expected: both tests pass.

- [ ] **Step 5: Add a persistence-value test before refactoring**

```swift
@Test("a queued job round-trips through Codable")
func conversionJobRoundTrips() throws {
    let original = ConversionJob(sourceURL: URL(filePath: "/Movies/Arrival.mkv"),
                                 destinationURL: URL(filePath: "/Output/Arrival.mp4"))
    let decoded = try JSONDecoder().decode(ConversionJob.self,
        from: JSONEncoder().encode(original))

    #expect(decoded == original)
}
```

- [ ] **Step 6: Run the new test, then make `ConversionJob` Equatable and verify all task tests**

Run first: `swift test --filter VideoMetadataTests/conversionJobRoundTrips`

Expected first run: compilation failure because `ConversionJob` is not `Equatable`.

Then add `Equatable` conformance to the value types and run: `swift test --filter VideoMetadataTests`

Expected final run: all metadata tests pass.

## Task 3: Safely Import Sources and Allocate Output Names

**Files:**
- Create: `Sources/MKVHomeVideoCore/Intake/OutputPathResolver.swift`
- Create: `Sources/MKVHomeVideoCore/Intake/MediaFileIntake.swift`
- Create: `Tests/MKVHomeVideoCoreTests/OutputPathResolverTests.swift`

**Interfaces:**
- Consumes: `ConversionJob` source/destination URLs from Task 2.
- Produces: `OutputPathResolver.uniqueOutputURL(sourceURL:destinationDirectory:preferredBaseName:existingURLs:) throws -> URL` used by the UI when adding jobs.

- [ ] **Step 1: Write failing output-safety tests**

```swift
import Testing
@testable import MKVHomeVideoCore

@Test("output uses an mp4 extension without changing the source")
func outputUsesMP4Extension() throws {
    let source = URL(filePath: "/Media/Arrival.mkv")
    let output = try OutputPathResolver.uniqueOutputURL(
        sourceURL: source,
        destinationDirectory: URL(filePath: "/Exports"),
        preferredBaseName: "Arrival",
        existingURLs: [])

    #expect(output.path == "/Exports/Arrival.mp4")
    #expect(source.path == "/Media/Arrival.mkv")
}

@Test("a collision receives a deterministic numbered suffix")
func collisionGetsNumberedSuffix() throws {
    let result = try OutputPathResolver.uniqueOutputURL(
        sourceURL: URL(filePath: "/Media/Arrival.mkv"),
        destinationDirectory: URL(filePath: "/Exports"),
        preferredBaseName: "Arrival",
        existingURLs: [URL(filePath: "/Exports/Arrival.mp4")])

    #expect(result.lastPathComponent == "Arrival 2.mp4")
}

@Test("output never reuses a source or existing output")
func testUniqueOutputURLSkipsSourceAndExistingOutputs() throws {
    let source = URL(filePath: "/Exports/Arrival.mp4")
    let result = try OutputPathResolver.uniqueOutputURL(
        sourceURL: source,
        destinationDirectory: URL(filePath: "/Exports"),
        preferredBaseName: "Arrival",
        existingURLs: [URL(filePath: "/Exports/Arrival 2.mp4")])

    #expect(result.lastPathComponent == "Arrival 3.mp4")
}
```

- [ ] **Step 2: Run the resolver tests to verify the expected failure**

Run: `swift test --filter OutputPathResolverTests`

Expected: compilation fails because `OutputPathResolver` is not defined.

- [ ] **Step 3: Implement the resolver**

Implement `OutputPathResolver` as a namespace enum. Reject a destination that is not a directory URL and strip `.mkv`/`.mp4` extensions from `preferredBaseName` before adding `.mp4`. Compare standardised, case-insensitive URLs against `sourceURL` and `existingURLs`, then return `Base.mp4`, `Base 2.mp4`, `Base 3.mp4`, and so on, without touching the filesystem. The caller supplies currently present destination files as part of `existingURLs`.

- [ ] **Step 4: Verify resolver behavior**

Run: `swift test --filter OutputPathResolverTests`

Expected: all three tests pass.

- [ ] **Step 5: Add failing folder-filtering coverage**

Add this test for the small, pure intake helper:

```swift
@Test("only mkv files are accepted regardless of extension case")
func filtersMKVFiles() {
    let accepted = MediaFileIntake.mkvFiles(in: [
        URL(filePath: "/Media/a.mkv"), URL(filePath: "/Media/b.MKV"),
        URL(filePath: "/Media/c.mp4")
    ])
    #expect(accepted.map(\.lastPathComponent) == ["a.mkv", "b.MKV"])
}
```

- [ ] **Step 6: Verify folder filtering and the entire suite**

Run first: `swift test --filter OutputPathResolverTests/filtersMKVFiles`

Expected first run: compilation failure because `MediaFileIntake` does not exist.

Implement `MediaFileIntake.mkvFiles(in:)` as an extension-based filter preserving input order. Then run: `swift test`

Expected final run: every test so far passes.

## Task 4: Discover FFmpeg and Build Apple-Compatible Commands

**Files:**
- Create: `Sources/MKVHomeVideoCore/Intake/MediaProbe.swift`
- Create: `Sources/MKVHomeVideoCore/FFmpeg/FFmpegToolchainLocator.swift`
- Create: `Sources/MKVHomeVideoCore/FFmpeg/FFmpegMetadataTagMapper.swift`
- Create: `Sources/MKVHomeVideoCore/FFmpeg/FFmpegCommandBuilder.swift`
- Create: `Tests/MKVHomeVideoCoreTests/FFmpegToolchainLocatorTests.swift`
- Create: `Tests/MKVHomeVideoCoreTests/FFmpegCommandBuilderTests.swift`

**Interfaces:**
- Consumes: `ResolvedVideoMetadata` and `ConversionJob` from Task 2; safe output URLs from Task 3.
- Produces: `FFmpegToolchain`, `FFmpegToolchainLocator.locate(customFFmpegURL:environmentPath:)`, `MediaProbeResult`, `FFmpegCommand`, and `FFmpegCommandBuilder.makeCommand(toolchain:sourceURL:outputURL:metadata:probe:) throws` for the runner.

- [ ] **Step 1: Write failing locator tests**

```swift
import Testing
@testable import MKVHomeVideoCore

@Test("custom ffmpeg path resolves its sibling ffprobe")
func customPathFindsSiblingProbe() throws {
    let toolchain = try FFmpegToolchainLocator.toolchain(
        customFFmpegURL: URL(filePath: "/opt/homebrew/bin/ffmpeg"),
        executablePaths: ["/opt/homebrew/bin/ffmpeg", "/opt/homebrew/bin/ffprobe"])

    #expect(toolchain.ffmpegURL.path == "/opt/homebrew/bin/ffmpeg")
    #expect(toolchain.ffprobeURL.path == "/opt/homebrew/bin/ffprobe")
}

@Test("missing tools return setup guidance")
func missingToolsProvideSetupGuidance() {
    #expect(throws: FFmpegToolchainLocatorError.self) {
        try FFmpegToolchainLocator.toolchain(customFFmpegURL: nil, executablePaths: [])
    }
}
```

- [ ] **Step 2: Run locator tests to verify the expected failure**

Run: `swift test --filter FFmpegToolchainLocatorTests`

Expected: compilation fails because the locator types are missing.

- [ ] **Step 3: Implement deterministic toolchain discovery**

Define `FFmpegToolchain` with `ffmpegURL` and `ffprobeURL`. `FFmpegToolchainLocator.toolchain(customFFmpegURL:executablePaths:)` first validates a custom `ffmpeg` and sibling `ffprobe`, then searches `/opt/homebrew/bin`, `/usr/local/bin`, and parsed `PATH` entries. It returns `FFmpegToolchainLocatorError.notInstalled(setupCommand: "brew install ffmpeg")` when neither tool pair is available. Keep actual executable/file-system checks in a thin production adapter; the deterministic method receives `executablePaths` so its policy is unit-testable.

- [ ] **Step 4: Verify locator tests pass**

Run: `swift test --filter FFmpegToolchainLocatorTests`

Expected: both tests pass.

- [ ] **Step 5: Write failing command-builder tests**

At the top of `FFmpegCommandBuilderTests.swift`, add test-only fixtures before the tests:

```swift
extension FFmpegToolchain {
    static let fixture = FFmpegToolchain(
        ffmpegURL: URL(filePath: "/opt/homebrew/bin/ffmpeg"),
        ffprobeURL: URL(filePath: "/opt/homebrew/bin/ffprobe"))
}

extension MediaProbeResult {
    static func fixture(video: VideoCodec, audio: [AudioCodec], subtitles: [SubtitleCodec]) -> Self {
        .init(durationMicroseconds: 10_000_000, video: [.init(codec: video)],
              audio: audio.map { .init(codec: $0) },
              subtitles: subtitles.map { .init(codec: $0) })
    }
}

extension ResolvedVideoMetadata {
    static let fixtureEpisode = ResolvedVideoMetadata(
        profile: .tvEpisode, shared: .init(showName: "Severance", episodeTitle: "Hello, Ms. Cobel"), override: .init())
}
```

```swift
@Test("movie command uses Apple-compatible video, audio, and Home Video tags")
func movieCommandUsesCompatibilityPreset() throws {
    let metadata = ResolvedVideoMetadata(profile: .movie,
        shared: .init(title: "Arrival", genre: "Science Fiction", description: "First contact"),
        override: .init())
    let command = try FFmpegCommandBuilder().makeCommand(
        toolchain: .fixture,
        sourceURL: URL(filePath: "/Media/Arrival.mkv"),
        outputURL: URL(filePath: "/Output/Arrival.mp4"),
        metadata: metadata,
        probe: .fixture(video: .h264, audio: [.aac], subtitles: []))

    #expect(command.arguments.contains("libx264"))
    #expect(command.arguments.contains("aac"))
    #expect(command.arguments.contains("+faststart"))
    #expect(command.arguments.containsSubsequence(["-metadata", "media_type=10"]))
    #expect(command.arguments.containsSubsequence(["-metadata", "title=Arrival"]))
}

@Test("text subtitles are mapped while bitmap subtitles are excluded")
func testCommandMapsOnlyTextSubtitleStreams() throws {
    let command = try FFmpegCommandBuilder().makeCommand(
        toolchain: .fixture, sourceURL: URL(filePath: "/Media/show.mkv"),
        outputURL: URL(filePath: "/Output/show.mp4"),
        metadata: .fixtureEpisode,
        probe: .fixture(video: .hevc, audio: [.ac3], subtitles: [.subrip, .pgs]))

    #expect(command.arguments.containsSubsequence(["-map", "0:s:0?"]))
    #expect(!command.arguments.contains("0:s:1?"))
    #expect(command.arguments.containsSubsequence(["-c:s", "mov_text"]))
}

@Test("empty optional episode metadata is omitted")
func testCommandOmitsEmptyOptionalTVMetadata() throws {
    let command = try FFmpegCommandBuilder().makeCommand(
        toolchain: .fixture, sourceURL: URL(filePath: "/Media/episode.mkv"),
        outputURL: URL(filePath: "/Output/episode.mp4"),
        metadata: ResolvedVideoMetadata(profile: .tvEpisode, shared: .init(episodeTitle: "Pilot"), override: .init()),
        probe: .fixture(video: .h264, audio: [.aac], subtitles: []))

    #expect(!command.arguments.contains(where: { $0 == "show=" || $0 == "network=" }))
}
```

- [ ] **Step 6: Run command-builder tests to verify the expected failure**

Run: `swift test --filter FFmpegCommandBuilderTests`

Expected: compilation fails because `FFmpegCommandBuilder` and probe fixtures are missing.

- [ ] **Step 7: Implement probe values, tag mapping, and conversion command construction**

Define `MediaProbeResult` with duration and ordered `VideoStream`, `AudioStream`, and `SubtitleStream` values. Decode ffprobe JSON in `MediaProbeResult.decode(json:)`, keeping only codecs required by command policy. `SubtitleCodec` must distinguish `.subrip`, `.ass`, `.webVTT`, `.pgs`, and `.unknown`; only text codecs map to `mov_text`.

Implement `FFmpegMetadataTagMapper.arguments(for:)` to return `-metadata` pairs only for non-empty values. Map required values: `title`, `sort_name`, `description`, `genre`, `date`, `album`, `artist`, `album_artist`, `copyright`, `show`, `episode_id`, `season_number`, `episode_sort`, `network`, and `media_type=10`. Map Movie credits to `artist`/`album_artist` only where an Apple-compatible atom exists; preserve full values in `description` only when supplied by the user, never synthesize text.

Implement `FFmpegCommandBuilder` to build an argument array equivalent to:

```text
-hide_banner -y -i SOURCE -map 0:v:0 -map 0:a? -c:v libx264 -pix_fmt yuv420p
-crf 18 -c:a aac -b:a 192k -c:s mov_text -movflags +faststart
-progress pipe:1 -nostats [metadata pairs] OUTPUT
```

Append only text subtitle maps, include artwork as a second input with an attached-picture disposition when `artworkURL` exists, and use explicit stream-index codecs so cover art is not re-encoded as main video. Throw a typed error if no primary video stream exists or required source/output URLs are not file URLs. Add `Array<String>.containsSubsequence(_:)` only in the test target.

- [ ] **Step 8: Verify command behavior and all prior tests**

Run: `swift test --filter FFmpegCommandBuilderTests && swift test`

Expected: all command tests and the full suite pass.

## Task 5: Parse Progress and Run a Cancellable FFmpeg Process

**Files:**
- Create: `Sources/MKVHomeVideoCore/FFmpeg/FFmpegProgressParser.swift`
- Create: `Sources/MKVHomeVideoCore/FFmpeg/ProcessRunner.swift`
- Create: `Tests/MKVHomeVideoCoreTests/FFmpegProgressParserTests.swift`

**Interfaces:**
- Consumes: `FFmpegCommand` and `MediaProbeResult.duration` from Task 4.
- Produces: `FFmpegProgressParser.feed(_:) -> [FFmpegProgressEvent]`, `FFmpegProcessRunning`, and `FFmpegProcessRunner.run(_:onProgress:) async throws -> ProcessOutcome` for Task 6.

- [ ] **Step 1: Write failing progress-parser tests**

```swift
import Testing
@testable import MKVHomeVideoCore

@Test("progress parser reports the measured fraction at a progress marker")
func parserReportsFraction() {
    var parser = FFmpegProgressParser(totalDurationMicroseconds: 10_000_000)
    let events = parser.feed("out_time_ms=2500000\\nprogress=continue\\n")

    #expect(events == [.updated(fraction: 0.25)])
}

@Test("partial records wait for their progress marker")
func testParserBuffersPartialRecordsUntilProgressMarker() {
    var parser = FFmpegProgressParser(totalDurationMicroseconds: 10_000_000)
    #expect(parser.feed("out_time_ms=2500000\\n") == [])
    #expect(parser.feed("progress=continue\\n") == [.updated(fraction: 0.25)])
}

@Test("end marker is reported as completion")
func parserReportsCompletion() {
    var parser = FFmpegProgressParser(totalDurationMicroseconds: 1)
    #expect(parser.feed("progress=end\\n") == [.completed])
}
```

- [ ] **Step 2: Run parser tests to verify the expected failure**

Run: `swift test --filter FFmpegProgressParserTests`

Expected: compilation fails because `FFmpegProgressParser` is undefined.

- [ ] **Step 3: Implement a buffered, bounded parser**

Use a `String` remainder buffer and a `[String: String]` current record. Split only complete newline-delimited lines; collect keys until `progress=continue` or `progress=end`. Parse FFmpeg `out_time_ms` as microseconds, clamp `fraction` to `0...1`, emit `.updated(fraction:)` only at a marker, and discard unknown keys. At `progress=end`, emit `.completed` even if no duration was available. Never interpret a malformed numeric value as complete.

- [ ] **Step 4: Verify parser tests pass**

Run: `swift test --filter FFmpegProgressParserTests`

Expected: all three tests pass.

- [ ] **Step 5: Write the failing process-runner seam test**

Add the following test-only fixtures above the runner test:

```swift
extension FFmpegCommand {
    static let fixture = FFmpegCommand(
        executableURL: URL(filePath: "/opt/homebrew/bin/ffmpeg"),
        arguments: ["-progress", "pipe:1", "/Output/Test.mp4"])
}

actor RecordingLauncher: ProcessLaunching {
    let stdoutChunks: [String]
    let exitCode: Int32

    init(stdoutChunks: [String], exitCode: Int32) {
        self.stdoutChunks = stdoutChunks
        self.exitCode = exitCode
    }

    func run(_ command: FFmpegCommand, onStdout: @escaping @Sendable (String) -> Void) async throws -> ProcessOutcome {
        stdoutChunks.forEach(onStdout)
        return exitCode == 0 ? .succeeded : .failed(exitCode: exitCode)
    }

    func cancel() {}
}
```

```swift
@Test("runner forwards parsed progress and exposes a cancellation handle")
func runnerForwardsProgress() async throws {
    let launcher = RecordingLauncher(stdoutChunks: ["out_time_ms=5000000\\nprogress=continue\\n"], exitCode: 0)
    let runner = FFmpegProcessRunner(launcher: launcher)
    var received: [FFmpegProgressEvent] = []

    let outcome = try await runner.run(.fixture, durationMicroseconds: 10_000_000) {
        received.append($0)
    }

    #expect(outcome == .succeeded)
    #expect(received == [.updated(fraction: 0.5)])
}
```

- [ ] **Step 6: Run the runner seam test to verify the expected failure**

Run: `swift test --filter FFmpegProgressParserTests/runnerForwardsProgress`

Expected: compilation fails because `FFmpegProcessRunner` and `RecordingLauncher` do not exist.

- [ ] **Step 7: Implement injectable process launching and cancellation**

Define a narrow async `ProcessLaunching: Sendable` protocol with `run(_:onStdout:) async throws -> ProcessOutcome` and `cancel()`. It streams stdout chunks through the callback and returns `.succeeded` or `.failed(exitCode:)`; cancellation produces `.cancelled`. Provide `FoundationProcessLauncher` using `Process`, a `Pipe`, `readabilityHandler`, and `terminationHandler`; never construct a shell command string. `FFmpegProcessRunner` injects a launcher, owns the parser, sends events to `onProgress`, and exposes `cancel()` by forwarding it to the launcher. The test-only `RecordingLauncher` shown in Step 5 belongs in the test target.

- [ ] **Step 8: Verify runner and full suite**

Run: `swift test --filter FFmpegProgressParserTests && swift test`

Expected: parser/runner tests and all earlier tests pass.

## Task 6: Persist and Execute the Sequential Queue

**Files:**
- Create: `Sources/MKVHomeVideoCore/Queue/QueueProjectStore.swift`
- Create: `Sources/MKVHomeVideoCore/Queue/ConversionQueueController.swift`
- Create: `Tests/MKVHomeVideoCoreTests/QueueProjectStoreTests.swift`
- Create: `Tests/MKVHomeVideoCoreTests/ConversionQueueControllerTests.swift`

**Interfaces:**
- Consumes: `ConversionJob`, `FFmpegProcessRunner`, `OutputPathResolver`, and resolved metadata from Tasks 2–5.
- Produces: `QueueProject`, `QueueProjectStore.save(_:)`, `QueueProjectStore.load()`, and `@MainActor ConversionQueueController` methods `start()`, `pauseAfterCurrent()`, `skip(_:)`, `retry(_:)`, and `restore()` for the app view model.

- [ ] **Step 1: Write failing project-store tests**

At the top of `QueueProjectStoreTests.swift`, add a test-only temporary directory helper:

```swift
struct TemporaryDirectory {
    let url: URL

    static func make() throws -> Self {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return Self(url: url)
    }
}
```

```swift
import Testing
@testable import MKVHomeVideoCore

@Test("queue project saves and loads atomically")
func projectRoundTrips() throws {
    let directory = try TemporaryDirectory.make()
    let store = QueueProjectStore(fileURL: directory.url.appending(path: "queue.json"))
    let project = QueueProject(destinationDirectory: URL(filePath: "/Exports"),
                               jobs: [ConversionJob.fixture(status: .queued)])

    try store.save(project)
    #expect(try store.load() == project)
}

@Test("interrupted running work becomes queued on load")
func testLoadRequeuesInterruptedRunningJob() throws {
    let directory = try TemporaryDirectory.make()
    let store = QueueProjectStore(fileURL: directory.url.appending(path: "queue.json"))
    try store.save(QueueProject(destinationDirectory: URL(filePath: "/Exports"),
                                jobs: [ConversionJob.fixture(status: .running, progress: 0.62)]))

    let restored = try store.load()
    #expect(restored.jobs[0].status == .queued)
    #expect(restored.jobs[0].progress == 0)
}
```

- [ ] **Step 2: Run the store tests to verify the expected failure**

Run: `swift test --filter QueueProjectStoreTests`

Expected: compilation fails because project storage types do not exist.

- [ ] **Step 3: Implement atomic local project storage**

Define `QueueProject: Codable, Equatable` with `destinationDirectory`, `jobs`, and `savedAt`. `QueueProjectStore.save(_:)` encodes with sorted keys, writes to a unique sibling temporary URL, then replaces/moves it atomically. `load()` returns an empty project when no file exists, decodes otherwise, and normalizes each `.running` job to `.queued` with zero progress and no stale error. Convert invalid JSON to `QueueProjectStoreError.corruptProject` rather than losing the file.

- [ ] **Step 4: Verify project-store tests pass**

Run: `swift test --filter QueueProjectStoreTests`

Expected: both project-store tests pass.

- [ ] **Step 5: Write failing queue-controller tests**

At the top of `ConversionQueueControllerTests.swift`, add these test-only values. `ControlledRunner` will conform to the production `ConversionRunning` protocol created in Step 7:

```swift
extension ConversionJob {
    static func fixture(status: JobStatus = .queued, progress: Double = 0) -> Self {
        var job = ConversionJob(sourceURL: URL(filePath: "/Media/Test.mkv"),
                                destinationURL: URL(filePath: "/Exports/Test.mp4"))
        job.status = status
        job.progress = progress
        return job
    }
}

extension QueueProject {
    static func fixture(twoQueuedJobs: Bool) -> Self {
        let jobs = twoQueuedJobs
            ? [ConversionJob.fixture(), ConversionJob.fixture()]
            : [ConversionJob.fixture()]
        return QueueProject(destinationDirectory: URL(filePath: "/Exports"), jobs: jobs)
    }
}

actor ControlledRunner: ConversionRunning {
    private var outcomes: [ProcessOutcome]
    private(set) var activeRuns = 0
    private(set) var maximumConcurrentRuns = 0

    init(outcomes: [ProcessOutcome] = [.succeeded]) { self.outcomes = outcomes }

    func run(_ command: FFmpegCommand, durationMicroseconds: Int64?, onProgress: @escaping @Sendable (FFmpegProgressEvent) -> Void) async throws -> ProcessOutcome {
        activeRuns += 1
        maximumConcurrentRuns = max(maximumConcurrentRuns, activeRuns)
        defer { activeRuns -= 1 }
        return outcomes.isEmpty ? .succeeded : outcomes.removeFirst()
    }
}
```

```swift
@Test("queue runs one job at a time and continues after success")
@MainActor
func queueRunsSequentially() async throws {
    let runner = ControlledRunner(outcomes: [.succeeded, .succeeded])
    let controller = ConversionQueueController(project: .fixture(twoQueuedJobs: true), runner: runner)

    await controller.start()

    #expect(controller.jobs.map(\.status) == [.completed, .completed])
    let maximumConcurrentRuns = await runner.maximumConcurrentRuns
    #expect(maximumConcurrentRuns == 1)
}

@Test("retry makes a failed job eligible without changing its metadata")
@MainActor
func retryPreservesJobMetadata() {
    var project = QueueProject.fixture(twoQueuedJobs: false)
    project.jobs[0].status = .failed
    project.jobs[0].lastError = "AAC encoder failed"
    let controller = ConversionQueueController(project: project, runner: ControlledRunner())

    let expectedMetadata = controller.jobs[0].metadataOverride
    controller.retry(controller.jobs[0].id)

    #expect(controller.jobs[0].status == .queued)
    #expect(controller.jobs[0].lastError == nil)
    #expect(controller.jobs[0].metadataOverride == expectedMetadata)
}
```

- [ ] **Step 6: Run the controller tests to verify the expected failure**

Run: `swift test --filter ConversionQueueControllerTests`

Expected: compilation fails because the queue controller and test runner are missing.

- [ ] **Step 7: Implement the main-actor state machine**

Define `ConversionRunning: Sendable` with `run(_:durationMicroseconds:onProgress:) async throws -> ProcessOutcome`, and conform `FFmpegProcessRunner` to it. Make `ConversionQueueController` observable on `MainActor`. It owns project state and injects this command-producing conversion service rather than embedding FFmpeg arguments. `start()` finds the first `.queued` job, marks only that job `.running`, persists, awaits the runner, records outcome, persists, and repeats unless `pauseAfterCurrent` became true. `skip(_:)` only changes queued/failed jobs to `.skipped`; `retry(_:)` clears `lastError`, zeroes progress, and makes a failed/skipped job queued; completed jobs are immutable. Calculate aggregate progress as completed units plus the current fraction over total jobs.

The test-only `ControlledRunner` must record concurrent invocations and use prescribed outcomes; do not substitute mock assertions for state assertions.

- [ ] **Step 8: Verify queue behavior and full suite**

Run: `swift test --filter ConversionQueueControllerTests && swift test`

Expected: controller tests pass and the full suite is green.

## Task 7: Build the SwiftUI Utility and Native Preview

**Files:**
- Create: `Sources/MKVHomeVideoCore/Queue/AppViewModel.swift`
- Create: `Sources/MKVHomeVideoApp/Views/SetupView.swift`
- Create: `Sources/MKVHomeVideoApp/Views/QueueView.swift`
- Create: `Sources/MKVHomeVideoApp/Views/QueueRowView.swift`
- Create: `Sources/MKVHomeVideoApp/Views/MetadataEditorView.swift`
- Create: `Sources/MKVHomeVideoApp/Views/PreviewView.swift`
- Modify: `Sources/MKVHomeVideoApp/MKVHomeVideoApp.swift`
- Create: `Tests/MKVHomeVideoCoreTests/AppViewModelTests.swift`

**Interfaces:**
- Consumes: toolchain locator, intake resolver, queue controller, and metadata values from Tasks 2–6.
- Produces: a desktop app whose UI operations call the tested core interfaces; no new conversion policy belongs in a view.

- [ ] **Step 1: Write failing view-model tests for setup and imports**

At the top of `AppViewModelTests.swift`, define a test-only provider that conforms to the production `ToolchainProviding` protocol created in Step 3:

```swift
struct TestToolchainProvider: ToolchainProviding {
    let result: Result<FFmpegToolchain, FFmpegToolchainLocatorError>
    func locateToolchain() -> Result<FFmpegToolchain, FFmpegToolchainLocatorError> { result }

    static let fixture = TestToolchainProvider(result: .success(.fixture))
    static let missing = TestToolchainProvider(result: .failure(.notInstalled(setupCommand: "brew install ffmpeg")))
}
```

```swift
import Testing
@testable import MKVHomeVideoCore

@Test("missing toolchain enters setup state with Homebrew guidance")
@MainActor
func missingToolchainShowsSetup() {
    let model = AppViewModel(toolchainProvider: .missing)
    model.refreshToolchain()

    #expect(model.screen == .setup)
    #expect(model.setupCommand == "brew install ffmpeg")
}

@Test("adding sources creates queued jobs with safe destinations")
@MainActor
func addingSourcesCreatesQueuedJobs() throws {
    let model = AppViewModel(toolchainProvider: .fixture,
                             destinationDirectory: URL(filePath: "/Exports"))
    try model.addSources([URL(filePath: "/Media/Arrival.mkv")])

    #expect(model.jobs.count == 1)
    #expect(model.jobs[0].status == .queued)
    #expect(model.jobs[0].destinationURL.path == "/Exports/Arrival.mp4")
}
```

- [ ] **Step 2: Run view-model tests to verify the expected failure**

Run: `swift test --filter AppViewModelTests`

Expected: compilation fails because `AppViewModel` is not in a testable target.

- [ ] **Step 3: Move only UI-independent view-model policy into the core target and implement it**

Put `AppViewModel` in `MKVHomeVideoCore` so it can be tested; it may import Observation/Foundation but not SwiftUI. Define `ToolchainProviding` with `locateToolchain() -> Result<FFmpegToolchain, FFmpegToolchainLocatorError>` and a production locator-backed implementation. Give the view model injectable `ToolchainProviding`, `QueueProjectStore`, and destination dependencies. Its `screen` is `.setup` or `.queue`; `refreshToolchain()` displays the exact Homebrew command for a missing toolchain; `addSources(_:)` uses `MediaFileIntake` and `OutputPathResolver`, then creates queued jobs with `.movie` as the editable default profile. Keep platform file-import panels and AVPlayer code in the app target.

- [ ] **Step 4: Verify view-model tests pass**

Run: `swift test --filter AppViewModelTests`

Expected: both tests pass.

- [ ] **Step 5: Implement the SwiftUI views over the tested model**

Replace the placeholder app window with `AppViewModel` ownership. `SetupView` presents missing-tool guidance, copyable `brew install ffmpeg` text, a Refresh button, and a custom FFmpeg file picker. `QueueView` uses `fileImporter` for files/folders plus `onDrop` for URL drops, a destination picker, Start/Pause/Retry Failed controls, aggregate progress, and a `Table`/`List` of `QueueRowView` items. Folder selection expands recursively via an app-target file enumerator before calling `addSources(_:)`.

`MetadataEditorView` supports the shared selection patch and an individual override sheet. Offer the approved Movie/TV Episode fields, artwork picker limited to JPEG/PNG, clear inheritance labels, validation for required title/episode ordering, and Save/Cancel actions. `QueueRowView` exposes Edit, Preview, Reveal, Remove, Retry, and Skip only when the job state permits it.

`PreviewView` builds an `AVPlayer` for the selected source/output URL. If `AVURLAsset.isPlayable` is false after loading, display "This MKV cannot be previewed natively. Convert it to make a compatible MP4." and a Convert action; do not launch external software. Dispose the player when its sheet closes.

- [ ] **Step 6: Build the app target and run all core tests**

Run: `swift test && swift build -c debug`

Expected: complete test suite passes and the SwiftUI executable target builds with no warnings.

- [ ] **Step 7: Perform a UI smoke pass without FFmpeg**

Run: `swift run MKVHomeVideoApp`

Expected: the missing-FFmpeg setup screen renders, shows the exact Homebrew command, accepts a custom-path selection, and does not crash when cancelled. Stop the app normally after this check.

## Task 8: Package, Verify, and Test a Real Conversion

**Files:**
- Modify: `Scripts/build-app.sh`
- Modify: `Resources/Info.plist`
- Modify: `README.md`
- Create: `Sources/MKVHomeVideoCore/Domain/PackagingInfo.swift`

**Interfaces:**
- Consumes: the completed executable target and tested core behavior.
- Produces: `dist/MKV Home Video.app` and concise local setup/run instructions.

- [ ] **Step 1: Write a failing package-artifact test**

Add `Tests/MKVHomeVideoCoreTests/PackagingTests.swift` with a test that resolves `Resources/Info.plist` from the repository and asserts the bundle identifier and minimum macOS version match `AppIdentity` and `26.0`. Use a repository-root URL passed through `MKV_REPOSITORY_ROOT` in the test command so the test never depends on the current directory.

```swift
@Test("bundle plist agrees with the core app identity")
func plistUsesAppIdentity() throws {
    let plist = try PackagingInfo.load(fromRepositoryRoot: try #require(ProcessInfo.processInfo.environment["MKV_REPOSITORY_ROOT"]))
    #expect(plist.bundleIdentifier == AppIdentity.bundleIdentifier)
    #expect(plist.minimumSystemVersion == "26.0")
}
```

- [ ] **Step 2: Run it to verify the expected failure**

Run: `MKV_REPOSITORY_ROOT="$PWD" swift test --filter PackagingTests/plistUsesAppIdentity`

Expected: compilation failure because `PackagingInfo` is not defined.

- [ ] **Step 3: Implement the smallest plist reader and harden the packaging script**

Create `PackagingInfo` in the core target using `PropertyListSerialization` to read the two tested strings. In `Scripts/build-app.sh`, quote all paths, remove only the explicit `dist/MKV Home Video.app` target before rebuilding it, and fail if the release executable or plist is absent. Run `chmod +x Scripts/build-app.sh`; it must not depend on FFmpeg being installed.

Write a `README.md` containing exactly: prerequisites (Xcode command-line tools and `brew install ffmpeg`), build command `Scripts/build-app.sh`, bundle path, first-launch tool detection, supported batch/metadata workflow, and the limitation that Apple TV determines which imported tags it displays.

- [ ] **Step 4: Verify the package artifact test, full suite, release build, and bundle layout**

Run:

```bash
MKV_REPOSITORY_ROOT="$PWD" swift test
swift build -c release
Scripts/build-app.sh
test -x "dist/MKV Home Video.app/Contents/MacOS/MKVHomeVideoApp"
test -f "dist/MKV Home Video.app/Contents/Info.plist"
```

Expected: tests/build succeed, the app bundle exists with its executable and plist, and no source MKV is changed.

- [ ] **Step 5: Install FFmpeg and manually validate conversion only with user authorization**

After the user runs `brew install ffmpeg`, launch the built bundle, add a disposable local MKV, choose a new output directory, fill a Movie or TV Episode metadata form with optional cover art, and convert. Confirm the source hash/path is unchanged, FFmpeg progress advances, the output MP4 plays in `PreviewView`, and inspect it with:

```bash
ffprobe -v error -show_entries format=format_name:format_tags -of json "OUTPUT.mp4"
```

Expected: `format_name` contains `mov,mp4,m4a,3gp,3g2,mj2`, the app records completion, and submitted non-empty metadata tags are present where FFmpeg exposes them. Reveal the output for manual Apple TV import; do not automate the import.

- [ ] **Step 6: Record the final verification checkpoint**

Report the exact passing test count, release build result, app-bundle path, whether FFmpeg was installed, and any Apple TV display-field behavior that requires user confirmation. The workspace remains non-Git, so do not fabricate commit hashes.

## Self-Review

- **Spec coverage:** Task 2 covers movie/episode/Home Video metadata and inheritance; Task 3 covers MKV intake and output safety; Task 4 covers FFmpeg/ffprobe discovery, compatibility encoding, subtitle policy, tags, and artwork; Task 5 covers progress/cancellation; Task 6 covers sequential batching, recovery, and JSON persistence; Task 7 covers setup, queue, editing, drag/drop, preview, and user actions; Task 8 covers the `.app`, README, full verification, and authorized manual conversion.
- **Placeholder scan:** The plan contains no deferred implementation markers. Each behavior is assigned a file, signature, test, expected red result, and expected green verification.
- **Type consistency:** `ResolvedVideoMetadata`, `ConversionJob`, `FFmpegToolchain`, `MediaProbeResult`, `FFmpegCommand`, `FFmpegProcessRunner`, `QueueProject`, `ConversionQueueController`, and `AppViewModel` are introduced before later tasks consume them.
- **Review focus coverage:** The five high-risk conditions named above are each pinned to a specific test in Tasks 3–6.
