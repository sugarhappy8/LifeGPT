# Implementation verification — 2026-10-16

Environment: Apple Silicon macOS, Swift 6.4 with Xcode 27. Release compilation and DMG creation are left to the project owner, as requested.

## Completed

- `swift test`: **244 tests across 30 suites passed** (232 core tests and 12 desktop-model tests), including the desktop target's debug compilation. The final run reported no compiler warnings or errors.
- Coverage includes v1 save migration, independent import without modifying the original, SQLite backup with WAL data, atomic commits, stale revision rejection, cancellation, starting balances, money gates, monthly accounting, debt, deposits/assets, business stages, crime consequences, provider request/response fixtures, setup/world drafts, memory compaction, and continuity validation.
- The debug app bundle was assembled with the packaging script. Its property list and ad-hoc code signature passed validation, and its resource bundles, prompts, icon, and license notice were present.
- Native desktop smoke testing used an isolated temporary data folder and the built-in offline demo. Character creation/review, opening narration, finding a job, skipping one month, the financial inspector, database-backed balance queries, Command-Return, story controls, and app Settings worked.
- In that scenario, starting cash was $1,750. A $1,400 monthly wage and $1,200 monthly living costs produced the expected $1,950 balance after the month skip, with matching ledger entries.
- The desktop layout was visually inspected at the default window size; the chat, sidebar, inspector, and settings were readable without overlapping controls.
- Packaging shell scripts passed `bash -n`; `packaging/Info.plist` passed `plutil -lint`; tracked changes passed `git diff --check`.

The offline and fixture checks below required no live model requests or API credentials.

## Crime validation and retry regression checks

- The university-letter fixture passes with omitted, null, empty, and whitespace-only crime fields in both single-call and two-step narration. Normal memories are retained without crime consequences or a repair call.
- Real crime attempts retain their age, reason-length, cooldown, and fate checks. Persistent invalid output and repair transport failures leave every database table unchanged, including otherwise-valid money, time, and memory changes.
- Desktop-model tests cover retrying ordinary actions and explicit time skips, preserving the reply length, clearing retry after text edits or life switches, rejecting stale revisions, and dismissing errors without saving them.
- Rejected responses remain counted in usage. Cancelling a repair leaves no saved turn and remains a cancellation rather than a retryable validation error.
- The rebuilt debug desktop app was tested against a localhost fixture server using an isolated life. Failed replies restored the composer and kept the story/date/balance unchanged. Retry saved one ordinary scene; retrying a one-month skip advanced exactly one month and charged living costs once ($1,750 to $550 with no wage).
- The final error panel, native validation-details dialog, and return to the story were visually checked. The error panel has a bounded scrolling area so diagnostics cannot expand the window layout.
- The existing Richard save and its historical correction message were preserved. No live Anthropic request was made during this fix.

## Household, royalty, gift identity and difficulty checks

- Adult family support preserves wages and personal purchases while removing automatic living costs and new living-cost arrears. Moving out changes later bills; explicit settings override inferred household status. Loan affordability uses personal household costs.
- Legacy settings retain Voice Bible, automatic length and tone while defaulting difficulty to Balanced and household to Follow the story. Settings survive reopening and invalidate pending Retry when changed.
- Manual setup recognizes UAE royalty, Emirati royal family and the spelling “royailty,” establishes a royal premise and supported household, and leaves personal starting cash unchanged. Generated setup receives equivalent semantic instructions; model interpretation still requires the normal draft review.
- Gifts referencing Dad, my father, Gerald or Gerald Hale resolve to the existing canonical giver, save that name, and retain cap/cooldown checks. Ambiguous names and same-turn deaths cannot bypass validation.
- Difficulty affects actual business success gates as well as shared narration context. The launch threshold succeeds on 91 of 100 raw rolls at Forgiving, 61 at Balanced and 31 at Challenging. Money caps remain enforced. Latest-turn audit stores and displays raw and adjusted fate without a schema migration.
- The rebuilt debug app was smoke-tested with an isolated offline life. The difficulty slider and household picker saved correctly. A three-month skip preserved the $1,750 balance, produced no bill or debt, and displayed $0 personal living costs. A raw roll of 32 displayed as 62 at difficulty 0. Layout, finances and audit controls were visually checked.
- A malformed initial reply followed by a repair network failure now also produces the retryable validation failure. Existing nullable/blank crime fixtures and whole-turn rollback tests still pass.
- Richard's existing save was backed up using SQLite backup, then its household setting was changed to family-supported through the rebuilt app. The inspector showed $0 personal monthly costs. A table-by-table comparison verified that only session settings and revision changed (20 → 21); all history, ledger, balances, cast and memories were identical. Claude Sonnet 5.5 stayed selected. No live API requests were made. Old bills and existing arrears were not refunded or removed.

