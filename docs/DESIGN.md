# LifeGPT design

LifeGPT is a text life simulation for macOS. The player lives one life from birth to death; an AI model
narrates each turn, introduces events, and reports what changed. The player brings their own API key.

## Principles

1. **Local state is the memory.** Every fact the story depends on (money, people, major moments, the date)
   lives in a save file on the player's Mac. Each narration call is stateless: the prompt is rebuilt from the
   save every turn, so the AI always reads the current truth and never relies on chat history.
2. **The game owns the numbers.** The AI returns *deltas* in a strict JSON schema. The game clamps them,
   moves time forward only, accrues income and expenses itself, and writes the result.
3. **Time and place shape the story.** The current in-game date and location, plus a decade-level era note,
   are in every prompt, and the system prompt requires period-accurate prices, technology and events.
4. **The provider is swappable.** The engine only talks to `LLMProvider`. Claude is the first implementation.

## Layout

```
Sources/LifeGPTCore/        platform-neutral engine (unit tested)
  Models/GameState.swift    the save schema
  Models/GameDate.swift     month-resolution calendar
  Engine/PromptAssembler    state -> prompt, with a size budget
  Engine/TurnResult         the AI's reply schema (JSON Schema + Codable)
  Engine/StateApplier       reply -> state changes
  Engine/HistoryCompactor   folds old turns into chapter summaries
  Engine/EraGuide           decade anchors for plausibility
  Engine/GameEngine         one turn end to end, plus the random event roller
  Providers/                LLMProvider protocol, AnthropicProvider
  Persistence/SaveStore     one JSON file per life
Sources/LifeGPT/            SwiftUI app (macOS 14+), Keychain storage for the API key
Packaging/                  Info.plist and build_dmg.sh
.github/workflows/macos.yml tests + universal DMG on a GitHub macOS runner
```

## Save schema (`GameState`, schema version 1)

| Field | What it holds |
|---|---|
| `character` | name, gender, birth date and place, occupation, education, traits |
| `world` | current in-game date (year + month), location, currency |
| `stats` | health, happiness, smarts, looks (0-100) |
| `finances` | cash, annual income, annual expenses, debt |
| `relationships` | name, relation, closeness 0-100, status (active/estranged/deceased), recent notes |
| `timeline` | major moments with date and importance 1-5 |
| `turns` | every turn: dates, player action, narration, events, change log |
| `chapters` | AI-written summaries of older stretches of turns |
| `firstUnsummarizedTurn` | where the verbatim history starts |
| `pendingChoices`, `isDead`, `causeOfDeath` | play state |

Saves live in `~/Library/Application Support/LifeGPT/Saves/<id>.json`, written atomically after every turn.
`schemaVersion` exists so later versions can migrate old saves.

## A turn

1. **Compact if needed.** If there are at least `keepRecent + batchSize` (8 + 8) unsummarized turns, the oldest
   8 are sent to the model with a "keep every concrete fact" summarization prompt and replaced by one chapter.
   If chapters exceed 10, the oldest 4 are merged. Timeline entries are never summarized away.
2. **Maybe roll an event.** 30% of turns get a game directive: "introduce one unexpected minor/major event,
   category: health/family/career/...". Career and romance are excluded for young children. The AI also adds
   events on its own when the story calls for it.
3. **Assemble the prompt** from the save, in this order: character sheet with stats and money, world (date,
   location, era note), people, chapter summaries, major moments, the last 8 turns verbatim, the directive,
   the player's action. If it exceeds the budget (~60k characters, ~15k tokens) it trims oldest chapters,
   then the least important moments below importance 4, then older verbatim turns (never below 2).
   The system prompt is fixed, so it is prompt-cached.
4. **Call the model** with the reply schema as a structured output, so the reply is always valid JSON.
5. **Apply** the reply: advance the date (0-120 months), accrue `(income - expenses) * months / 12`,
   apply clamped stat deltas, one-off cash, income/expense/debt changes, job/education/location changes,
   upsert relationships by name, append timeline entries, record death. A readable change log is kept per turn.
6. **Save** and show the new narration, events, changes and suggested choices.

## Reply schema (`TurnResult`)

`narration`, `monthsElapsed`, `statChanges{health,happiness,smarts,looks}`,
`financeChanges{oneOffCash,annualIncomeChange,annualExpensesChange,debtChange}`, `newOccupation`,
`newEducation`, `newLocation` (empty string = unchanged), `newTraits[]`, `events[{title,description,category}]`,
`relationshipChanges[{name,relation,closenessChange,status,note}]`, `timelineEntries[{title,summary,importance}]`,
`choices[]`, `died`, `causeOfDeath`. Every property is required and there are no nulls, which keeps the schema
compatible with strict structured outputs across providers.

## Provider

`AnthropicProvider` calls the Messages API with the player's key, `output_config.format` for the schema,
`effort: medium`, a cached system prompt, and server-side refusal fallback. The default model is
`claude-opus-5-5`; Settings offers `claude-sonnet-5-5` and `claude-haiku-5-5` as cheaper options.
Adding another vendor means one `LLMProvider` implementation and a `ProviderKind` case.

## Distribution

`Packaging/build_dmg.sh` builds a universal binary with SwiftPM, wraps it in `LifeGPT.app`, ad-hoc signs it
and creates `LifeGPT.dmg`. CI runs it on `macos-15` and uploads the DMG as a workflow artifact. The app is not
notarized (that needs a paid Apple Developer ID), so first launch needs right-click > Open.

## Next steps

- Money display in the save's currency symbol rather than `$`.
- Streaming narration so text appears as it is written.
- Richer mechanics the AI can't override: aging health decline, school stages by age, inheritance.
- An OpenAI-compatible provider for other vendors and local models.
- Save migration when `schemaVersion` changes; export/import of lives.
- Developer ID signing and notarization in CI once there is an Apple account to sign with.
