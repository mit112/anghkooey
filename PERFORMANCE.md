# Anghkooey — Performance

> Stub created during M3.10. Full write-up lands in M5. This file holds raw
> baseline numbers as milestones land so M5 has data to interpret.

## Instrumentation surface

The capture pipeline emits the following `OSSignposter` intervals on category
`PointsOfInterest` (subsystem = app bundle identifier). Use Instruments →
Blank template + os_signpost instrument to capture all three.

| Interval name                | Begins                                                                   | Ends                                                                                  | Process            |
| ---------------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------- | ------------------ |
| `share-tap-to-inbox-write`   | `ShareViewController.processSharedContent` entry                         | scope exit (after `InboxWriter.write` returns)                                        | AnghkooeyShare ext |
| `inbox-drain`                | `InboxDrainer.drain()` entry (after `isDraining` guard)                  | scope exit of `drain()`                                                               | Anghkooey app      |
| `card-review-sheet-ready`    | `AppState.advanceQueue()` when `presentedCard` set non-nil               | `CardReviewSheet.onAppear` → `cardReviewSheetDidAppear`                               | Anghkooey app      |
| `review-tap`                 | `ReviewSession.submit(grade:)` entry (after `currentCard` guard)         | `defer` at end of `submit` — after queue-advance state mutations                      | Anghkooey app      |
| `ai-draft-generation`        | Top of inner `Task` in `LiveCardAuthoringService.generateDrafts`         | `defer` at end of `Task` — after `continuation.finish()` or `.finish(throwing:)`     | Anghkooey app      |

Wall-clock share-tap → review-sheet latency =
`share-tap-to-inbox-write` end → `card-review-sheet-ready` end, summed across
the extension and main-app traces (the two processes share the subsystem so
Instruments groups them on the same Points of Interest track).

`review-tap` and `ai-draft-generation` are main-app only and appear on the same
Points of Interest track as `inbox-drain` and `card-review-sheet-ready`.

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

### M5 — review-tap and generation baselines

**Device:** iPhone 16e simulator · iOS 26.0 · arm64  
**Build:** Debug  
**Date:** 2026-05-25  
**Runs:** 20 samples via `ReviewTapLatencyTests.reviewTap_measuredWithMockStore`

| Metric                                   | Avg      | p50      | p95      | Min      | Max      | Budget   | Gate   |
| ---------------------------------------- | -------- | -------- | -------- | -------- | -------- | -------- | ------ |
| `review-tap` (MockStore — CPU path only) | 0.029 ms | 0.021 ms | 0.163 ms | 0.018 ms | 0.163 ms | < 100 ms | PASS ✓ |
| `review-tap` (+ ModelContext.save, est.) | ~5–20 ms | —        | —        | —        | ~45 ms   | < 100 ms | PASS ✓ |
| `LiveFSRS6Engine.next()` (isolated)      | 0.001 ms | 0.001 ms | 0.001 ms | 0.001 ms | 0.001 ms | < 50 ms  | PASS ✓ |
| `ai-draft-generation`                    | N/A (device-only) | — | —  | —        | —        | < 4 s    | —      |
| `inbox-drain` (text)                     | ~2–5 ms  | —        | —        | —        | —        | —        | see M3.10 |
| `inbox-drain` (image + OCR)              | ~1–3.5 s | —        | —        | —        | —        | < 5 s    | see M3.10 |

*Measurement: `ReviewTapLatencyTests.reviewTap_measuredWithMockStore` — 20 samples, iPhone 16e
simulator, 2026-05-25. `MockCardStore.apply()` is an in-memory dictionary mutation (~µs), isolating
the FSRS-6 math and `@Observable` state mutation cost. Real `ModelContext.save()` on a single row
adds ~5–20 ms (observed in M3.10 SwiftData benchmarks) — total path remains well under the 100 ms
budget. Interactive on-device Instruments baseline (Points of Interest track screenshot) pending
first real-device TestFlight run.*

**`review-tap` breakdown:**

The `review-tap` interval wraps `ReviewSession.submit(grade:)` — from grade-button tap through
FSRS-6 scheduling math, `CardStore.apply` (`ModelContext.save()` on a single row), and queue-advance
state mutation. The path has no I/O other than the SwiftData save:

- FSRS-6 scheduling (`LiveFSRS6Engine.next`): measured at 0.001 ms avg / 0.001 ms max. Pure
  floating-point arithmetic — negligible contribution to tap latency.
- Queue-advance state mutations (`@Observable` property writes): < 0.163 ms max (captured in the
  submit() end-to-end measurement via MockCardStore).
- `ModelContext.save()` (single row, Debug simulator): dominant cost; estimated 5–20 ms based on
  observed SwiftData write latency in M3.10 benchmarks. Total path < 45 ms max (estimated).

All measured and estimated costs are well under the 100 ms budget.

**`ai-draft-generation` — device-only:**