## Banking, recurring income and play style checks

- Schema v3 migration preserves existing ledger amounts, balances, income and history under Personal. New account, transfer, dated rate-change and reopen tests pass; invalid writes, overdrafts, overflow and stale revisions roll back atomically.
- A provider JSON fixture records $50,000/month as recurring business profit in a newly opened business account. Zero elapsed time pays nothing; the next monthly boundary pays exactly $50,000. Simulation accepts scalable business income as well; wage and small self-employment rules remain separate.
- Effective-date tests cover income starting mid-skip, changed rates, ended sources, multiple sources, separate personal allowances, and family-supported/independent households. Linked income replaces a legacy business-path payout, including after the income ends, preventing double payments and a fallback payout after closure.
- Transfers conserve total cash and cannot spend another account's funds. A transfer can fund an ordinary expense or asset purchase in the same turn. Loans use current recurring income and age at the turn's endpoint; ended/future income cannot support a new loan. Reserved arrears IDs cannot become assets or investments.
- Invalid narration and repair transport failures preserve accounts, income history, ledger, date, transcript, positions and revision. Desktop finance edits reject stale life IDs/revisions, refresh stale snapshots, and invalidate pending Retry.
- Sandbox persists per life, honors established business stages without Simulation waits, supports documented cash corrections, and relaxes ordinary economic gates while preserving account consistency. Older settings default to Simulation.
- An isolated debug app with an offline demo life was operated through native UI: opened Website business, entered $50,000/month net profit, and skipped January 1 → April 1, 2003. The business received exactly $150,000; Personal retained $1,750. Transferring $10,000 to Personal resulted in $140,000 business / $11,750 personal, with total cash unchanged at $151,750. Database inspection after quitting confirmed all amounts, three deposits, two story messages and the saved Sandbox setting.
- The finance editor, monthly-income header, account/ledger inspector, play-style control, and roleplay guide were visually checked. All QA data stayed in a temporary directory. Richard's actual save and selected provider/model were not edited by this pass. No undocumented historical earnings were backfilled and no live model calls were made.

## Claude structured-output grammar fix

- The expanded turn schema had 24 optional fields. Claude rejected its combined grammar complexity even though that count met the documented explicit limit. [Claude's guidance](https://platform.claude.com/docs/en/build-with-claude/structured-outputs#schema-complexity-limits) recommends requiring fields with safe defaults and reducing optional branches.
- Claude now receives a flat, four-field native response schema with no optional fields, no nullable branches and only one object. The `resolution` field transports JSON as a string. The complete logical contract remains in the prompt; the app decodes that string into its typed resolution and runs the same validation before saving. Other providers retain their existing transport. No extra requests or automatic retries were added.
- The logical generation contract uses required empty arrays for unused systems, false for a living character, and empty notes/choices. Crime remains omitted or null, and omitted cast fields preserve recorded information. Money and financial actions require explicit account IDs; income updates include kind/rate/account/effective date/reason. Older response shapes still decode, with no save migration.
- New tests exercise both narration modes, escaped quotes and Unicode, $50,000/month business income and three exact monthly deposits, malformed inner JSON, invalid financial changes, single repair, usage accounting and atomic rollback. A grammar HTTP 400 makes one request without committing a turn or starting a repair loop. A schema regression check enforces the flat format's zero optional/nullable branches.
- A live synthetic request using the selected Claude Sonnet 5.5 model accepted the compact format and returned a decodable resolution. A second live check ran the actual `LLMNarrator` → `TurnProcessor` → SQLite pipeline: it created a business account and recorded $50,000/month business profit with no repair, no elapsed time, no premature payout and exactly one saved turn. Both completed responses were counted in isolated QA usage accounting. Richard's save and app settings were not changed.
- The final debug bundle passed property-list and code-signature checks and launched successfully with an isolated data directory. The launch produced no diagnostic output. Release compilation and DMG creation remain for the owner.

## Remaining release checks

- Complete longer live Anthropic playthroughs, run live Gemini checks, and test your local model/server configuration.
- Compile the release app and requested architectures on your distribution toolchain.
- Create and mount the DMG, install the app into Applications, eject the image, and test the relocated app.
- If distributing to others, sign with your Developer ID certificate and complete notarization/stapling.
- Complete the broader accessibility, appearance, and multi-life desktop checklist in [manual-testing.md](manual-testing.md).

Commands and signing instructions are in [BUILDING.md](../BUILDING.md).
