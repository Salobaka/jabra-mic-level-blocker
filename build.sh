#!/bin/bash
set -e

APP_NAME="JabraInputTracker"
BUILD_DIR=".build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

mkdir -p "$APP_BUNDLE/Contents/MacOS"

echo "Compiling $APP_NAME..."
swiftc -O -whole-module-optimization \
    -framework Cocoa \
    -framework AVFoundation \
    -framework CoreAudio \
    -framework IOBluetooth \
    Sources/*.swift \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "Built: $APP_BUNDLE"
echo "Run with: open '$APP_BUNDLE'"
