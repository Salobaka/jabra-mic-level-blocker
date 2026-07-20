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
    -framework CoreBluetooth \
    Sources/*.swift \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"

echo "Generating app icon..."
if command -v swift >/dev/null 2>&1; then
    swift tools/generate_icon.swift "$BUILD_DIR/AppIcon.iconset" "$RESOURCES_DIR/AppIcon.icns"
else
    echo "WARNING: swift not found, skipping icon generation" >&2
fi

echo "Ad-hoc code signing..."
codesign --force --deep --options runtime --sign - "$APP_BUNDLE" >/dev/null 2>&1 || \
    codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

xattr -cr "$APP_BUNDLE" 2>/dev/null || true

echo "Built: $APP_BUNDLE"
echo "Run with: open '$APP_BUNDLE'"
echo
echo "NOTE: On Sequoia 15.7, TCC modals cannot be triggered automatically"
echo "      (com.apple.provenance is system-enforced and cannot be removed)."
echo "      Jabra gain control works immediately with NO permission."
echo "      For Bluetooth and Input Monitoring, add the app manually:"
echo "        System Settings → Privacy & Security → [Bluetooth / Input Monitoring] → +"