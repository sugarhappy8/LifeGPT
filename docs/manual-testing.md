# Manual verification before release

Use an isolated data folder for destructive checks:

```sh
LIFEGPT_DATA_DIR="$(mktemp -d /tmp/lifegpt-qa.XXXXXX)" \
  dist/LifeGPT.app/Contents/MacOS/LifeGPT
```

Do not run these checks on a valuable save without exporting it first.

## Offline desktop flow

1. Start with the default Offline demo. Create a character with all required fields.
2. Review the manual setup, edit currency/economy and family tier, and begin.
3. Send an action with the button and with Command-Return. Check that Return can compose multiline text.
4. Choose a suggested action; it should populate the composer without sending automatically.
5. Look for work, then skip one month. Confirm payroll, living costs, date and age match the ledger.
6. Skip long enough to exhaust savings without income. Cash should stay non-negative and unpaid bills should appear as debt.
7. Ask `((balance))` and `((age))`; no narrator turn should be generated. Use `((longer))` and verify Story Settings changes.
8. Inspect Life, Finances, People, Decisions, Timeline, Paths, and Memory.
9. Change the Voice Bible, length, and Swing Dial. Close and relaunch the app; settings and story should persist.
10. Create a second life. Switching between lives must preserve independent histories and finances.
11. Export a save and story. Import the save as another life and confirm the original remains independent.
12. Cancel a deletion, then delete only a disposable test life. Reopen the remaining life.
13. Try light and dark appearances, 14–24 pt reading text, narrow windows, keyboard navigation, and VoiceOver labels.
14. After enough turns, load older messages and inspect local chapter excerpts. Export should still contain the entire story.

## Household, background and difficulty

1. In a disposable adult life, open Story Settings and choose **Family covers rent and living costs**. Skip three months. Confirm no living-cost charges or new living-cost arrears, while wages and voluntary purchases still work. Finances should display personal living costs of zero.
2. Select **I pay my own living costs**, skip one month, and confirm exactly one normal monthly bill. Existing ledger history must remain intact. With **Follow the story**, ask to move out at the end of a scene; later months should use the new household status.
3. Set difficulty to Forgiving, save, relaunch, and confirm it persists for this life only. A successful turn's Memory audit should show its raw roll and the adjusted value. Change settings after a failed turn and confirm the pending Retry is invalidated.
4. Start a life with a background such as “UAE royalty, living in the family home.” The reviewed draft should establish the royal identity, relatives, access and family support, while keeping the personal wallet separate. Verify household and family tier before beginning.
5. With a live model, compare a prepared website-growth attempt at Forgiving and Balanced settings on separate test lives. Easier settings should favor the intended ambition; cash still needs validated sources. Check established gifts referring to a parent by name and as Dad/Mom; the ledger should use the canonical saved name.

## Accounts, recurring income and play style

