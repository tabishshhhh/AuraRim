#!/bin/bash
# Assemble AuraRim.app from the SwiftPM build output and ad-hoc sign it.
# Usage: ./build.sh [debug|release]   (default: release)
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="AuraRim.app"
CONTENTS="$APP/Contents"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG"
BIN=".build/$CONFIG/AuraRim"

echo "▸ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/AuraRim"
cp Resources/Info.plist "$CONTENTS/Info.plist"

echo "▸ Code signing…"
# Sign with a STABLE identity so macOS keeps your granted permissions (Screen
# Recording, Automation) across rebuilds. Ad-hoc ("-") changes identity every
# build and resets TCC — avoid it. Prefer an Apple Development / Developer ID
# identity if one exists; fall back to ad-hoc only if none is found.
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

echo "✓ Built $APP"
echo "  Run:  open $APP        (or)   $CONTENTS/MacOS/AuraRim"
