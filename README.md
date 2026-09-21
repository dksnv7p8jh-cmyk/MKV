# MKV Home Video

A private, offline macOS utility for turning local MKV files into Apple TV-ready MP4 Home Videos.

## Prerequisites

- Xcode command-line tools
- FFmpeg and ffprobe, installed once with:

  ```sh
  brew install ffmpeg
  ```

## Build and launch

Build a clickable app bundle with:

```sh
Scripts/build-app.sh
```

The result is at `dist/MKV Home Video.app`. On first launch, the app checks for FFmpeg and lets you choose a custom executable if it is not in a standard Homebrew location.

## Workflow

1. Add individual MKV files or a folder of MKVs.
2. Choose an output folder. Original files and existing MP4s are never overwritten; a collision receives a numbered filename.
3. Select rows to apply shared metadata, or edit metadata for individual Movie and TV Episode profiles. Exports are marked as Apple TV Home Videos and can include titles, descriptions, sort fields, episode ordering, credits, genre, dates, and JPEG/PNG cover art.
4. Start the sequential conversion queue. The app saves batches locally, reports progress, and retains failed jobs for retrying.
5. Reveal the completed MP4 and import it into Apple TV.

To clean up an already converted file, choose **Edit MP4 Metadata…**. The app rewrites the MP4 container metadata in place while stream-copying the existing media, so video and audio are not re-encoded. It first writes a temporary sibling file and replaces the original only after the edit succeeds. Cover-art changes remain available when converting MKVs; this in-place path preserves existing artwork.

Apple TV decides which imported metadata fields it shows, but the app writes the associated MP4/iTunes-style tags that FFmpeg supports.
