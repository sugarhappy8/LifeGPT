#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) LifeGPT.app and wraps it in build/LifeGPT.dmg.
# Run on macOS with Xcode 15.3+ installed:  ./Packaging/build_dmg.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
BUILD="${GITHUB_RUN_NUMBER:-1}"
OUT=build
APP="$OUT/LifeGPT.app"

swift build -c release --product LifeGPT --arch arm64 --arch x86_64
BIN="$(swift build -c release --product LifeGPT --arch arm64 --arch x86_64 --show-bin-path)/LifeGPT"

rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LifeGPT"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Packaging/Info.plist > "$APP/Contents/Info.plist"

# Ad-hoc signature so the app runs on Apple Silicon. Not notarized: see README for first-launch steps.
codesign --force --deep --sign - "$APP"

STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "LifeGPT" -srcfolder "$STAGE" -ov -format UDZO "$OUT/LifeGPT.dmg"
rm -rf "$STAGE"

echo "Built $OUT/LifeGPT.dmg"
