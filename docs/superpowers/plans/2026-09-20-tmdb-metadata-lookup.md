# TMDB Metadata Lookup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add opt-in TMDB movie and TV-episode lookup to the individual metadata editor, securely using a TMDB API Read Access Token stored in the macOS Keychain.

**Architecture:** Keep TMDB mechanics in focused `MKVHomeVideoCore/TMDB` types: a Keychain-backed credential store, filename parser, URLSession API client, artwork cache, and observable lookup model. The SwiftUI editor receives the model, starts no request until the user presses Search TMDB, and applies the model's patch only when the user chooses a result.

**Tech Stack:** Swift 6.2, Swift Testing, Foundation/URLSession, Observation, Security framework, SwiftUI, TMDB v3 JSON API authenticated by a v4 API Read Access Token bearer header.

**Spec:** `docs/superpowers/specs/2026-09-20-tmdb-metadata-lookup-design.md`

## Global Constraints

- Target macOS 26.0 and Swift 6.2; add no package dependencies.
- Store only the TMDB API Read Access Token, using `Authorization: Bearer`; do not store or use the legacy TMDB API key.
- Never write a token to source, tests, fixtures, logs, URLs, `UserDefaults`, a queue project, or a Git-tracked file.
- Issue no TMDB request until the user presses **Search TMDB** or explicitly applies a selected result.
- Keep all current metadata manual and editable; missing TMDB fields must not clear existing editor values.
- Store applied poster/still artwork locally under Application Support so FFmpeg export has no network dependency.
- Use `https://api.themoviedb.org/3`, `language=en-US`, JSON responses, and clear user-facing errors.
- Add a visible About/Credits view with an approved, unmodified TMDB logo and this notice: `This product uses the TMDB API but is not endorsed or certified by TMDB.`
- Do not make a live TMDB request in tests.

## Review Focus

- A filename with dots, underscores, release tags, and a lowercase `s02e03` must yield an editable clean query plus season 2/episode 3; add this in Task 1.
- An apostrophe, ampersand, or spaces in a search query must be percent-encoded by `URLComponents`, never concatenated into the URL; add this in Task 3.
- A rejected token must show a replacement-token error without exposing its value; add this in Task 3 and Task 4.
- A TV result with no detected episode must apply series metadata but must not invent an episode; add this in Task 3 and Task 4.
- A failed poster download must preserve the current artwork while still allowing the other selected metadata to apply; add this in Task 4.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `Sources/MKVHomeVideoCore/TMDB/TMDBFilenameParser.swift` | Derive an editable query and optional SxxEyy values from a source filename. |
| `Sources/MKVHomeVideoCore/TMDB/TMDBModels.swift` | App-owned search/detail/result/error types; isolates UI and metadata mapping from TMDB JSON. |
| `Sources/MKVHomeVideoCore/TMDB/TMDBCredentialStore.swift` | Credential-store protocol and macOS Keychain implementation. |
| `Sources/MKVHomeVideoCore/TMDB/TMDBArtworkStore.swift` | Application Support image persistence with safe filenames. |
| `Sources/MKVHomeVideoCore/TMDB/TMDBClient.swift` | Testable API-client protocol and `URLSession` implementation for search, details, episode details, and image bytes. |
| `Sources/MKVHomeVideoCore/TMDB/TMDBMetadataMapper.swift` | Convert TMDB detail types into `VideoMetadataPatch` values. |
| `Sources/MKVHomeVideoCore/TMDB/TMDBLookupModel.swift` | Main-actor observable state machine that coordinates secure token configuration, search, details, mapping, and artwork. |
| `Sources/MKVHomeVideoApp/TMDBDependencies.swift` | Production composition root shared by queue/editor sheets. |
| `Sources/MKVHomeVideoApp/MKVHomeVideoApp.swift` | Create and inject the production TMDB dependency container. |
| `Sources/MKVHomeVideoApp/Views/QueueView.swift` | Pass the shared dependency container to each individual editor. |
| `Sources/MKVHomeVideoApp/Views/MetadataEditorView.swift` | Render token controls, editable query, results, error/progress state, and apply the returned patch. |
| `Sources/MKVHomeVideoApp/Views/TMDBAttributionView.swift` | Show TMDB's approved logo, mandatory notice, and a link to TMDB in the app's About/Credits sheet. |
| `Resources/tmdb-logo.svg` | Unmodified approved TMDB primary full blue SVG downloaded from TMDB's logo page. |
| `Scripts/build-app.sh` | Copy the TMDB SVG into the built app bundle resources. |
| `Tests/MKVHomeVideoCoreTests/TMDBFilenameParserTests.swift` | Parser edge-case coverage. |
| `Tests/MKVHomeVideoCoreTests/TMDBCredentialStoreTests.swift` | Credential protocol/fake behavior and token validation coverage. |
| `Tests/MKVHomeVideoCoreTests/TMDBClientTests.swift` | Request construction, JSON decoding, and HTTP-failure behavior through a custom `URLProtocol`. |
| `Tests/MKVHomeVideoCoreTests/TMDBMetadataMapperTests.swift` | Mapping and partial-field behavior. |
| `Tests/MKVHomeVideoCoreTests/TMDBLookupModelTests.swift` | User-flow state, result application, and artwork-failure coverage with fakes. |
| `README.md` | Explain the optional TMDB lookup, token setup, no-token behavior, and TMDB attribution. |

