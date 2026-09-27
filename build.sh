#!/bin/bash
# Assemble AuraRim.app from the SwiftPM build output and sign it.
# Usage: ./build.sh [debug|release]   (default: release)
#
# IMPORTANT: the .app is assembled and signed in ~/Applications, NOT in this
# project folder. The project lives on the iCloud-synced Desktop, and iCloud
# re-stamps `com.apple.FinderInfo` xattrs on files right after they're written —
# which invalidates the code signature (Gatekeeper rejects it and TCC/permission
# grants like system-audio capture stop matching the app, so music sync silently
# breaks). ~/Applications is a local, non-synced folder, so the signature stays
# valid and permissions persist across rebuilds.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="${AURARIM_APP_DEST:-$HOME/Applications/AuraRim.app}"
CONTENTS="$APP/Contents"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG"
BIN=".build/$CONFIG/AuraRim"

echo "▸ Assembling $APP…"
mkdir -p "$(dirname "$APP")"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/AuraRim"
cp Resources/Info.plist "$CONTENTS/Info.plist"

echo "▸ Code signing…"
# Strip any extended attributes before signing (defensive; ~/Applications
# shouldn't get iCloud xattrs, but the copied binary can carry com.apple.provenance).
xattr -cr "$APP"
# Sign with a STABLE identity so macOS keeps granted permissions (System Audio,
# Screen Recording, Automation) across rebuilds. Ad-hoc ("-") changes identity
# every build and resets TCC — avoid it. Prefer an Apple Development / Developer
# ID identity if one exists; fall back to ad-hoc only if none is found.
SIGN_ID="${AURARIM_SIGN_ID:-}"
if [ -z "$SIGN_ID" ]; then
  SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -Eo '"(Apple Development|Developer ID Application)[^"]*"' | head -1 | tr -d '"')
fi
if [ -z "$SIGN_ID" ]; then
  echo "  ! No stable identity found — falling back to ad-hoc (permissions will reset each build)."
  SIGN_ID="-"
else
  echo "  Using identity: $SIGN_ID"
fi
codesign --force --deep \
  --entitlements Resources/AuraRim.entitlements \
  --sign "$SIGN_ID" "$APP"

echo "▸ Verifying signature…"
if codesign --verify --strict --verbose=1 "$APP" 2>&1; then
  echo "  ✓ signature valid"
else
  echo "  ! signature verification FAILED — permissions may not persist."
fi

echo "✓ Built $APP"
echo "  Run:  open \"$APP\""
