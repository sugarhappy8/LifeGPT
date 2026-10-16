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
- Character creation with searchable preset nations/regions and separate birthplace/starting residence, followed by editable world/economy review. AI and manual setup use the selected place/date; personal starting savings remain age-based, regardless of family wealth.
- One SQLite save per life, atomic turn commits, schema v4 legacy-save migration, import, export, and a readable Markdown story export.
- Anthropic and Gemini REST clients; a local OpenAI-compatible adapter for LM Studio and Ollama. Two-step narration can draft prose, then extract and validate changes.
- macOS Keychain credentials, transient HTTP retries, connection testing, response usage history, and a configurable estimated daily spending limit.
- Engine-owned income, living costs, asset ownership/resale, deposits and interest, loans, repayments, arrears, and abstract fate-gated criminal outcomes.
- Personal, business, savings, tax-reserve and custom-purpose accounts; funded transfers, default-account selection, account closure, ownership and access enforcement.
- Gross business revenue, employee/group payroll, owner salary, recurring costs, tax reserves/remittance and unpaid obligations, with dated monthly statements. Complete company sales require revision-bound review and remove access to transferred accounts.
- Bundled offline nation catalog: 249 current countries/territories, 31 historical identities and 5,070 regional presets. Dated fiscal profiles cover every country through sourced components or disclosed estimates, with per-life overrides.
- Wage, self-employment, scalable business profit, allowance, and rental income, with named destinations and dated rate history.
- Staged business paths with elapsed-time and capital requirements. Their default payout begins at the profit stage; a linked recorded business income stream replaces that payout.
- Persistent cast, decisions, life state/history, timeline, unresolved threads, narrator notes, and suggested choices.
- Relevance-scored context packing and local chapter-excerpt compaction. Full transcripts are retained.
- Per-life Simulation/Sandbox play style, difficulty, household support, Voice Bible, Swing Dial, automatic/custom reply length, and tone preferences. Death closes the life while leaving its history readable.
- Read-only out-of-character questions such as `((balance))`, `((age))`, `((income))`, `((who))`, and `((decisions))`. `((longer))` and `((shorter))` change the app's reply-length preference for the current life.

Choose **Simulation** to resolve attempts through the game's rules, or **Sandbox** to declare fictional outcomes while retaining validated financial records. Play style is separate from difficulty. Open **How to prompt for roleplay** in the app for examples, also available in [the roleplay guide](docs/roleplay-guide.md).

Open **Finances → Manage finances** for legacy recurring net income and ordinary transfers. Open **Businesses & payroll** for gross-revenue simulation: create a company with a business account and preset jurisdiction, then record revenue, employee pay, owner salary, operating costs and scheduled transfers. For a website earning USD 50,000/month before costs, enter **gross revenue 50,000** and **owner salary 1,500 gross**. Employee pay needs its own explicit amounts. Owner salary debits the company; only the amount after employee deductions reaches the personal destination.

New business records accrue by calendar day and settle monthly in arrears. Dated hires, rate changes and expenses preserve earlier terms. Due taxes, employee payroll, operating costs and owner pay follow the displayed priority, with outstanding balances retained when funds are insufficient. Restricted tax reserves are separate from spendable cash. No personal savings silently fund a business shortfall.

Legacy income sources retain their existing net-income behavior and first-of-month payments. Convert an existing business account explicitly before adding gross revenue/payroll, so old net income is ended rather than counted twice. Changes begin on the chosen current/future date; neither mode backfills undocumented earnings. Transfers move recorded cash without increasing income.

In **Story Settings**, choose **Family covers rent and living costs** when living with parents or in a supported household. Your automatic personal living costs become zero; local market prices and previous ledger entries remain unchanged. **Follow the story** uses recorded household facts, then the starting background. Unknown older households retain independent-adult costs until specified.

The difficulty slider runs from **Forgiving** to **Challenging**, with **Balanced** preserving the original odds. It adjusts uncertain rolls by up to +30 or −30 and guides the narrator toward more ambitious outcomes at easier settings. It does not change the rules selected by the play style. A background such as **UAE royalty** is an established starting identity with family access and support, while personal cash remains separate.

## Storage and privacy

Lives: `~/Library/Application Support/LifeGPT/Lives/`

Preferences and usage estimates: `~/Library/Application Support/LifeGPT/`

API keys: macOS Keychain, service `app.lifegpt.provider-credentials`.

There is no account service, analytics SDK, cloud save service, or automatic cloud fallback. A selected cloud provider receives the current life context needed for narration/setup. A local provider sends requests to the exact server you configure. Point it at localhost for inference on your own Mac. A remote server URL is not offline operation.

Provider requests use an ephemeral HTTP session with no cookie storage, cached responses, or automatic redirects.

Use **Export Save** for backups of open lives. It uses SQLite's backup API so committed WAL data is included. Copying a live SQLite file with Finder can omit recent writes. Import creates an independent copy with a new identity.

