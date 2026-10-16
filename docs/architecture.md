# Architecture and invariants

## Layers

`LifeGPT` is the native presentation layer. `AppModel` owns the selected store, settings, and the single active UI task. It creates providers only after the player has selected one. OOC questions and demo mode do not require credentials. `LifeCore` is usable independently from the GUI through `lifelab` and tests.

`TurnProcessor` is an actor. Reentrant attempts are rejected while a turn is active. It captures a database revision before requesting narration, so another window/process changing story settings or committing a turn invalidates the stale result. The final store write is transactional. Cancellation is checked before commit, including when a narrator fails to propagate cancellation.

A turn classifies input, loads current truth and memories, rolls fate, asks the narrator, validates the proposed changes, optionally repairs once, then commits. Narrator output is never a direct database command. Financial actions are pure planned changes until the final transaction succeeds.

## What owns what

- Dates and completed age: Gregorian `GameDate`, validated elapsed durations, explicit UI skip overrides. Maximum 20 years per turn and calendar years 1–9999.
- Starting savings: 2%, 10%, or 50% of median monthly income for children, teens, and adults.
- Pay and bills: first-of-month accounting over `(previous date, new date]`. Income versions pay from their start date inclusive to their end date exclusive. `effective_from` must fall within the current turn; omission defaults to turn end. A rate change closes the old version and creates its replacement at the same date, preserving earlier rates. There is no daily proration or automatic back pay before the turn.
- Household: per-life `SessionSettings.household` overrides automatic inference. Automatic uses `household_support` state (`family_supported` or `independent`), then current housing text, then background. A supported family household pays zero automatic personal living costs, including after age 18. Independent costs still use the reviewed economy. Loan affordability uses the same personal cost. Narrated household changes take effect at turn end. Explicit settings stay in effect until edited. Historical charges are not rewritten.
- Difficulty: per-life 0–100 slider, default 50. Effective fate is `clamp(raw + (50 - difficulty) * 30 / 50, 1, 100)`. Narration, business, windfall and crime gates use this same adjusted value; age, time, funding and payout rules are unchanged. The audit keeps the raw roll in `turn_log` and the latest effective roll/difficulty in engine-owned life state. This uses existing JSON/state storage with no schema migration. Old settings decode missing fields without losing voice, length or tone.
- Accounts: balances derive from ledger entries assigned to stable account IDs; new personal/business/savings accounts open at zero. Up to 20 accounts, with unique IDs/names. Paired transfer debits and credits preserve total cash. Spending requires enough money in its source account; other accounts do not silently cover it. Household bills use Personal.
- Income streams: up to 20 active named sources across wage, self-employment, business, allowance, and rental kinds. Positive monthly amounts are bounded at one trillion minor units. Simulation applies reviewed wage bands and the self-employment cap; scalable business/rental income has separate validation. Allowances, and business/rental rates above median income, require a rationale. Each stream names a receiving account; stream creation alone posts no cash.
- Play style: Simulation resolves attempts under the game's plausibility rules. Sandbox accepts declared fictional outcomes and relaxes wage/self-employment limits and selected gain caps/cooldowns. Known accounts, valid signs/dates, positive rates, funding, cast identity, bounded amounts and engine-owned source rules remain enforced. A narrated record adjustment is available only in Sandbox and cannot make an account negative. Difficulty remains a separate setting.
- Side hustle money: in Simulation, capped per period and shared across a rolling seven-day window to prevent repeated same-day farming.
- Gifts: known living cast, with a recorded death required for inheritance. Simulation adds family-tier caps for relatives and middle-tier caps for other givers, one gift/inheritance per turn, and a shared 90-day cooldown. Simulation windfalls additionally require fate ≥ 95 and a 730-day cooldown.
- Gift identity: exact names, unique first/last names and unambiguous family roles such as Dad resolve to the canonical existing cast name before money checks and ledger writes. Ambiguous/unknown givers remain invalid; introducing a person in the same turn does not authorize a gift. Validated status updates also govern that turn's gifts/inheritances.
- Investments: funded principal, fixed era-dependent interest, monthly engine calculation. Withdrawals cannot exceed principal.
- Assets: recorded purchases, no unowned sales, resale at 80% of purchase principal. Partial sale requests consume the corresponding recorded principal.
- Loans: adults with positive wage surplus and no outstanding debt; borrowing and payments are income-bounded. Interest accrues monthly at 8% annually.
- Bills beyond cash: ledger financing and an explicit arrears position, leaving cash at zero instead of inventing an untracked overdraft.
- Business paths: idea, capital, launch, traction, profit; 7/30/60/90-day stage waits, a real capital charge, and fate gates for launch/profit. Up to three active paths, one stage change per path per turn. A business stream linked by `path_id` replaces the legacy fixed profit payout from its effective date, including after the stream ends; a matching business stream name also suppresses the legacy payout. Ending income cannot reactivate an old default payment.
- Abstract criminal outcomes: one attempt per 30 days from age 16; fate chooses bounded proceeds or a fine, with legal-state/timeline consequences. No model-assigned proceeds.
- Cast continuity: a deceased cast member cannot be revived without an uncanny event and Swing Dial 2 or 3. Engine-owned life-state keys cannot be overwritten through narration.
- Ending: an accepted `life_ended` result stores an epilogue and closes further narrative turns. OOC queries and exports remain available.

