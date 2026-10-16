#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/LifeGPT.app"
if [[ ! -d "$APP" ]]; then echo 'Build the app first: ./scripts/build-app.sh' >&2; exit 1; fi
codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/LifeGPT")"
if [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]]; then LABEL=universal; elif [[ "$ARCHS" == *arm64* ]]; then LABEL=arm64; else LABEL=x86_64; fi
DMG="$ROOT/dist/LifeGPT-$VERSION-$LABEL.dmg"
STAGING="$(mktemp -d "$ROOT/dist/.dmg-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/LifeGPT.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Install LifeGPT.txt" <<'INSTALL'
Drag LifeGPT into Applications, then launch it from Applications.

Your lives are saved in ~/Library/Application Support/LifeGPT/Lives.
Updating or replacing the app does not remove your lives.

Open Settings to choose Anthropic, Google Gemini, or a local model server.
The built-in offline demo works without a key or server.
INSTALL
hdiutil create -volname LifeGPT -srcfolder "$STAGING" -ov -format UDZO "$DMG"
if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != '-' ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
hdiutil verify "$DMG"
echo "DMG ready: $DMG"