1. Import a disposable v1/v2 save with known balance, ledger and income. After migration, its existing cash and streams should belong to **Personal**, with unchanged amounts and dates. A business claim appearing only in old prose must not create income or back pay.
2. In a disposable USD life, open **Finances → Manage finances → Accounts**. Open business and savings accounts; each starts at zero and total cash stays unchanged. Reopen the manager after each applied edit.
3. Under **Income**, start a business source at `50,000.00` per month, paid into the business account, with a reason describing net profit after expenses. Confirm its current-date start and destination in Finances; creating the rate must not deposit USD 50,000 immediately.
4. Add a separate USD 1,500 monthly allowance to Personal with a reason, and select a family-supported household. Skip three months. Expect three USD 50,000 business payments, three USD 1,500 personal payments, and no personal living-cost charges. Business earnings must not silently become personal cash. Repeat with independent living costs and check that only Personal pays the bills.
5. Transfer USD 10,000 from business to Personal. Check the matching debit/credit, account labels, and unchanged total cash. Reject a transfer exceeding the source balance even when other accounts hold enough money. Opening a savings account alone must not generate interest.
6. Change the business source's rate and receiving account, skip a month, then end it and skip again. Confirm earlier rate versions and ledger payments remain intact, with payments following the new version and stopping at the end date. Try a duplicate active name, missing reason, zero/negative amount, and a USD amount smaller than one cent; rejected edits must change nothing. Close and reopen the manager after any stale-save notice.
7. With a fixture endpoint or live narrator, start business income midway through an explicit time skip. Verify only first-of-month boundaries on/after its effective date pay; an omitted effective date defaults to turn end. Link it to an existing profitable business path and verify the default path payout is not added again, including in later turns after the stream ends.
8. Use **Simulation** and **Sandbox** in separate test lives, then relaunch to confirm the per-life choice persists. Simulation should enforce wage bands; Sandbox may accept a declared fictional income outside those bands while still rejecting unknown accounts, invalid dates and unaffordable spending. Difficulty and household support should retain their separate settings.
9. Open **How to prompt for roleplay** and copy an example. Confirm the guide explains net monthly income, receiving accounts, transfers, time skips and checking recorded payments. A prose claim alone must not be treated as proof of a saved income stream.
10. Return a proposed account opening, income change and invalid transfer twice through a fixture endpoint, or fail its repair request. Accounts, streams, ledger, date, revision and transcript must all remain unchanged. A manual finance edit should instead add a timeline event without adding a fictional player/narrator exchange or advancing time. Export/import and relaunch should preserve the accounts and income history.

## Cloud providers

For each provider, enter your own key in Settings. Never put it in a screenshot, repository, or chat transcript.

1. Select a model available to your account; set its current pricing estimates.
2. Test connection. Verify the response and usage entry.
3. Generate a setting and review/edit its economy; play an ordinary turn. Open World & Economy, generate an updated draft for a new location/era, then review and save a new version.
4. Try the spoon claim and prompt-injection scenarios in `Fixtures/voice/scenarios.json`.
5. Set a deliberately tiny estimated daily spending limit; a request should fail before it is sent. Restore a reasonable limit.
6. Stop a pending reply. No uncommitted changes should appear in the transcript or ledger; the composer should retain the attempted action.
7. Try an invalid key/model and verify the useful error without credential disclosure.
8. Check refusal, malformed JSON, and truncated-response behavior with a test endpoint or fixtures. No partial JSON should be displayed as narrative.
9. Return invalid changes twice using a fixture endpoint. Confirm the error appears outside the story, your action returns to the composer, and date, balance, transcript, and memories stay unchanged. Use **Retry reply** with a valid response and confirm exactly one turn is saved.
10. Repeat with a time skip and a custom reply length; Retry must preserve both. Editing the action, switching lives, or updating Story Settings must clear the retry. An external save revision change must prevent Retry from sending a request.
11. Use `Fixtures/narration/university-letter.json` with omitted/null/empty/whitespace-only `crime_attempt` values. The scene should succeed without a repair, payout, fine, or legal-status change.

## Local model servers

1. Start LM Studio at `http://localhost:1234/v1`, or Ollama at `http://localhost:11434/v1`.
2. Load an instruction-tuned model and enter its exact name.
3. Match the app context setting to the server's configured context window. Begin with at least 32k where possible.
4. Leave two-step mode enabled. Test connection, setup, and a story turn.
5. Opt into JSON Schema only if the server/model supports it. Verify both modes.
6. Disconnect the internet while leaving the local server running. Local narration should continue.
7. Stop the local server. The error must not trigger any cloud fallback.

## Release bundle

- Run the full network-free `swift test` suite.
- Build a release bundle, validate its signature, and create the DMG.
- Install from the mounted DMG into Applications, eject it, and relaunch from Applications.
- Test resource loading and a saved life after relocation.
- Verify the requested architectures with `lipo -archs`.
- For signed distribution, notarize and staple both the app and DMG; validate on a second Mac if available.

Live APIs, local model behavior, Intel/universal release binaries, and notarization require these external checks; passing unit tests alone does not establish them.
