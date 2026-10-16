# Building LifeGPT for macOS

## Prerequisites

Use a Mac with Xcode and a Swift 6 toolchain. The app targets macOS 14+. This implementation was developed with Swift 6.4/Xcode 27; the release and Intel/universal builds should be verified on the toolchain you distribute with.

Open Xcode once and complete its first-run setup. If command-line tools are not selected:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcrun swift --version
```

The first build downloads the pinned GRDB dependency from GitHub. No Homebrew packages, CocoaPods, JavaScript tools, or `create-dmg` installation are needed. The scripts use Apple's `hdiutil`, `codesign`, `iconutil`, and Xcode tools.

## Test and build

From this repository:

```sh
swift test
./scripts/build-app.sh
open dist/LifeGPT.app
```

The build script compiles the `LifeGPT` product in release mode, creates a proper app bundle, copies prompt and privacy resources, generates the icon, and ad-hoc signs the result. It writes only generated outputs under `dist/`; it never touches your saves.

For a debug app bundle:

```sh
./scripts/build-app.sh --debug
```

The default build uses the current Mac's architecture. For a universal Apple Silicon + Intel binary, if supported by your installed Xcode SDK:

```sh
./scripts/build-app.sh --universal
lipo -archs dist/LifeGPT.app/Contents/MacOS/LifeGPT
```

Expected universal output contains `arm64` and `x86_64`. If your installed toolchain no longer includes one architecture, use a compatible Xcode installation or build that architecture on a suitable Mac.

## Create the DMG installer

```sh
./scripts/create-dmg.sh
```

The output is named for its architecture, for example:

- `dist/LifeGPT-0.3.0-arm64.dmg`
- `dist/LifeGPT-0.3.0-universal.dmg`

It contains **LifeGPT.app**, an **Applications** shortcut, and a short installation note. The user drags the app into Applications. This is a standard disk-image installer, not a privileged `.pkg` installer, and it does not modify system folders beyond that user-initiated copy.

## Signed distribution and notarization

For distribution to other people, sign with a **Developer ID Application** certificate and notarize. Apple requires the hardened runtime for notarized software; the signed build path enables it. See Apple's [notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [custom workflow documentation](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Find your installed certificate:

```sh
security find-identity -v -p codesigning
```

Set its exact name, then rebuild:

```sh
export SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
./scripts/build-app.sh --universal
```

Omit `--universal` if you only need your current architecture. Before signing your own release, change the bundle identifier in `packaging/Info.plist` if appropriate. Keep it consistent for later updates.

Store notarization credentials using Apple's interactive Keychain workflow:

```sh
xcrun notarytool store-credentials 'LifeGPT-notary'
export NOTARY_PROFILE='LifeGPT-notary'
./scripts/notarize.sh
```

The script submits a ZIP of the signed app, staples the accepted ticket to the app, rebuilds the DMG from that stapled app, submits the DMG, and staples the disk image. Credentials are read through your Keychain profile, not stored in this repository.

If Apple rejects a submission, inspect the submission log with the ID returned by `notarytool`:

```sh
xcrun notarytool log SUBMISSION_ID --keychain-profile 'LifeGPT-notary' notarization-log.json
```

Do not ship a failed or unverified result. These scripts do not purchase certificates or create a developer account.

## Personal builds without a Developer ID

The default ad-hoc build can be used for local testing. A copy downloaded on another Mac may be blocked by Gatekeeper. If you trust the build, use the explicit **Open Anyway** flow in System Settings → Privacy & Security. Do not disable Gatekeeper globally. Apple documents its supported [app-opening security controls](https://support.apple.com/102445).

## Verify the bundle before sharing

```sh
codesign --verify --deep --strict --verbose=2 dist/LifeGPT.app
plutil -lint dist/LifeGPT.app/Contents/Info.plist
```

Mount the DMG, drag the app into Applications, eject the image, and launch the copied app. Test both a newly created life and reopening a saved life. Launching only from the build folder can hide missing resource-bundle problems; the app must also work after relocation.

Complete [manual testing](docs/manual-testing.md), especially cloud/local connection tests, on the final signed app. Unit tests do not verify API credentials, actual model availability, or Apple notarization.

## Updating and uninstalling

Replace the app in Applications to update. Saves are migrated when opened; export a backup before updating a valuable life. Deleting the app does not delete saves or Keychain entries.

To remove game data, first export anything you want to keep, then remove `~/Library/Application Support/LifeGPT` yourself. To remove credentials, clear the API key in the app's Settings and save, or remove the matching service entry in Keychain Access.
