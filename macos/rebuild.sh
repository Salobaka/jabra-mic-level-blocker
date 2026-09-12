#!/bin/bash
set -euo pipefail

APP_NAME="JabraInputTracker"
cd "$(dirname "$0")"

./build.sh

echo
echo "========================================"
echo "  NEW BUILD - RE-GRANT ALL PERMISSIONS"
echo "========================================"
echo
echo "Each rebuild changes the code signature (cdhash)."
echo "Previous TCC entries are stale and must be replaced."
echo
echo "Steps:"
echo "  1. Remove old entries from TCC lists:"
echo "       System Settings → Privacy & Security → Microphone      → select old JabraInputTracker → -"
echo "       System Settings → Privacy & Security → Bluetooth        → select old JabraInputTracker → -"
echo "       System Settings → Privacy & Security → Input Monitoring → select old JabraInputTracker → -"
echo
echo "  2. Launch the app:"
echo "       open .build/$APP_NAME.app"
echo
echo "  3. Click the menu-bar mic icon → for each permission:"
echo "       Click 'Open Settings' → click '+' → add .build/$APP_NAME.app → toggle on"
echo "       Click back to the app (or click ↻) → badge flips green"
echo