# Anghkooey — Performance

> Stub created during M3.10. Full write-up lands in M5. This file holds raw
> baseline numbers as milestones land so M5 has data to interpret.

## Instrumentation surface

The capture pipeline emits the following `OSSignposter` intervals on category
`PointsOfInterest` (subsystem = app bundle identifier). Use the **Instruments
→ Points of Interest** template to capture all three.

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

| Metric                                | Median | p95  | Device | Build | Date |
| ------------------------------------- | ------ | ---- | ------ | ----- | ---- |
| `share-tap-to-inbox-write`            | TBD    | TBD  | TBD    | TBD   | TBD  |
| `inbox-drain` (text item)             | TBD    | TBD  | TBD    | TBD   | TBD  |
| `inbox-drain` (image item + OCR)      | TBD    | TBD  | TBD    | TBD   | TBD  |
| `card-review-sheet-ready`             | TBD    | TBD  | TBD    | TBD   | TBD  |
| **End-to-end share → review sheet**   | TBD    | TBD  | TBD    | TBD   | TBD  |

**Action item (blocks M3 exit gate):** capture these numbers on a physical
iPhone — the simulator can't host a Share Extension via the system share
sheet meaningfully and OCR latency on Apple Silicon Mac differs from a
mobile NPU. Steps:

1. Archive Release on a real device.
2. Open Instruments → Points of Interest template, target the device.
3. Share a tweet (text) and a screenshot (image) from another app.
4. Record at least 10 runs of each; record median + p95 above.
5. Update this table and remove the "TBD" markers before closing M3.

If the device step has to slip past M3 close, file it as M3.10-followup and
mark the M3 exit gate "signpost code shipped, baseline pending device run".