### Task 1: Add TMDB domain models, filename suggestion, and metadata mapping

**Files:**
- Create: `Sources/MKVHomeVideoCore/TMDB/TMDBModels.swift`
- Create: `Sources/MKVHomeVideoCore/TMDB/TMDBFilenameParser.swift`
- Create: `Sources/MKVHomeVideoCore/TMDB/TMDBMetadataMapper.swift`
- Create: `Tests/MKVHomeVideoCoreTests/TMDBFilenameParserTests.swift`
- Create: `Tests/MKVHomeVideoCoreTests/TMDBMetadataMapperTests.swift`

**Interfaces:**
- Consumes: `MediaProfile` and `VideoMetadataPatch` from `Sources/MKVHomeVideoCore/Domain/VideoMetadata.swift`.
- Produces: `TMDBSearchSuggestion`, `TMDBMediaType`, `TMDBSearchResult`, `TMDBMovieDetails`, `TMDBTVDetails`, `TMDBEpisodeDetails`, `TMDBArtwork`, `TMDBSelection`, and `TMDBMetadataMapper.patch(for:)` for Tasks 3 and 4.

- [ ] **Step 1: Write the parser and mapper tests first**

```swift
@Test("filename parser strips release tags and detects a case-insensitive episode")
func parsesTVFilename() {
    let suggestion = TMDBFilenameParser.suggestion(
        for: URL(filePath: "/Media/The.Last.of.Us.s02e03.2160p.WEB-DL.mkv")
    )

    #expect(suggestion.query == "The Last of Us")
    #expect(suggestion.seasonNumber == 2)
    #expect(suggestion.episodeNumber == 3)
}

@Test("movie mapping leaves unavailable fields nil instead of clearing metadata")
func mapsPartialMovieWithoutClears() {
    let patch = TMDBMetadataMapper.patch(for: .movie(.fixture(title: "Arrival", overview: nil)))

    #expect(patch.title == "Arrival")
    #expect(patch.description == nil)
    #expect(patch.clearedFields.isEmpty)
}
```

- [ ] **Step 2: Run the focused tests to verify they fail because the TMDB types do not exist**

Run: `swift test --filter TMDBFilenameParserTests`

Expected: compilation fails with `cannot find 'TMDBFilenameParser' in scope`.

- [ ] **Step 3: Implement the small app-owned types and pure transforms**

