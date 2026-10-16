#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION=release
UNIVERSAL=0
SKIP_BUILD=0
for argument in "$@"; do
    case "$argument" in
        --debug) CONFIGURATION=debug ;;
        --universal) UNIVERSAL=1 ;;
        --skip-build) SKIP_BUILD=1 ;;
        --help) echo 'Usage: scripts/build-app.sh [--debug] [--universal] [--skip-build]'; exit 0 ;;
        *) echo "Unknown argument: $argument" >&2; exit 2 ;;
    esac
done

cd "$ROOT"
BUILD_ARGS=(--configuration "$CONFIGURATION" --product LifeGPT)
if [[ "$UNIVERSAL" == 1 ]]; then BUILD_ARGS+=(--arch arm64 --arch x86_64); fi
if [[ "$SKIP_BUILD" == 0 ]]; then xcrun swift build "${BUILD_ARGS[@]}"; fi
BIN_DIR="$(xcrun swift build "${BUILD_ARGS[@]}" --show-bin-path)"
if [[ ! -x "$BIN_DIR/LifeGPT" ]]; then echo "Missing executable at $BIN_DIR/LifeGPT" >&2; exit 1; fi

mkdir -p "$ROOT/dist"
STAGING="$(mktemp -d "$ROOT/dist/.app-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/LifeGPT.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Prompts"
cp "$BIN_DIR/LifeGPT" "$APP/Contents/MacOS/LifeGPT"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Sources/LifeCore/Resources/"*.md "$APP/Contents/Resources/Prompts/"
# Keep SwiftPM resource bundles, including GRDB's privacy manifest.
shopt -s nullglob
for resource in "$BIN_DIR/"*.bundle; do ditto "$resource" "$APP/Contents/Resources/$(basename "$resource")"; done
shopt -u nullglob
xcrun swift "$ROOT/scripts/generate-icon.swift" "$STAGING/AppIcon.iconset"
iconutil --convert icns "$STAGING/AppIcon.iconset" --output "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/packaging/ThirdPartyNotices.txt" "$APP/Contents/Resources/ThirdPartyNotices.txt"
plutil -lint "$APP/Contents/Info.plist"

IDENTITY="${SIGN_IDENTITY:--}"
SIGN_ARGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" == '-' ]]; then SIGN_ARGS+=(--timestamp=none); else SIGN_ARGS+=(--timestamp --options runtime); fi
shopt -s nullglob
for resource in "$APP/Contents/Resources/"*.bundle; do
    codesign --force --sign "$IDENTITY" "$resource"
done
shopt -u nullglob
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
# Only generated output is replaced. Saves live in Application Support and are never touched.
if [[ -e "$ROOT/dist/LifeGPT.app" ]]; then rm -rf "$ROOT/dist/LifeGPT.app"; fi
mv "$APP" "$ROOT/dist/LifeGPT.app"
echo "App ready: $ROOT/dist/LifeGPT.app"