After an unsuccessful repair, `TurnError.validationFailed(reasons:)` stops the entire turn before any database write. Engine-generated changes, including payroll and crime consequences, remain temporary too. Successful repairs commit once. Completed provider responses remain in app-level usage accounting even if the life was not changed.

An omitted or null `crime_attempt`, or an object with a whitespace-only reason, means no crime. The engine checks this before age or cooldown. Nonempty reasons are limited to 500 characters, with separate rejection messages for length, age, and cooldown violations.

The app retains failed action text, selected skip duration, resolved word target, original length-picker choice, life ID, and save revision in temporary memory. Retry uses those inputs with the currently configured narrator. Editing the text, changing lives, dismissing the notice, or successful completion clears the retry. Refresh and retry preflight check the revision; a changed save cannot silently replay the stale action. Validation details appear outside the transcript. A post-commit view-refresh error never offers a retry of the already-saved action.

## Persistence

Schema v3 migrates v1/v2 saves in place through GRDB migrations. It adds accounts, ledger/income account IDs, and optional income path links. Existing ledger entries and income streams are assigned to `personal` without changing amounts, dates, running totals, or transcript. Migration neither extracts income claims from prose nor backfills undocumented payments. The save also contains cast, decisions, timeline, state history, world/economy versions, settings, notes, choices, chapter excerpts, paths, threads, positions, turn audit, ending flag, and revision number.

`LifeStore.apply` opens accounts before posting ledger entries and applies income versions in the same revision-checked transaction as the story. Checked arithmetic, known accounts, nonnegative account balances, balanced transfers, positive income and valid dates guard financial writes. `applyFinancialChanges` shares those guards for **Manage finances**: edits take effect at the current date, increment the revision and add a “Financial records updated” event without advancing time or inserting narration/turn logs. The UI and `BankingEngine.manage` reject stale edits. Manual and narrated changes share income/transfer validators.

All model proposals and pending UI tasks are temporary. Only a committed turn appears in the durable transcript. Save backups use SQLite backup, not a raw file copy. Imported copies receive independent IDs. The library skips unreadable files while exposing their filenames/errors in the UI.

App preferences and usage records live outside individual lives. Credentials only enter macOS Keychain and provider request headers. Transcript export includes no credentials or private author notes.

## Context and memory

Approved starting identity is binding, including fictional royal-family backgrounds. Setup interprets free-form family status and support, records household responsibility, and keeps family resources separate from the personal wallet. The draft remains editable. Difficulty guidance distinguishes ambitious non-cash achievements (for example audience growth) from unvalidated money deposits.

The context includes identity, account balances and income destinations, play style, life state, world/economy, paths, positions, threads, cast, past choices, summaries, narrator notes, fate, recent dialogue, and the current attempted action. Lexical relevance and importance rank optional memory. A conservative UTF-8-based token estimate trims low-priority material before the request. Essential facts and the current input are preserved; if they cannot fit, the request fails with a setting correction instead of silently truncating them. The in-app roleplay guide explains declared outcomes, recurring net income, transfers, and checking the recorded finances; [its examples are also documented](roleplay-guide.md).

Every 40 unsummarized messages, the oldest 24 become a dated local excerpt chapter. Source messages remain intact. This avoids hidden summarization API spend and remains compatible with all providers. Long-lived characters with very large essential context may need a larger model window.

## Provider contracts

- Anthropic: Messages API, `output_config.format` with a flat four-field JSON schema to stay below Claude's grammar-complexity limits. Only `resolution` is transported as a JSON-encoded string; narration, notes and choices retain their ordinary types. The complete logical contract remains in the prompt. `LLMNarrator` decodes the inner resolution into the same typed model, and the normal validators and single-repair limit still apply before any commit. The app disables server-side refusal fallback. The original CLI retains its explicit configuration options. [Official structured-output documentation](https://platform.claude.com/docs/en/build-with-claude/structured-outputs).
- Gemini: `generateContent`, key in `x-goog-api-key`, `generationConfig.responseFormat.text` for JSON. Thinking parts are excluded from returned prose and counted in output usage. [Official generateContent structured-output documentation](https://ai.google.dev/gemini-api/docs/generate-content/structured-output).
- Local: `/v1/chat/completions`, with schema output opt-in. Two-step mode is the app default for local models. No fallback to a cloud provider. [Ollama compatibility](https://docs.ollama.com/api/openai-compatibility), [LM Studio chat completions](https://lmstudio.ai/docs/developer/openai-compat/chat-completions).

Retryable HTTP statuses receive at most two retries with bounded delays. Network timeouts and ambiguous transport failures are not automatically retried. Cloud response metering happens before JSON validation, so malformed or rejected output is still counted. Rates are explicitly user-editable estimates. Repairs and each stage of two-step mode reserve their own estimated budget.

The default HTTP transport uses an ephemeral session without ambient cookies, saved HTTP credentials, or response caching. Redirects are rejected, so a configured endpoint cannot forward credentials or story context to a different destination. Responses larger than 2 MB are rejected before decoding.

## Deliberate boundaries

No shared lives, server backend, community content, world packs, descendant mode, external tools, web lookup inside the game, embeddings, or stock-market simulation. World revisions are reviewed edits; a new currency does not silently reinterpret an old ledger. Complete era accuracy and semantic content classification remain model-dependent. See README for the practical limitations and BUILDING for release requirements.
