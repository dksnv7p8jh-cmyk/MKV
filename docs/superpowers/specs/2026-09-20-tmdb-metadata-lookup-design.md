# TMDB Metadata Lookup Design

## Purpose

Let a user enrich an individual MKV conversion job with movie or TV-episode
metadata from TMDB without putting credentials in source code, Git, or the
output project file. The user retains full control over the search and every
field before the conversion is saved or exported.

## User experience

1. Opening an individual metadata editor derives a proposed search query from
   the input filename. It also detects common season/episode forms such as
   `S02E03`. No network request is made automatically.
2. The TMDB section reports whether a read token is configured. The user can
   add, replace, or remove it using a secure field. The value is never shown
   again after saving.
3. The user can edit the proposed query and clicks **Search TMDB**. Movie
   profile searches movies; TV Episode profile searches TV series.
4. Results display title, year, overview, and poster thumbnail. The user
   selects one result and clicks **Apply Metadata**.
5. The app fetches the selected detail record. For TV episodes with an
   available season and episode number, it fetches that exact episode. It then
   replaces the editor's relevant editable values and downloads a selected
   poster to local app-managed storage. The user may edit, clear, replace, or
   discard every value before clicking **Save Metadata**.

## Credential storage

`TMDBCredentialStore` is a small protocol backed in production by the macOS
Keychain (`kSecClassGenericPassword`). It stores one item identified by the
app's bundle/service name and a fixed account name. The store supports read,
save/replace, and delete. It never writes the token to `UserDefaults`, a file,
logs, a test fixture, the README, or a queue project.

The client uses only the TMDB API Read Access Token as an HTTP
`Authorization: Bearer <token>` header. The separately-issued TMDB API key is
not needed by this app and will not be stored. This supports TMDB v3 search
and detail endpoints with the v4-style read token.

## Core components

### Filename parser

`TMDBFilenameParser` accepts an input URL and returns a suggested query plus
optional season and episode numbers. It removes the extension and common
release tags, normalizes `.`, `_`, and `-` separators into spaces, and detects
`SxxEyy` case-insensitively. Its output is only a suggestion: the user can
change the query and episode values in the editor.

### Client and API models

`TMDBClient` is a protocol so UI code depends on a testable boundary. Its
production implementation uses `URLSession`, encodes query parameters through
`URLComponents`, requires a token from the credential store, and decodes only
the TMDB fields used by this app.

It supports:

- movie search and movie details with credits and images;
- TV-series search and TV details;
- TV episode details for a selected series, season, and episode; and
- poster download.

All requests use `https://api.themoviedb.org/3`, `language=en-US`, and an
`Accept: application/json` header. Poster paths are converted into HTTPS image
URLs using TMDB's documented image host. No request body is sent and no
request is made until the user clicks Search or Apply Metadata.

### Result types and mapper

App-owned result types (`TMDBSearchResult`, `TMDBMovieDetails`, and
`TMDBEpisodeDetails`) isolate the rest of the application from TMDB JSON.
`TMDBMetadataMapper` converts a selected detail result into values understood
by `VideoMetadataPatch`:

- movie: title, sort title, overview, genre, release date, collection,
  director, cast, studio, and poster;
- TV episode: show and sort names, episode title, overview, air date, season
  and episode numbers, episode sort, genre, network, and poster/still image.

Missing TMDB values produce no replacement value; applying a result never
marks a field as explicitly cleared.

### Artwork cache

`TMDBArtworkStore` downloads image data only after Apply Metadata, validates a
successful image response, and writes it beneath the app's Application Support
directory. Its stable, media-ID-based filename prevents a network dependency
during FFmpeg export. A download failure leaves the current artwork unchanged
and reports an error.

## SwiftUI integration

`MetadataEditorView` receives a `TMDBClient` and a credential-store-backed
view model. Its TMDB section contains credential actions, editable search
query, search progress and errors, result selection, and an Apply Metadata
button. All network tasks run asynchronously; controls are disabled only for
the active operation. Cancelling the editor abandons unsaved TMDB-applied
changes just like manually edited changes.

The initial application composition creates the real Keychain store, artwork
store, and URLSession client once, while unit tests inject fakes.

## Errors and privacy

Errors use concrete user-facing text:

- no saved token: prompt to configure one;
- 401/403: saved token was rejected and should be replaced;
- no results: advise changing the query;
- unavailable network or non-success HTTP response: describe the retryable
  failure without showing a URL containing secrets;
- decoding or missing episode: retain existing editor fields and explain that
  no matching metadata was applied;
- artwork download failure: retain existing artwork and allow metadata fields
  to be applied.

Tokens must not be logged, embedded in errors, added to `URL` query strings,
or included in recorded fixtures. Search terms and titles are not persisted as
TMDB history.

## Testing

Unit tests use a fake credential store and a custom `URLProtocol` to cover:

- filename query and SxxEyy parsing;
- Keychain-store behavior through the protocol contract;
- request method, URL query encoding, bearer header presence, and no API key;
- decoding/mapping for representative movie, TV-series, and TV-episode JSON;
- 401/403, empty results, malformed JSON, network, and artwork-download
  failures;
- applying partial TMDB results without clearing unrelated fields; and
- local artwork cache paths and successful writes.

No test makes a live TMDB request or contains a real token.

## Non-goals

- Batch metadata lookup and automatic search on editor opening.
- Persisting a user's TMDB search history or selection.
- Ratings/certifications, trailers, cast browsing, or alternate-language UI.
- Replacing manual artwork selection or changing FFmpeg export behavior.
- Storing or using the legacy TMDB API key.

## Verification

Run the focused TMDB unit-test target, then `swift test` for the full package,
and `Scripts/build-app.sh`. Manually verify the built app can save a test
token to Keychain, search only after the button is pressed, apply a movie and a
TV episode result, edit applied values, and export with the downloaded local
artwork after disabling the network.
