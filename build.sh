#!/bin/bash
set -euo pipefail

APP_NAME="JabraInputTracker"
BUILD_DIR=".build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
INFO_PLIST="Info.plist"

cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "ERROR: 'swiftc' not found. Install Xcode Command Line Tools: xcode-select --install" >&2
    exit 1
fi

if pgrep -x "$APP_NAME" >/dev/null; then
    echo "Stopping running $APP_NAME instance..."
    pkill -x "$APP_NAME" || true
    sleep 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$RESOURCES_DIR"

echo "Compiling $APP_NAME..."
swiftc -O -whole-module-optimization \
    -framework Cocoa \
    -framework AVFoundation \
    -framework CoreAudio \
    -framework IOBluetooth \
    Sources/*.swift \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"

echo "Ad-hoc code signing..."
codesign --force --deep --options runtime --sign - "$APP_BUNDLE" >/dev/null 2>&1 || \
    codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "Built: $APP_BUNDLE"
echo "Run with: open '$APP_BUNDLE'"
echo
echo "NOTE: First launch on this Mac prompts for Microphone, Bluetooth, and Input Monitoring."
echo "      Each rebuild re-signs ad-hoc, so Input Monitoring must be re-granted after every build."