Opening a pre-account save assigns its existing ledger and income streams to **Personal**; the newer simulation migration preserves existing accounts, amounts, access and past transactions. Migration does not infer income from prose, add missing payments, or backfill undocumented earnings. Record an intended recurring source through Manage finances from the current game date.

For isolated development sessions, set `LIFEGPT_DATA_DIR` to a separate directory before launching the executable.

## Current implementation choices

Country selection uses stable catalog IDs; typing a search query cannot create a nation. States/provinces are required for modeled regional jurisdictions. Historical presets and dated currency associations are included, but historical subdivision boundaries are incomplete: unsupported eras are labeled historical area estimates, and future dates use projections. Original location text remains in older saves; ambiguous locations require a preset choice instead of a silent guess.

Every country has an offline economic/fiscal baseline. **Worldwide coverage is not worldwide legal verification.** Country-local wage/living-cost scales derive from CLDR territory data and explicit modeling assumptions. Most tax rates, deductions, eligibility, employment costs and remittance schedules remain estimates. Narrow sourced reference components include US FICA/federal wage floors for 2003–2005 and ordinary UAE corporate threshold/rate plus wage exclusion for 2023–2026. US withholding and corporate/franchise provisions, UAE pension applicability, cross-border treatment, special regimes and unverified historical years stay labeled estimates. **Tax rules & assumptions** shows component status, dates, sources and editable per-life assumptions.

The accounting currency and denomination of an existing life stay fixed. Moving can apply dated local wage/cost estimates converted into that accounting currency using a recorded FX assumption. Bundled conversion scales are approximate, not historical market quotes; unknown retired-currency pairs require an explicit estimate. This does not create foreign-currency bank balances or reinterpret old ledger entries. Overrides and catalog updates affect new calculations only; settled assessments retain their original immutable profiles.

Personal tax-year boundaries are modeled separately from the company's default calendar accounting year, including the UK April 6 boundary. Payroll withholding is an estimated cumulative earned-period calculation; it is not a substitute for exact statutory payroll tables. Transactions are not blindly charged VAT/sales tax merely because money was deposited.

Company-sale support currently handles a complete ownership transfer on a reviewable sale date. It credits agreed proceeds once and transfers the company's accounts/obligations without also crediting company cash to the player. Partial sales, retained equity/management rights and post-sale employment require additional explicit accounting support and are not silently inferred.

Investments are conservative interest-bearing deposits, not a stock-market simulator. Asset resale returns 80% of the recorded purchase value. Loans use a fixed 8% annual rate and income-based qualification. These game constants are explicit in the engine and narration prompt.

Context compaction uses deterministic excerpts, avoiding paid summarization calls. An optional context-selection request (Automatic, Always or Off) selects relevant saved history before narration; it is read-only and counts toward usage. Essential date, ownership, account and obligation facts are always included. Local fallback retrieval is lexical, not embeddings. Free-form historical/technological accuracy depends on the model and the reviewed world brief; it is not guaranteed by a complete historical knowledge database.

A local content tripwire supplements provider safety controls and the system policy. It is a conservative heuristic, not a comprehensive semantic classifier. Sexual content involving minors is prohibited at every setting.

Narration is displayed after validation, not streamed speculatively. One repair is attempted for invalid output. If it still fails, the entire turn stays unsaved: no time, money, memories, or correction text enter the story. Your action returns to the composer, and **Retry reply** repeats it with the same skip duration and reply-length choice. Editing the action or changing the life invalidates that retry. A cut-off response is retried as a complete structured reply through the single repair path. Completed model responses still count toward usage even when a turn is rejected.

The estimated spending limit uses the input/output rates you enter, conservatively reserves each request's output budget, and records completed responses including unusable output. Provider-side charges for failed/disconnected requests may not appear; billing dashboards remain authoritative. Cloud API behavior and local model quality need real-provider smoke testing with your credentials/server.

## Project layout

- `Sources/LifeCore`: game rules, persistence, prompts, providers, setup and memory. Geography/fiscal rules are in `Geography`, with catalog data and attribution in `Resources/Geography`.
- `Sources/LifeGPT`: SwiftUI app, view model, Keychain and app preferences.
- `Sources/lifelab`: original mock and paid voice-test command-line tools.
- `Tests/LifeCoreTests`: network-free Swift Testing suites.
- `Fixtures`: narration scenarios and a legacy database-schema fixture.
- `packaging` and `scripts`: bundle metadata, app icon generation, DMG and notarization.
- `docs/game-outline.md`: the original approved product brief.

Read [the architecture notes](docs/architecture.md) for engine invariants and [the manual verification checklist](docs/manual-testing.md) before distributing a release.

See [verification results](docs/verification.md) for the checks performed during implementation and the release checks still to run.
