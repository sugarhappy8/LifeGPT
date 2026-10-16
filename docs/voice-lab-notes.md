# Voice Lab Notes

Results from `lifelab voice` runs against the real API. One section per run; newest last.

## Setup

- Command: `lifelab voice --scenarios Fixtures/voice/scenarios.json --seed Fixtures/voice/seed.json --runs 3 --yes`
- Model / effort: _(fill in)_
- Date: _(fill in)_
- Refusal fallback accepted by the API: _(yes / no, and what happened)_

## Results

| Scenario | Run | Valid JSON first try | Largest gain attempted | Gain accepted | Pass | Tokens in / out |
|---|---|---|---|---|---|---|
| spoons | 1 | | | | | |

Totals: passed _/_, valid JSON first try _/_.

Targets (not gates): valid JSON first try in at least 5 of 6 scenarios; over-cap attempts in at most 1 of 3 runs for `spoons` and `injection` after tuning. The hard check is that no accepted gain ever exceeds a scenario's bound.

## Prose observations

_(Does the narration sound like a novel about one person? Clichés that slipped through? Length vs. the 200-word target? Did money claims get a realistic first step instead of a payout?)_

## Voice Bible changes

_(What was edited in `Sources/LifeCore/Resources/voice.md` or `system.md`, and why.)_

## Open issues

_(Anything found that the code or prompts should fix next.)_

## Desktop implementation update — 2026-10-16

The native app now includes Anthropic, Gemini, and local providers, usage accounting, editable setup, and local two-step narration. New automated tests use stubbed transports and providers. No paid live voice-lab run was performed during this implementation. The original live-results table above remains intentionally unfilled; complete it with real model observations before making provider-quality claims.
