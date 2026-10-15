# LifeGPT

An AI life sim for macOS based on the player and their life. You choose who you are, when and where you're born,
and what you do; an AI narrator plays out the consequences, introduces events, and moves time forward.
Your life (money, relationships, major moments, the date) is saved on your Mac and re-read by the AI every turn.

Bring your own API key: LifeGPT talks to the model provider directly, and the key stays in your Keychain.

## Play

1. Download `LifeGPT.dmg` from the latest run of the **macOS build** workflow (Actions tab > run > Artifacts).
2. Open the DMG and drag LifeGPT to Applications.
3. The app is not notarized yet, so the first time, right-click LifeGPT in Applications and choose **Open**
   (or run `xattr -dr com.apple.quarantine /Applications/LifeGPT.app`).
4. Open **LifeGPT > Settings** (⌘,), paste your Anthropic API key, and save.
5. Start a new life (⌘N).

Requires macOS 14 Sonoma or later. Every turn is a paid API call on your account.

## Build from source

```sh
swift test                      # engine tests
swift run LifeGPT               # run the app unbundled
./Packaging/build_dmg.sh        # build/LifeGPT.dmg (needs Xcode 15.3+)
```

See [docs/DESIGN.md](docs/DESIGN.md) for how state, prompts and history compaction work.