```swift
public struct TMDBSearchSuggestion: Sendable, Equatable {
    public let query: String
    public let seasonNumber: Int?
    public let episodeNumber: Int?
}

public enum TMDBMediaType: String, Sendable, Equatable {
    case movie
    case tv
}

public struct TMDBArtwork: Sendable, Equatable {
    public let mediaIdentifier: String
    public let imageURL: URL
    public let fileExtension: String
}

public struct TMDBSearchResult: Sendable, Equatable, Identifiable {
    public let id: Int
    public let mediaType: TMDBMediaType
    public let title: String
    public let year: String?
    public let overview: String?
    public let artwork: TMDBArtwork?
}

public struct TMDBMovieDetails: Sendable, Equatable {
    public let id: Int
    public let title: String
    public let originalTitle: String?
    public let overview: String?
    public let genres: [String]
    public let releaseDate: String?
    public let collectionName: String?
    public let director: String?
    public let cast: String?
    public let studio: String?
    public let artwork: TMDBArtwork?
}

public struct TMDBTVDetails: Sendable, Equatable {
    public let id: Int
    public let name: String
    public let originalName: String?
    public let overview: String?
    public let genres: [String]
    public let network: String?
    public let artwork: TMDBArtwork?
}

public struct TMDBEpisodeDetails: Sendable, Equatable {
    public let name: String?
    public let overview: String?
    public let airDate: String?
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let artwork: TMDBArtwork?
}

public enum TMDBFilenameParser {
    public static func suggestion(for sourceURL: URL) -> TMDBSearchSuggestion {
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let episode = episodeMatch(in: stem)
        let title = cleanedTitle(from: stem, removing: episode?.range)
        return TMDBSearchSuggestion(
            query: title,
            seasonNumber: episode?.seasonNumber,
            episodeNumber: episode?.episodeNumber
        )
    }
}

public enum TMDBSelection: Sendable, Equatable {
    case movie(TMDBMovieDetails)
    case tvSeries(TMDBTVDetails, seasonNumber: Int?, episodeNumber: Int?)
    case episode(TMDBTVDetails, TMDBEpisodeDetails)
}

public enum TMDBMetadataMapper {
    public static func patch(for selection: TMDBSelection) -> VideoMetadataPatch {
        switch selection {
        case .movie(let movie):
            VideoMetadataPatch(title: movie.title, sortTitle: movie.originalTitle,
                description: movie.overview, genre: joined(movie.genres),
                releaseDate: movie.releaseDate, collectionName: movie.collectionName,
                director: movie.director, cast: movie.cast, studio: movie.studio)
        case .tvSeries(let series, let season, let episode):
            VideoMetadataPatch(showName: series.name, showSortName: series.originalName,
                description: series.overview, genre: joined(series.genres),
                seasonNumber: season, episodeNumber: episode, network: series.network)
        case .episode(let series, let episode):
            VideoMetadataPatch(showName: series.name, showSortName: series.originalName,
                description: episode.overview, genre: joined(series.genres),
                episodeTitle: episode.name, seasonNumber: episode.seasonNumber,
                episodeNumber: episode.episodeNumber, episodeSort: episode.episodeNumber,
                airDate: episode.airDate, network: series.network)
        }
    }

    private static func joined(_ values: [String]) -> String? {
        values.isEmpty ? nil : values.joined(separator: ", ")
    }
}
```

Implement the parser without network or UI dependencies. Remove the extension, detect `S(\\d{1,2})E(\\d{1,2})` before stripping release terms, normalize separators, then remove common quality/source tags only when they are whole tokens. Define explicit `Codable` detail fields needed by the mapper: titles/names, dates, overview, genres, production companies/networks, credits, collection, poster/still paths, and integer identifiers. Make all resulting public value types `Sendable` and `Equatable`.

- [ ] **Step 4: Run the new parser and mapper tests**

