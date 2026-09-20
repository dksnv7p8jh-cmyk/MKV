# MKV Home Video Converter — Design Specification

## Purpose

Create a private, offline macOS utility for preparing local MKV files for
Apple TV. The app lets one person queue MKVs in batches, review or edit
metadata, convert them to MP4 with a locally installed FFmpeg executable, and
import the resulting files into Apple TV as well-described Home Videos.

No account, cloud service, online metadata lookup, telemetry, or distribution
workflow is in scope.

## Users and Success Criteria

The sole user can:

1. Drop one or more MKV files (or a folder containing them) into a queue.
2. Set metadata across selected files and override it for an individual file.
3. Mark each file as a Movie or TV Episode while exporting all files as Apple
   TV Home Videos.
4. Convert the queue without risking the source files, observe both per-file
   and batch progress, recover from failures, and resume after restarting.
5. Import output MP4s into Apple TV with useful titles, descriptions,
   categorization, episode ordering, and optional cover art.

## Platform and Dependencies

- **Platform:** macOS 26 or later.
- **UI:** SwiftUI, including native file importing, drag-and-drop, and
  Quick Look-style preview where AVFoundation supports the source codec.
- **Conversion:** an externally installed `ffmpeg` binary. At launch the app
  checks common Homebrew locations and `PATH`, then provides a setup screen
  with `brew install ffmpeg` and a custom-path picker when none is found.
- **Playback:** AVFoundation / `AVPlayer`. A source that macOS cannot decode
  is clearly identified; it can still be converted through FFmpeg. Converted
  MP4s are previewable in the app.
- **Storage:** a local application-support JSON project file that persists the
  queue, metadata drafts, destination choices, and completed/failed state.

## Interface and Workflow

### Queue

The main window has a drag-and-drop target, Add Files and Add Folder buttons,
destination selector, total-progress header, and a queue table. Each row
shows a thumbnail/name, media profile, output filename, conversion state,
per-file progress, and actions for preview, metadata editing, removal,
retrying, and revealing completed output.

Folder import recursively finds `.mkv` files, ignores unsupported files, and
does not modify the source folder. Source file paths are security-scoped while
in use. Outputs are always written to a selected destination, never over a
source; filename collisions receive a numbered suffix before conversion.

The queue runs sequentially in its first release. This provides predictable
resource use, straightforward total progress, and allows later jobs to retain
their shared metadata edits until they start. The user can start, pause after
the current item, retry failures, skip a job, and resume a saved project.

### Metadata Editing

The user can select any number of rows and open a shared-metadata inspector.
Values set there become batch defaults for the selected rows. Each row’s
metadata sheet can override any inherited value; visually, inherited values
remain distinguishable from overrides.

All output files have Apple TV **Home Video** media kind. The profile changes
the additional fields and metadata atoms:

| Field group | Movie | TV Episode |
| --- | --- | --- |
| Identity | title, sort title | show name, show sort name, episode title |
| Ordering | collection name | season number, episode number, episode sort |
| Description | synopsis/description | synopsis/description |
| Release information | release date/year | original air date, network |
| Credits | director, cast, studio | studio/network |
| Shared | genre, rating, copyright, cover artwork | genre, rating, copyright, cover artwork |

An optional JPEG or PNG cover image is copied into the MP4 as attached artwork.
Metadata fields are intentionally local and manually editable; the app never
scrapes or uploads media information.

### Conversion

For each job the app builds an explicit FFmpeg command. It maps the first video
stream and appropriate audio/subtitle streams, produces a `.mp4` result, and
writes Apple-compatible MP4/iTunes-style tags including title, sort title,
description, genre, date, artwork, Home Video media kind, and applicable TV
show/season/episode values. The exact tags Apple TV displays are controlled by
Apple TV, but the app supplies the fields it can consume on import.

The command runner sends FFmpeg progress to a structured pipe. The UI converts
that output into job percentage, elapsed time, and aggregate queue progress.
Before executing a job it validates the source file, destination, output name,
FFmpeg location, and applicable metadata types.

Initial conversion behavior prefers broad Apple compatibility: H.264 video,
AAC audio, and `+faststart` MP4 layout. A later preference may expose quality
presets, but the initial app keeps one understandable compatibility preset.

### Preview

The app opens a selected video in an `AVPlayer`-based preview sheet. If an MKV
contains a codec unsupported by AVFoundation, the sheet explains that native
preview is unavailable and offers conversion; it does not claim universal MKV
playback. Completed MP4s use the same player.

## Architecture

The implementation separates policy and UI:

- `AppModel` owns persisted queue state, selection, commands, and alerts.
- `ConversionJob` and `VideoMetadata` are Codable value models. Metadata
  resolution combines shared values with a row’s explicit overrides.
- `FFmpegLocator` resolves and validates an FFmpeg executable.
- `FFmpegCommandBuilder` is a pure component that maps a job and compatibility
  preset to an argument list. It owns metadata/cover-art tag translation.
- `FFmpegProcessRunner` starts `Process`, parses structured progress, supports
  cancellation after the current safe boundary, and returns typed outcomes.
- `QueueStore` atomically saves and restores the project JSON.
- SwiftUI views render these models without embedding FFmpeg arguments or
  persistence logic.

## Errors and Recovery

Missing FFmpeg leads to a non-destructive setup state. Invalid paths,
unwritable destinations, lost security scope, output collisions, malformed
metadata, FFmpeg nonzero exits, and cancelled jobs each get a distinct message
with recovery options. A failed job retains its source and metadata so Retry
can create a fresh output attempt. Existing source MKVs are never renamed,
deleted, or overwritten.

## Testing and Verification

Unit tests precede production implementation and cover:

1. Media-profile metadata maps to the expected FFmpeg arguments and Home Video
   tag.
2. Per-row overrides win over selected-row shared metadata.
3. Output filename generation protects sources and handles collisions.
4. The FFmpeg command builder creates a compatible MP4 command with the right
   stream, artwork, and progress options.
5. Progress parser accepts FFmpeg updates and reports job completion/failure.
6. Queue state transitions correctly handle success, skip, retry, pause, and
   resume persistence.

The final build is verified through the full test suite and a macOS app build.
Manual smoke testing uses a local MKV only after FFmpeg is installed.

## Explicitly Out of Scope

- Online movie/TV metadata lookup or artwork downloading.
- DRM-protected media.
- Bundling FFmpeg inside the application.
- Parallel conversions, disc ripping, editing/transcoding timelines, or
  universal playback of every possible MKV codec.
- Automatic Apple TV library import; the app prepares and reveals files for
  the user to import.
