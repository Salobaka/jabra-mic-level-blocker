#!/bin/bash
# notarize.sh — Developer ID sign + notarize + staple + zip for GitHub distribution.
#
# Usage:
#   source notarize.env        # exports APPLE_ID, APP_SPECIFIC_PASSWORD, TEAM_ID, SIGN_IDENTITY
#   ./build.sh                  # produce .build/JabraInputTracker.app (ad-hoc signed is fine; we re-sign below)
#   ./notarize.sh [version]     # default version pulled from Info.plist CFBundleShortVersionString
#
# Output:
#   release/JabraInputTracker-<version>-macos.zip   (signed + notarized + stapled, ready to upload)
#   Prints the suggested `gh release create` command at the end (does NOT auto-publish).
#
# Prerequisites (one-time, see README):
#   - "Developer ID Application" certificate installed in Keychain
#   - App-specific password generated at appleid.apple.com (labeled "notarytool")
#   - notarize.env filled in and sourced before running this script

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="JabraInputTracker"
BUNDLE_ID="jabra-mic-level-handler"
APP_BUNDLE=".build/$APP_NAME.app"
ENTITLEMENTS="release.entitlements"
RELEASE_DIR="release"

# --- validate env -----------------------------------------------------------------

required_vars=(APPLE_ID APP_SPECIFIC_PASSWORD TEAM_ID SIGN_IDENTITY)
for v in "${required_vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "ERROR: \$$v is not set. Run: source notarize.env" >&2
    exit 1
  fi
done

# --- validate prerequisites --------------------------------------------------------

if [ ! -d "$APP_BUNDLE" ]; then
  echo "ERROR: $APP_BUNDLE not found. Run ./build.sh first." >&2
  exit 1
fi

if [ ! -f "$ENTITLEMENTS" ]; then
  echo "ERROR: $ENTITLEMENTS not found next to this script." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "ERROR: xcrun not found. Install Xcode: xcode-select --install" >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
  echo "ERROR: Sign identity not found in Keychain: $SIGN_IDENTITY" >&2
  echo "Available identities:" >&2
  security find-identity -v -p codesigning >&2 || true
  exit 1
fi

# --- resolve version ---------------------------------------------------------------

if [ $# -ge 1 ]; then
  VERSION="$1"
else
  VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || echo "1.0")
fi
echo "Releasing $APP_NAME version $VERSION"

# --- fresh release dir ------------------------------------------------------------

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Use a copy so the original .build/ stays untouched for further dev.
cp -R "$APP_BUNDLE" "$RELEASE_DIR/$APP_NAME.app"
APP="$RELEASE_DIR/$APP_NAME.app"

# --- strip quarantine + any prior ad-hoc signature ---------------------------------

xattr -cr "$APP" 2>/dev/null || true

# --- re-sign with Developer ID Application + hardened runtime + entitlements ------

echo "Code-signing with: $SIGN_IDENTITY"
codesign --force --deep --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  "$APP"

# Verify the signing identity took (not still ad-hoc).
SIGN_AUTHORITY=$(codesign -dv --verbose=4 "$APP" 2>&1 | grep -i "Authority=" | head -1 || true)
if ! echo "$SIGN_AUTHORITY" | grep -q "Developer ID Application"; then
  echo "ERROR: bundle is not signed with a Developer ID Application certificate." >&2
  echo "Authority line: $SIGN_AUTHORITY" >&2
  exit 1
fi
echo "  signature: $SIGN_AUTHORITY"

# --- zip for notarization (ditto preserves macOS metadata) ------------------------

ZIP_PRE="$RELEASE_DIR/$APP_NAME-notarize-input.zip"
echo "Zipping for notarization..."
ditto -c -k --keepParent "$APP" "$ZIP_PRE"

# --- submit to Apple notarization service -----------------------------------------

echo "Submitting to notarytool (this can take 5-30 minutes)..."
xcrun notarytool submit "$ZIP_PRE" \
  --apple-id "$APPLE_ID" \
  --password "$APP_SPECIFIC_PASSWORD" \
  --team-id "$TEAM_ID" \
  --wait

# --- staple the notarization ticket to the .app (not the zip) ----------------------

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# --- final Gatekeeper verification -------------------------------------------------

echo "Verifying Gatekeeper acceptance..."
SPCTL_OUT=$(spctl -a -vvv -t install "$APP" 2>&1 || true)
echo "$SPCTL_OUT"
if ! echo "$SPCTL_OUT" | grep -q "source=Notarized Developer ID"; then
  echo "ERROR: Gatekeeper did not accept the bundle as Notarized Developer ID." >&2
  exit 1
fi

# --- final zip (post-staple) for distribution --------------------------------------

ZIP_FINAL="$RELEASE_DIR/$APP_NAME-$VERSION-macos.zip"
echo "Packaging final zip: $ZIP_FINAL"
ditto -c -k --keepParent "$APP" "$ZIP_FINAL"

rm -f "$ZIP_PRE"

# --- suggested publish command (NOT auto-run) --------------------------------------

echo
echo "========================================"
echo "  RELEASE READY: $ZIP_FINAL"
echo "========================================"
echo
echo "To publish on GitHub:"
echo "  gh release create v$VERSION \"$ZIP_FINAL\" \\"
echo "    --title \"v$VERSION\" \\"
echo "    --generate-notes"
echo
echo "(Script does not auto-publish. Review the zip, then run the command above.)"