# LifeGPT

A native macOS life RPG told through conversation. Create a person, choose a place and era, and live their story. The narrator writes the fiction; the game owns the calendar, money, and saved facts.

Built with Swift 6, SwiftUI, and GRDB/SQLite. Requires macOS 14 or later.

## Run during development

```sh
swift test
swift run LifeGPT
```

Open `Package.swift` in Xcode if you prefer its editor and debugger. Select the **LifeGPT** executable scheme. The command-line `lifelab` remains available for engine and voice experiments.

The app starts in **Offline demo** mode, which uses a small, clearly labeled set of built-in scenes. It requires no key, server, or network. For open-ended narration, open Settings and choose Anthropic, Gemini, or a local LM Studio/Ollama server.

## Build the macOS app and DMG

```sh
./scripts/build-app.sh
./scripts/create-dmg.sh
```

The app and installer appear in `dist/`. Open the DMG and drag **LifeGPT** into **Applications**. See [BUILDING.md](BUILDING.md) for prerequisites, Intel/Apple Silicon builds, signing, and notarization.

## What is implemented

- Native chat window with life history, date/age/balance display, suggested actions, custom reply lengths, stop/cancel, and explicit time skipping.
- Character creation followed by editable world/economy review, with reviewed regeneration after moves or era changes. AI setup or manual setup; personal starting savings remain age-based, regardless of family wealth.
- One SQLite save per life, atomic turn commits, schema v3 legacy-save migration, import, export, and a readable Markdown story export.
- Anthropic and Gemini REST clients; a local OpenAI-compatible adapter for LM Studio and Ollama. Two-step narration can draft prose, then extract and validate changes.
- macOS Keychain credentials, transient HTTP retries, connection testing, response usage history, and a configurable estimated daily spending limit.
- Engine-owned income, living costs, asset ownership/resale, deposits and interest, loans, repayments, arrears, and abstract fate-gated criminal outcomes.
- Separate personal, business, and savings accounts, paired transfers, and **Manage finances** controls for accounts and recurring income.
- Wage, self-employment, scalable business profit, allowance, and rental income, with named destinations and dated rate history.
- Staged business paths with elapsed-time and capital requirements. Their default payout begins at the profit stage; a linked recorded business income stream replaces that payout.
- Persistent cast, decisions, life state/history, timeline, unresolved threads, narrator notes, and suggested choices.
- Relevance-scored context packing and local chapter-excerpt compaction. Full transcripts are retained.
- Per-life Simulation/Sandbox play style, difficulty, household support, Voice Bible, Swing Dial, automatic/custom reply length, and tone preferences. Death closes the life while leaving its history readable.
- Read-only out-of-character questions such as `((balance))`, `((age))`, `((income))`, `((who))`, and `((decisions))`. `((longer))` and `((shorter))` change the app's reply-length preference for the current life.

Choose **Simulation** to resolve attempts through the game's rules, or **Sandbox** to declare fictional outcomes while retaining validated financial records. Play style is separate from difficulty. Open **How to prompt for roleplay** in the app for examples, also available in [the roleplay guide](docs/roleplay-guide.md).

Open **Finances → Manage finances** to create an account, start/change/end monthly income, or transfer existing funds. Enter net income after business expenses; an established business can earn USD 50,000 per month without being treated as an ordinary wage. Business proceeds stay in their receiving account until transferred. The header shows total cash and recorded monthly income; Finances shows each account and its ledger entries.

Income pays on each first of the month while its recorded version is active. Narrated changes may specify an effective date within the current turn; without one, they take effect at turn end. Manual finance changes use the current game date. Setting a monthly rate does not create an immediate deposit or credit earlier undocumented months. Changes preserve previous rates and payments, and transfers leave total cash unchanged.

In **Story Settings**, choose **Family covers rent and living costs** when living with parents or in a supported household. Your automatic personal living costs become zero; local market prices and previous ledger entries remain unchanged. **Follow the story** uses recorded household facts, then the starting background. Unknown older households retain independent-adult costs until specified.