Run: `swift test --filter 'TMDBFilenameParserTests|TMDBMetadataMapperTests'`

Expected: PASS. Confirm movie and TV mappings do not introduce `clearedFields` and do not make a TV episode number when none exists.

- [ ] **Step 5: Commit the pure TMDB domain layer**

```bash
git add Sources/MKVHomeVideoCore/TMDB/TMDBModels.swift \
  Sources/MKVHomeVideoCore/TMDB/TMDBFilenameParser.swift \
  Sources/MKVHomeVideoCore/TMDB/TMDBMetadataMapper.swift \
  Tests/MKVHomeVideoCoreTests/TMDBFilenameParserTests.swift \
  Tests/MKVHomeVideoCoreTests/TMDBMetadataMapperTests.swift
git commit -m "feat: add TMDB metadata domain types"
```

### Task 2: Implement secure credential and local artwork storage

**Files:**
- Create: `Sources/MKVHomeVideoCore/TMDB/TMDBCredentialStore.swift`
- Create: `Sources/MKVHomeVideoCore/TMDB/TMDBArtworkStore.swift`
- Create: `Tests/MKVHomeVideoCoreTests/TMDBCredentialStoreTests.swift`

**Interfaces:**
- Consumes: `Foundation`, `Security`, `TMDBArtwork` from Task 1.
- Produces: `TMDBCredentialStoring`, `KeychainTMDBCredentialStore`, `TMDBArtworkStoring`, and `TMDBArtworkStore` for Tasks 3 and 4.

- [ ] **Step 1: Write failing contract tests using a test-double store and a temporary Application Support directory**

```swift
@Test("saving a blank TMDB token is rejected before it reaches a store")
func rejectsBlankToken() throws {
    let store = InMemoryCredentialStore()
    #expect(throws: TMDBCredentialStoreError.invalidToken) {
        try store.saveToken("   ")
    }
}

@Test("artwork store writes a local JPEG using a stable safe name")
func storesArtworkLocally() throws {
    let directory = try makeTemporaryDirectory()
    let store = TMDBArtworkStore(baseDirectory: directory)

    let url = try store.save(data: Data([0xFF, 0xD8]), mediaIdentifier: "movie-329865", fileExtension: "jpg")

    #expect(url.deletingLastPathComponent() == directory)
    #expect(url.lastPathComponent == "movie-329865.jpg")
}
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `swift test --filter TMDBCredentialStoreTests`

Expected: compilation fails because the credential and artwork store types do not exist.

- [ ] **Step 3: Implement the Keychain protocol boundary and artwork persistence**

```swift
public protocol TMDBCredentialStoring: Sendable {
    func token() throws -> String?
    func saveToken(_ token: String) throws
    func deleteToken() throws
}

public protocol TMDBArtworkStoring: Sendable {
    func save(data: Data, mediaIdentifier: String, fileExtension: String) throws -> URL
}
```

Use a `KeychainTMDBCredentialStore` production type that reads/writes a generic-password Keychain item with service `com.peterbertella.MKVHomeVideo.tmdb` and account `api-read-access-token`; use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Trim and reject an empty token, update an existing item rather than creating duplicates, and convert unexpected OSStatus values into `TMDBCredentialStoreError` without including token data. `TMDBArtworkStore` must use `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`, append an app subdirectory, make it as needed, whitelist `jpg`, `jpeg`, and `png` extensions, and write atomically.

- [ ] **Step 4: Run storage tests and the existing metadata suite**

Run: `swift test --filter 'TMDBCredentialStoreTests|VideoMetadataTests'`

Expected: PASS. Confirm test helpers never instantiate the production Keychain store and no test data resembles a real token.

- [ ] **Step 5: Commit secure local storage**

```bash
git add Sources/MKVHomeVideoCore/TMDB/TMDBCredentialStore.swift \
  Sources/MKVHomeVideoCore/TMDB/TMDBArtworkStore.swift \
  Tests/MKVHomeVideoCoreTests/TMDBCredentialStoreTests.swift
