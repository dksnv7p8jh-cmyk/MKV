#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_PATH="$PROJECT_DIR/dist/MKV Home Video.app"

cd "$PROJECT_DIR"
swift build -c release

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BUILD_DIR/MKVHomeVideoApp" "$APP_PATH/Contents/MacOS/MKVHomeVideoApp"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"

print -r -- "$APP_PATH"
