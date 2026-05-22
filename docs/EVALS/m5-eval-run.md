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

3 fixtures in `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Fixtures/eval-fixtures.json`:

| ID | Passage (truncated) | Domain |
|---|---|---|
| `biology-001` | Mitosis is the process by which a single cell divides… | Biology |
| `vocab-001` | Ephemeral means lasting for a very short time… | Vocabulary |
| `history-001` | The Treaty of Versailles was signed in 1919… | History |

Pass threshold: **80%** (≥ 3/3 inputs must pass rubric).

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