git commit -m "feat: store TMDB credentials and artwork locally"
```

### Task 3: Build the authenticated TMDB API client

**Files:**
- Create: `Sources/MKVHomeVideoCore/TMDB/TMDBClient.swift`
- Create: `Tests/MKVHomeVideoCoreTests/TMDBClientTests.swift`
- Modify: `Sources/MKVHomeVideoCore/TMDB/TMDBModels.swift`

**Interfaces:**
- Consumes: `TMDBCredentialStoring` from Task 2; search/detail types from Task 1.
- Produces: `TMDBSearching` with `search(query:profile:)`, `selection(for:searchResult:seasonNumber:episodeNumber:)`, and `downloadArtwork(_:)` for Task 4.

- [ ] **Step 1: Write failing URLProtocol-backed client tests with non-sensitive JSON fixtures**

```swift
@Test("movie search sends an encoded query and bearer header")
func movieSearchUsesBearerAuthentication() async throws {
    let recorder = URLProtocolRecorder(statusCode: 200, body: movieSearchFixture)
    let client = TMDBAPIClient(session: recorder.session, credentials: InMemoryCredentialStore(token: "test-token"))

    _ = try await client.search(query: "Me & You", profile: .movie)

    #expect(recorder.request?.url?.query?.contains("query=Me%20%26%20You") == true)
    #expect(recorder.request?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
}

@Test("unauthorized response does not include a token in its error")
func rejectedTokenIsSafe() async {
    let client = TMDBAPIClient(session: failingSession(statusCode: 401), credentials: InMemoryCredentialStore(token: "not-for-logs"))

    await #expect(throws: TMDBError.unauthorized) {
        _ = try await client.search(query: "Arrival", profile: .movie)
    }
}
```

- [ ] **Step 2: Run the client tests to verify they fail**

Run: `swift test --filter TMDBClientTests`

Expected: compilation fails with `cannot find 'TMDBAPIClient' in scope`.

- [ ] **Step 3: Implement the protocol, URL construction, decoding, and error mapping**

```swift
public protocol TMDBSearching: Sendable {
    func search(query: String, profile: MediaProfile) async throws -> [TMDBSearchResult]
    func selection(
        for result: TMDBSearchResult,
        seasonNumber: Int?,
        episodeNumber: Int?
    ) async throws -> TMDBSelection
    func downloadArtwork(_ artwork: TMDBArtwork) async throws -> Data
}
```

Use a `TMDBAPIClient` that obtains its token immediately before each request. Build URLs with `URLComponents`; set `language=en-US`, `include_adult=false`, and `Accept: application/json`. Use `/search/movie` for movies and `/search/tv` for TV. Detail requests use `/movie/{id}?append_to_response=credits,images` or `/tv/{id}?append_to_response=credits,images`; when both episode numbers are supplied, request `/tv/{id}/season/{season}/episode/{episode}?append_to_response=images`. Map 401 to `.unauthorized`, 403 to `.forbidden`, any status outside `200..<300` to a safe API error, malformed successful JSON to `.invalidResponse`, and transport failures to `.networkUnavailable`. Include no token, raw Authorization header, or full request URL in any error description. Build artwork URLs only from TMDB image paths with the fixed `https://image.tmdb.org/t/p/w500` base.

- [ ] **Step 4: Run the API-client tests**

Run: `swift test --filter TMDBClientTests`

Expected: PASS. Confirm search queries are encoded, each request carries the bearer header, movie/TV routes differ, `SxxEyy` routes to the episode endpoint, and 401/403 errors are safe.

- [ ] **Step 5: Commit the API client**

```bash
git add Sources/MKVHomeVideoCore/TMDB/TMDBClient.swift \
  Sources/MKVHomeVideoCore/TMDB/TMDBModels.swift \
  Tests/MKVHomeVideoCoreTests/TMDBClientTests.swift
git commit -m "feat: add authenticated TMDB API client"
```

