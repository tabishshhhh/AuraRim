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

echo "▸ Ad-hoc code signing…"
# Ad-hoc signature (dev). For distribution replace "-" with your Developer ID
# and add --options runtime for the hardened runtime (see README).
codesign --force --deep \
  --entitlements Resources/AuraRim.entitlements \
  --sign - "$APP"

echo "✓ Built $APP"
echo "  Run:  open $APP        (or)   $CONTENTS/MacOS/AuraRim"