The difficulty slider runs from **Forgiving** to **Challenging**, with **Balanced** preserving the original odds. It adjusts uncertain rolls by up to +30 or −30 and guides the narrator toward more ambitious outcomes at easier settings. It does not change the rules selected by the play style. A background such as **UAE royalty** is an established starting identity with family access and support, while personal cash remains separate.

## Storage and privacy

Lives: `~/Library/Application Support/LifeGPT/Lives/`

Preferences and usage estimates: `~/Library/Application Support/LifeGPT/`

API keys: macOS Keychain, service `app.lifegpt.provider-credentials`.

There is no account service, analytics SDK, cloud save service, or automatic cloud fallback. A selected cloud provider receives the current life context needed for narration/setup. A local provider sends requests to the exact server you configure. Point it at localhost for inference on your own Mac. A remote server URL is not offline operation.

Provider requests use an ephemeral HTTP session with no cookie storage, cached responses, or automatic redirects.

Use **Export Save** for backups of open lives. It uses SQLite's backup API so committed WAL data is included. Copying a live SQLite file with Finder can omit recent writes. Import creates an independent copy with a new identity.

Opening an older save migrates its existing ledger and income streams into a **Personal** account without changing amounts or past transactions. Migration does not infer income from prose, add missing payments, or backfill undocumented earnings. Record an intended recurring source through Manage finances from the current game date.

For isolated development sessions, set `LIFEGPT_DATA_DIR` to a separate directory before launching the executable.

## Current implementation choices

Economic figures produced during setup are estimates for user review, not historical research. Currency denomination is fixed within an existing life; a move can revise the context and local cost assumptions while continuing in that accounting currency. Automatic foreign-exchange conversion is not implemented.

Investments are conservative interest-bearing deposits, not a stock-market simulator. Asset resale returns 80% of the recorded purchase value. Loans use a fixed 8% annual rate and income-based qualification. These game constants are explicit in the engine and narration prompt.

Context compaction uses deterministic excerpts, avoiding additional paid summarization calls. Relevance retrieval is lexical, not embeddings. Free-form historical/technological accuracy depends on the model and the reviewed world brief; it is not guaranteed by a complete historical knowledge database.

A local content tripwire supplements provider safety controls and the system policy. It is a conservative heuristic, not a comprehensive semantic classifier. Sexual content involving minors is prohibited at every setting.

Narration is displayed after validation, not streamed speculatively. One repair is attempted for invalid output. If it still fails, the entire turn stays unsaved: no time, money, memories, or correction text enter the story. Your action returns to the composer, and **Retry reply** repeats it with the same skip duration and reply-length choice. Editing the action or changing the life invalidates that retry. A cut-off response is retried as a complete structured reply through the single repair path. Completed model responses still count toward usage even when a turn is rejected.

The estimated spending limit uses the input/output rates you enter, conservatively reserves each request's output budget, and records completed responses including unusable output. Provider-side charges for failed/disconnected requests may not appear; billing dashboards remain authoritative. Cloud API behavior and local model quality need real-provider smoke testing with your credentials/server.

## Project layout

- `Sources/LifeCore`: game rules, persistence, prompts, providers, setup and memory.
- `Sources/LifeGPT`: SwiftUI app, view model, Keychain and app preferences.
- `Sources/lifelab`: original mock and paid voice-test command-line tools.
- `Tests/LifeCoreTests`: network-free Swift Testing suites.
- `Fixtures`: narration scenarios and a legacy database-schema fixture.
- `packaging` and `scripts`: bundle metadata, app icon generation, DMG and notarization.
- `docs/game-outline.md`: the original approved product brief.

Read [the architecture notes](docs/architecture.md) for engine invariants and [the manual verification checklist](docs/manual-testing.md) before distributing a release.

See [verification results](docs/verification.md) for the checks performed during implementation and the release checks still to run.
