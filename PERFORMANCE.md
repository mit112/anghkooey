# Anghkooey — Performance

> Stub created during M3.10. Full write-up lands in M5. This file holds raw
> baseline numbers as milestones land so M5 has data to interpret.

## Instrumentation surface

The capture pipeline emits the following `OSSignposter` intervals on category
`PointsOfInterest` (subsystem = app bundle identifier). Use Instruments →
Blank template + os_signpost instrument to capture all three.

| Interval name                | Begins                                                     | Ends                                              | Process            |
| ---------------------------- | ---------------------------------------------------------- | ------------------------------------------------- | ------------------ |
| `share-tap-to-inbox-write`   | `ShareViewController.processSharedContent` entry           | scope exit (after `InboxWriter.write` returns)    | AnghkooeyShare ext |
| `inbox-drain`                | `InboxDrainer.drain()` entry (after `isDraining` guard)    | scope exit of `drain()`                           | Anghkooey app      |
| `card-review-sheet-ready`    | `AppState.advanceQueue()` when `presentedCard` set non-nil | `CardReviewSheet.onAppear` → `cardReviewSheetDidAppear` | Anghkooey app  |

Wall-clock share-tap → review-sheet latency =
`share-tap-to-inbox-write` end → `card-review-sheet-ready` end, summed across
the extension and main-app traces (the two processes share the subsystem so
Instruments groups them on the same Points of Interest track).

## Baselines

### M3.10 — share-tap → review-sheet baseline

**Device:** iPhone 15 · iOS 26.4.2 (23E261) · arm64  
**Build:** Debug (Instruments, Blank + os_signpost)  
**Date:** 2026-05-21  
**Runs:** 12 total (mix of text and image shares from Notes)

| Metric                                | Avg     | Std Dev | Min     | Max      | Exit gate |
| ------------------------------------- | ------- | ------- | ------- | -------- | --------- |
| `share-tap-to-inbox-write`            | 13 ms   | 9 ms    | 3.6 ms  | 26.7 ms  | —         |
| `inbox-drain` (all runs, bimodal)     | 462 ms  | 985 ms  | 1.7 ms  | 3.54 s   | —         |
| `card-review-sheet-ready`             | 88 ms   | —       | 88 ms   | 88 ms    | —         |
| **End-to-end (worst case, image+OCR)**| ~3.7 s  | —       | —       | ~3.7 s   | < 5 s ✓   |

**Exit gate result: PASS.** Worst-case end-to-end (image share + OCR drain +
sheet presentation) ≈ 3.7 s, under the 5 s budget.

### Notes on the M3.10 run

- `inbox-drain` is bimodal: text-only drains complete in ~2–5 ms; image+OCR
  drains take ~1–3.5 s depending on image complexity. The 985 ms std dev
  reflects this split, not flakiness.
- `card-review-sheet-ready` recorded a single sample (88 ms). SwiftUI's
  `sheet(item:)` reuses the presented sheet when the item changes, so
  `onAppear` fires only on the first presentation. Subsequent queue advances
  begin a signpost interval that is never closed; the open intervals are
  harmless orphans. M5 should switch to a dismiss-and-re-present pattern or
  instrument queue advance separately if per-card latency matters.
- Two `fopen` errors appeared during image shares (`errno = 2, No such file
  or directory`). Root cause (identified during M3 exit review): the
  drainer's orphan-eviction cleanup phase was racing the extension's write
  sequence (image → JSON → notify) and deleting freshly-written `.heic`
  files before their matching JSON arrived on disk. Fixed by adding a 60s
  mtime grace window to `evictOrphanImages` (`InboxConstants
  .orphanImageGraceSeconds`); regression test
  `drainPreservesRecentlyWrittenOrphanImages` locks the behavior. Optional:
  re-run the device baseline to confirm 0/N `fopen` errors on rapid image
  shares.

### M4 — review-tap latency note

M4 introduces no new `OSSignposter` intervals. The review interaction path is:

  user tap → `ReviewSession.submit(grade:)` → `LiveFSRS6Engine.next(...)` (pure math, no I/O)
  → `CardStore.apply(...)` → `ModelContext.save()` → UI update

The dominant cost is `ModelContext.save()` on a single-row write. Expected
latency is well under 100 ms median on any supported device. No dedicated
baseline was captured; M5 will add a `review-tap` signpost and include it
in the full Instruments write-up.

### M5 — full perf write-up (planned)

Release build baselines + Instruments screenshots + MetricKit histogram will
land here when M5 closes. This is the section recruiters read.
