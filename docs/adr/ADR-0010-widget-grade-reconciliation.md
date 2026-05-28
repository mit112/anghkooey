# ADR-0010 — Widget Grade Reconciliation

**Date:** 2026-05-28  
**Status:** Accepted  
**Lanes:** W (WidgetKit Interactive Review Widget)

---

## Context

The interactive review widget must record grade decisions (Again / Good) without
opening the app. Tapping a button in the widget runs a `GradeCardIntent` that
writes to the App Group; the main app reconciles on its next foreground activation.

Two design constraints shaped this:
1. **No cross-process SwiftData.** SwiftData `ModelContainer` is not safe to open
   from a widget extension process alongside the app process. The widget must
   never touch the database directly.
2. **Idempotent replay.** The widget may append the same grade more than once
   (e.g. if the user double-taps before the timeline reloads). Replay must be
   safe to run on any set of queued decisions.

---

## Decision

### Two-file App Group contract

| File | Writer | Reader | Format |
|------|--------|--------|--------|
| `widget/due-snapshot.json` | App (on foreground / after review) | Widget `TimelineProvider` | JSON — `WidgetDueSnapshot` |
| `widget/grades.jsonl` | Widget `GradeCardIntent` | App `WidgetGradeReconciler` | Newline-delimited JSON — `WidgetGradeDecision` |

`WidgetBridge` (in `AnghkooeyCore`) encapsulates all reads/writes to both files
and is the only code that touches the App Group file paths.

### Idempotency mechanism

Each `WidgetGradeDecision` carries a stable `id: UUID` generated at intent fire
time. `WidgetGradeReconciler` maintains an in-memory `Set<UUID> appliedIDs`.
On each reconcile pass:
1. Read all decisions from `grades.jsonl`.
2. Sort by `decidedAt` (preserves review order).
3. Skip any `id` already in `appliedIDs`.
4. Apply remaining decisions through `store.apply(...)` using `decidedAt` as the
   review timestamp (preserving the actual grade time, not the drain time).
5. Clear `grades.jsonl`.
6. Rewrite `due-snapshot.json` from the current due queue.

### Known limitation: cross-relaunch crash window

`appliedIDs` is in-memory only. If the app crashes between step 4 (`store.apply`)
and step 5 (`clearGrades`), the queue file survives. On next launch, `appliedIDs`
is empty, so those decisions would be replayed a second time.

**Accepted because:** the FSRS-6 effect of one spurious duplicate "Good" is a
slightly longer next interval — self-correcting within a review cycle. The
engineering cost of a persistent applied-set (requiring another App Group file
and atomic swap) is not justified for v1.1. Revisit if device QA reveals actual
double-scheduling complaints.

---

## Consequences

- The widget is stateless with respect to FSRS: it shows what the app wrote and
  queues what the user tapped; all scheduling math stays in the app process.
- Adding a new grade button (e.g. "Easy") requires only: a new `Rating` case raw
  value in `GradeCardIntent`, a new `Button(intent:)` in the widget view, and no
  changes to `WidgetBridge` or `WidgetGradeReconciler`.
- The 15-minute timeline refresh policy means the widget may show a stale card
  for up to 15 minutes after the app drains grades. Acceptable for v1.1.