### Task 4: Add the observable lookup model and apply flow

**Files:**
- Create: `Sources/MKVHomeVideoCore/TMDB/TMDBLookupModel.swift`
- Create: `Tests/MKVHomeVideoCoreTests/TMDBLookupModelTests.swift`

**Interfaces:**
- Consumes: parser and mapper from Task 1; credential/artwork stores from Task 2; `TMDBSearching` from Task 3.
- Produces: `@MainActor @Observable TMDBLookupModel`, `TMDBLookupState`, and `TMDBAppliedMetadata` for Task 5.

- [ ] **Step 1: Write failing state-machine tests with fake API and storage implementations**

```swift
@Test("lookup does not make a request until search is explicitly invoked")
@MainActor
func waitsForSearchButton() {
    let client = FakeTMDBClient()
    _ = TMDBLookupModel(sourceURL: URL(filePath: "/Media/Arrival.2016.mkv"), client: client, credentials: InMemoryCredentialStore())

    #expect(client.searchCalls == 0)
}

@Test("artwork download failure still returns a metadata patch without replacing artwork")
@MainActor
func appliesFieldsWhenArtworkFails() async throws {
    let model = TMDBLookupModel(sourceURL: URL(filePath: "/Media/Arrival.mkv"), client: FakeTMDBClient(artworkError: .networkUnavailable), credentials: InMemoryCredentialStore(token: "test-token"))
    await model.search(profile: .movie)
    model.selectedResultID = 329865
    let applied = await model.applySelectedResult(profile: .movie)

    #expect(applied?.patch.title == "Arrival")
    #expect(applied?.artworkURL == nil)
    #expect(model.notice == "Metadata applied, but artwork could not be downloaded.")
}
```

- [ ] **Step 2: Run the lookup-model tests to verify they fail**

Run: `swift test --filter TMDBLookupModelTests`

Expected: compilation fails because `TMDBLookupModel` and `TMDBAppliedMetadata` do not exist.

- [ ] **Step 3: Implement the main-actor model with explicit user-facing states**

```swift
public enum TMDBLookupState: Equatable {
    case idle
    case searching
    case applying
    case failed(String)
}

public struct TMDBAppliedMetadata: Sendable, Equatable {
    public let patch: VideoMetadataPatch
    public let artworkURL: URL?
}

@MainActor
@Observable
public final class TMDBLookupModel {
    public var query: String
    public var seasonNumber: String
    public var episodeNumber: String
    public private(set) var tokenConfigured: Bool
    public private(set) var state: TMDBLookupState
    public private(set) var results: [TMDBSearchResult]
    public var selectedResultID: Int?
    public private(set) var notice: String?

    public func saveToken(_ token: String) throws
    public func removeToken() throws
    public func search(profile: MediaProfile) async
    public func applySelectedResult(profile: MediaProfile) async -> TMDBAppliedMetadata?
}
```

Initialize `query`, `seasonNumber`, and `episodeNumber` from `TMDBFilenameParser`. Search must first confirm a token exists, clear stale results/notice, show a `.searching` state, and return to `.idle` with an actionable error message for missing token, empty query, authorization failure, no results, or transport/decode failure. Apply must require a selected result, fetch selection details, map only supplied data, download and store artwork opportunistically, and return `TMDBAppliedMetadata(patch:artworkURL:)`; it must return nil without changing the editor for detail failures. If artwork fails after details map successfully, return the patch with nil artwork and the exact notice in the test. Never retain the token in a published property.

- [ ] **Step 4: Run the lookup model tests and related core tests**

Run: `swift test --filter 'TMDBLookupModelTests|TMDBClientTests|TMDBMetadataMapperTests'`

Expected: PASS. Confirm automatic initialization makes zero client calls, no-episode TV selection remains series-level, and rejected credentials request replacement without exposing token text.