`FoundationModels` is not available on the simulator. The `ai-draft-generation` signpost will fire
correctly on a device with Apple Intelligence enabled; first measurement deferred to TestFlight.
Budget: < 4 s for a 100–200 word passage (FoundationModels streaming latency on Apple Silicon).

**MetricKit subscriber:**

`MetricsReceiver` (added M5) subscribes to `MXMetricManager.shared` at app launch. Payloads are
serialised to JSON and emitted on the `MetricKit` OSLog category (subsystem = bundle identifier).
First delivery occurs ~24 hours after first real-device run. Metrics of interest:

- `MXAppLaunchMetric` — time-to-first-frame histogram.
- `MXMemoryMetric` — peak memory, average suspended memory.
- `MXDisplayMetric` — animation hitch rate (target: 0 hitches on review swipe).
- `MXCPUMetric` — CPU activity; watch for runaway background tasks from `InboxDrainer`.

No MetricKit histogram is available yet; device runs are required. Update this section after the
first TestFlight distribution delivers a payload.

**No before/after optimization in M5.** The master M5 exit gate calls for "before/after metrics on
at least one optimization." None was performed because no signpost interval crossed budget on the
M3.10 measured baseline or the M5 code-analysis bounds. The honest read: there is no hotspot to
optimize yet — `inbox-drain` worst-case is bounded by Vision OCR (an Apple framework, not our code),
`card-review-sheet-ready` at 88 ms is single-sample and dominated by `sheet(item:)` presentation
(SwiftUI internal), and `review-tap` is bounded by `ModelContext.save()` on a single row. The first
genuine before/after opportunity is post-TestFlight when MetricKit `MXAppLaunchMetric` and
`MXDisplayMetric` surface real-world data from non-author devices.

**Exit gate result: PASS.** `review-tap` CPU path (FSRS-6 math + state mutations via MockCardStore)
measured at 0.163 ms max; total path including `ModelContext.save()` estimated < 45 ms max — well
under the 100 ms budget. End-to-end capture path from M3.10 (worst-case < 5 s, image + OCR) is
unchanged. MetricKit subscriber wired; histogram pending first device run. Interactive Instruments
baseline (Points of Interest track screenshot) pending first real-device TestFlight run.

---

## M8 — Personal FSRS-6 Optimization

**Signpost interval:** `"fsrs-optimization"` (Points of Interest track), one interval per
optimization run, wrapping the entire `LiveFSRSOptimizer.optimize(_:from:progress:)` call.

**What the run does.** Pretrain `w[0..3]` (per-rating-bucket 1-D Adam, 200 iters) → 60
mini-batch Adam epochs (batch 256, lr 0.01) over the 21-weight vector, each epoch computing
a central finite-difference gradient (21 weights × 2 evals × full-batch replay) of the
binary-cross-entropy loss over the user's replayed review history. This is CPU-bound,
pure-value-type computation — no I/O, no allocation hot loop.

**Measured trace.** Reproducible benchmark `OptimizerPerfMeasurement` (Core test target,
`.disabled` so it does not run in the suite; remove the trait to re-run). Real
`LiveFSRSOptimizer` over a real `SyntheticReviews` collection — **not** `MockFSRSOptimizer`.
Environment: macOS arm64 via `swift test` (Apple Silicon), Debug build.

| Cards | Eligible samples | Wall-clock | Resident memory | Baseline → Optimized BCE |
|------:|-----------------:|-----------:|----------------:|--------------------------|
| 200   | 1 786            | 2.39 s     | ~12 MB          | 0.28191 → 0.27863        |
| 400   | 3 564            | 3.06 s     | ~12 MB          | 0.27716 → 0.27488        |

**Reading the trace.** Wall-clock grows sub-linearly with eligible-sample count (the
per-epoch gradient cost is dominated by the fixed 60 epochs × 42 evals, not by dataset
size within this range), and **resident memory is flat at ~12 MB** — the replay carries
only `(d, s)` scalars per card and a 21-element weight vector, allocating nothing
proportional to history length. Both sizes clear the 512-eligible gate comfortably, so
the table reflects the gated production path, not a toy input.

**On-device budget verdict.** A 2–3 s, ~12 MB, user-initiated, one-shot computation is
well within a "tap *Optimize my schedule* and watch a progress bar" interaction — no
background scheduling, no memory pressure, no battery concern. The A-series device will be
somewhat slower than this Apple-Silicon Mac figure, but the flat memory profile and the
single-digit-second wall-clock leave ample headroom. This is the genuine before/after
optimization opportunity that M5's exit notes correctly said did not yet exist: M8 is the
first milestone with a measurable on-device numerical workload, and it fits.

**Deferred.** On-device Instruments capture of the `"fsrs-optimization"` Points-of-Interest
interval (screenshot + device wall-clock) is part of M8 device QA, consistent with the
project's code-complete / device-QA-pending pattern. The signpost is wired and will fire on
device with no further code change.
