#!/bin/bash
set -euo pipefail

APP_NAME="JabraInputTracker"
SRC_BUNDLE="$(cd "$(dirname "$0")" && pwd)/.build/$APP_NAME.app"
DEST_DIR="${1:-/Applications}"
DEST_BUNDLE="$DEST_DIR/$APP_NAME.app"

if [ ! -d "$SRC_BUNDLE" ]; then
    echo "ERROR: $SRC_BUNDLE not found. Run ./build.sh first." >&2
    exit 1
fi

echo "Installing $APP_NAME to $DEST_DIR ..."
mkdir -p "$DEST_DIR"

if [ -d "$DEST_BUNDLE" ]; then
    echo "Replacing existing $DEST_BUNDLE ..."
    rm -rf "$DEST_BUNDLE"
fi

cp -R "$SRC_BUNDLE" "$DEST_BUNDLE"

echo "Stripping Gatekeeper quarantine attribute ..."
xattr -cr "$DEST_BUNDLE" 2>/dev/null || true

echo "Re-signing ad-hoc in place ..."
codesign --force --deep --options runtime --sign - "$DEST_BUNDLE" >/dev/null 2>&1 || \
    codesign --force --deep --sign - "$DEST_BUNDLE" >/dev/null 2>&1 || true

echo "Registering Gatekeeper exception ..."
spctl --add "$DEST_BUNDLE" 2>/dev/null || true

defaults delete com.salobaka.jabrainputtracker showDockIcon 2>/dev/null || true

echo "Installed. Launch with: open '$DEST_BUNDLE'"
echo
echo "First launch prompts for Microphone, Bluetooth, and Input Monitoring."
echo "Sequoia 15: if the app is missing from the Input Monitoring list, run:"
echo "  sudo xattr -cr '$DEST_BUNDLE'"