- [ ] **Step 5: Commit the lookup flow**

```bash
git add Sources/MKVHomeVideoCore/TMDB/TMDBLookupModel.swift \
  Tests/MKVHomeVideoCoreTests/TMDBLookupModelTests.swift
git commit -m "feat: add TMDB lookup workflow"
```

### Task 5: Compose the production dependencies and add the editor UI

**Files:**
- Create: `Sources/MKVHomeVideoApp/TMDBDependencies.swift`
- Modify: `Sources/MKVHomeVideoApp/MKVHomeVideoApp.swift`
- Modify: `Sources/MKVHomeVideoApp/Views/QueueView.swift`
- Modify: `Sources/MKVHomeVideoApp/Views/MetadataEditorView.swift`
- Create: `Sources/MKVHomeVideoApp/Views/TMDBAttributionView.swift`
- Create: `Resources/tmdb-logo.svg`
- Modify: `Scripts/build-app.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: `TMDBLookupModel`, `KeychainTMDBCredentialStore`, `TMDBArtworkStore`, and `TMDBAPIClient` from Tasks 2–4.
- Produces: working per-item editor UI with token configuration, explicit search, result selection, and safe patch application.

- [ ] **Step 1: Write a manual acceptance checklist in the README change before changing SwiftUI**

```markdown
### TMDB metadata lookup

Open an individual item's **Edit Metadata** sheet, configure an API Read Access Token, adjust the suggested filename query if necessary, and click **Search TMDB**. Choose and apply a result, then review or edit the metadata before saving. The token is stored only in your macOS Keychain; the downloaded artwork is stored locally for export.
```

Include the note that the legacy TMDB API key is not used. Add an **About TMDB** button to `QueueView`; its sheet must render `TMDBAttributionView`, which displays the unmodified `Resources/tmdb-logo.svg`, links to `https://www.themoviedb.org`, and includes this exact notice: `This product uses the TMDB API but is not endorsed or certified by TMDB.` Copy the SVG to `Contents/Resources` in `Scripts/build-app.sh` and load it from the app bundle. Obtain the primary full blue SVG directly from TMDB's official Logos & Attribution page; do not recreate or alter the logo.

- [ ] **Step 2: Add the production composition root and thread it through the queue sheet**

```swift
@MainActor
final class TMDBDependencies {
    let credentials: any TMDBCredentialStoring
    let artworkStore: any TMDBArtworkStoring
    let client: any TMDBSearching

    init() {
        let credentials = KeychainTMDBCredentialStore()
        self.credentials = credentials
        self.artworkStore = TMDBArtworkStore()
        self.client = TMDBAPIClient(credentials: credentials)
    }

    func lookupModel(for sourceURL: URL) -> TMDBLookupModel {
        TMDBLookupModel(sourceURL: sourceURL, client: client, credentials: credentials, artworkStore: artworkStore)
    }
}
```

Create exactly one `TMDBDependencies` instance in `MKVHomeVideoApp`, pass it to `QueueView`, and pass it into the individual `MetadataEditorView` sheet. Do not instantiate it in the shared/batch editor and do not add a token to `AppViewModel` or `QueueProjectStore`.

- [ ] **Step 3: Add the TMDB section to `MetadataEditorView`**

```swift
Section("TMDB") {
    SecureField("API Read Access Token", text: $tokenInput)
    Button(lookupModel.tokenConfigured ? "Replace Token" : "Save Token") { saveToken() }
    if lookupModel.tokenConfigured { Button("Remove Token", role: .destructive) { removeToken() } }
    TextField("Search query", text: $lookupModel.query)
    if profile == .tvEpisode {
        TextField("Season", text: $lookupModel.seasonNumber)
        TextField("Episode", text: $lookupModel.episodeNumber)
    }
    Button("Search TMDB") { Task { await lookupModel.search(profile: profile) } }
    // Show results in a Picker/List and Apply Metadata only after selection.
}
```

