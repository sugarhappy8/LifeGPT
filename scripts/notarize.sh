#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool Keychain profile}"
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"
if [[ "$SIGN_IDENTITY" == '-' ]]; then echo 'Notarization requires a Developer ID Application certificate.' >&2; exit 1; fi
APP="$ROOT/dist/LifeGPT.app"
if [[ ! -d "$APP" ]]; then echo 'Build a signed app first with scripts/build-app.sh.' >&2; exit 1; fi
codesign --verify --deep --strict "$APP"
STAGING="$(mktemp -d "$ROOT/dist/.notary.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto -c -k --keepParent "$APP" "$STAGING/LifeGPT.zip"
xcrun notarytool submit "$STAGING/LifeGPT.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
"$ROOT/scripts/create-dmg.sh"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/LifeGPT")"
if [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]]; then LABEL=universal; elif [[ "$ARCHS" == *arm64* ]]; then LABEL=arm64; else LABEL=x86_64; fi
DMG="$ROOT/dist/LifeGPT-$VERSION-$LABEL.dmg"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type execute --verbose=2 "$APP"
echo "Notarized installer: $DMG"
