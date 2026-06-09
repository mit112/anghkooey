# M5 Eval Run Log

> Eval harness requires Apple Intelligence (macOS 26 or iOS device with Apple Intelligence enabled).
> Cannot be run on the iOS Simulator. Update this file after the first device run.

## How to run

From the repo root on a machine with Apple Intelligence enabled:

```bash
swift run --package-path Packages/AnghkooeyIntelligence EvalRunner
```

To update golden fixtures after a prompt change:

```bash
swift run --package-path Packages/AnghkooeyIntelligence EvalRunner --update-goldens
```

## Fixtures

20 fixtures in `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Fixtures/eval-fixtures.json`:

| ID | Domain |
|---|---|
| `biology-001` | Biology |
| `vocab-001` | Vocabulary |
| `history-001` | History |
| `chemistry-001` | Chemistry |
| `physics-001` | Physics |
| `history-002` | History |
| `geography-001` | Geography |
| `vocab-002` | Vocabulary |
| `cs-001` | Computer Science |
| `medicine-001` | Medicine |
| `astronomy-001` | Astronomy |
| `economics-001` | Economics |
| `art-001` | Art |
| `music-001` | Music |
| `psychology-001` | Psychology |
| `math-001` | Mathematics |
| `biology-002` | Biology |
| `literature-001` | Literature |
| `anatomy-001` | Anatomy |
| `language-001` | Linguistics |

Pass threshold: **80%** (≥ 16/20 inputs must pass rubric).

**2026-06-09:** Fixture set expanded 3 → 20. Goldens for the 17 new fixtures pending first `--update-goldens` run on AI hardware.

## M2 baseline (original run, 2026-05-21)

> Recorded during M2 implementation. Model: Apple Intelligence on-device (iOS 26 dev).

Pass rate: **[not recorded — M2 session did not log output]**

## M5 run — pending

Status: **Pending first device run.**

Run this on a device with Apple Intelligence enabled after TestFlight distribution or direct device install. Record output below.

```
Date:
Device:
iOS version:
Pass rate: X/3 (XX.X%)
Output:
  [biology-001] …
  [vocab-001] …
  [history-001] …
```

Gate: ≥ 80% required. If regressed, open prompt-iteration ADR.