Create the model with `@State` in the editor initializer so its query reflects the current job source and its state persists through SwiftUI rendering. Disable only relevant controls during searching/applying. Render all state/notice text in the sheet; a save-token success must clear `tokenInput`. When Apply Metadata returns a patch, update the existing editor `@State` fields from that patch and assign artwork only when `artworkURL` is non-nil. Do not save or dismiss the editor automatically.

- [ ] **Step 4: Build and run the full automated suite**

Run: `swift test`

Expected: PASS, including all existing conversion, persistence, and metadata tests plus every TMDB test. Fix any Swift 6 sendability, Observation, or actor-isolation diagnostics before proceeding.

- [ ] **Step 5: Build the app bundle and perform the manual acceptance checklist**

Run: `Scripts/build-app.sh`

Expected: `dist/MKV Home Video.app` is produced.

Manually verify all of the following in the built app using a real token entered directly into the secure field (never terminal history or chat):

1. Opening the editor makes no network request and pre-fills an editable suggestion from a movie filename.
2. A movie search returns selectable results; applying one fills fields, keeps the sheet open, and allows edits before Save Metadata.
3. A `Show.S02E03.mkv` TV item exposes the detected numbers and applies a selected episode's title/date/order.
4. Removing/replacing the token changes configuration status and a missing/invalid token receives a clear, non-secret error.
5. With network disabled after applying a result, an export still uses the local downloaded artwork.
6. The **About TMDB** sheet includes the approved TMDB logo, the exact required notice, and a working TMDB website link.

- [ ] **Step 6: Commit UI, documentation, and verified feature**

```bash
git add Sources/MKVHomeVideoApp/TMDBDependencies.swift \
  Sources/MKVHomeVideoApp/MKVHomeVideoApp.swift \
  Sources/MKVHomeVideoApp/Views/QueueView.swift \
  Sources/MKVHomeVideoApp/Views/MetadataEditorView.swift \
  Sources/MKVHomeVideoApp/Views/TMDBAttributionView.swift \
  Resources/tmdb-logo.svg Scripts/build-app.sh \
  README.md
git commit -m "feat: add TMDB metadata lookup UI"
```

### Task 6: Final integration verification and review handoff

**Files:**
- Modify: only files required to correct a test, build, or manual-verification defect found in this task.

**Interfaces:**
- Consumes: all production and test interfaces from Tasks 1–5.
- Produces: a clean, tested branch ready for independent code review.

- [ ] **Step 1: Inspect the complete change set for secret-safety and scope**

Run: `git diff main~5..HEAD --check && rg -n -i 'github_pat_|ghp_|eyJ[a-zA-Z0-9_-]{20,}|api[_ -]?key\s*=' --glob '!\.git/**' .`

Expected: no whitespace errors and no real credential-like values. The only acceptable occurrences of `API key` describe that it is unsupported; the implementation must not create an `api_key` query parameter.

- [ ] **Step 2: Run the final test/build evidence commands**

Run: `swift test && Scripts/build-app.sh && git status --short --branch`

Expected: tests pass, app bundle builds, and the branch has only the intended committed changes.

- [ ] **Step 3: Request an independent code review**

Use the `superpowers:requesting-code-review` skill. Supply the spec, this plan, all task commit hashes, test/build output, and the review focus above. Resolve every confirmed finding using the `superpowers:receiving-code-review` skill before declaring completion.

- [ ] **Step 4: Commit any review fixes and re-run final verification**

```bash
git add -u
git add Sources/MKVHomeVideoCore/TMDB Sources/MKVHomeVideoApp README.md Tests/MKVHomeVideoCoreTests
git commit -m "fix: address TMDB lookup review findings"
swift test
Scripts/build-app.sh
```

Expected: no review-related regression and a clean post-review build.
