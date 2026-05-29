# M8 — Personal FSRS Optimization Implementation Plan (SKELETON)

> **STATUS: SKELETON, NOT EXECUTION-READY.** M8 is gated on accumulated real review history (≥512 eligible samples). This is a task-level plan with contracts, file map, and validation strategy. **Before executing, run a short session to expand each task into bite-sized TDD steps against a real seeded dataset** — the optimizer's numerical behavior must be tuned to data that doesn't exist yet. Do not subagent-execute this skeleton as-is.

> **For agentic workers:** REQUIRED SUB-SKILL when expanded: superpowers:subagent-driven-development. The math-critical optimizer task (T3) runs on **Opus** with **Codex fresh-eyes review**.

**Goal:** On-device personal FSRS-6 parameter optimization — fit the 21 weights to the user's own `ReviewLog` history via gradient descent over the parity-verified forward model, gated and applied globally.

**Architecture:** `OptimizationDataset` reconstructs ordered per-card review sequences from `ReviewLog`. `LiveFSRSOptimizer` runs Adam over binary-cross-entropy loss, computing predicted recall by **replaying state under candidate parameters** through the existing `FSRS6Engine` forward pass, with **finite-difference gradients** (no second math surface). `OptimizedParametersStore` persists one global parameter set, gated at ≥512 eligible samples, resolving optimized-or-default at the scheduling call site. A manual UI triggers the run with `os_signpost` instrumentation feeding `PERFORMANCE.md`.

**Tech Stack:** Swift 6, `FSRS6Engine`/`FSRSParameters` (existing), `ReviewLog` (existing), `os_signpost`, Swift Testing; Python `py-fsrs` (pinned version) for the parity fixture.

**Source spec:** `docs/superpowers/specs/2026-05-28-v2-cloze-fsrs-design.md` (§M8).

**Model routing:**

| Task | Model | Codex role |
|---|---|---|
| ADR-0004 | Opus | reviewer |
| T1 OptimizationDataset (replay sample builder) | Sonnet writes failing tests + skeleton | **Codex primary impl** |
| T2 py-fsrs parity fixture (Python) | Sonnet orchestrates | **Codex primary impl** |
| T3 LiveFSRSOptimizer (loss/gradient/Adam/pretraining) | **Opus** (math-critical) | **Codex fresh-eyes review** |
| T4 OptimizedParametersStore + threshold gate | Sonnet | none |
| T5 scheduling call-site optimized-or-default resolution | Sonnet | reviewer |
| T6 CardStore.optimizationReviewLogs() projection | Sonnet | none |
| T7 OptimizeScheduleView (trigger + progress + before/after) | Sonnet | none |
| T8 PERFORMANCE.md trace + ADR-0004 + exit review | Opus | reviewer |

---

## File Map

**Create — `AnghkooeyCore/Scheduling/Optimization/`:**
- `OptimizationDataset.swift` — value type: per-card ordered `[ReviewSample]` (`elapsedDays`, `rating`, `sameDay: Bool`); eligibility = non-first, non-same-day; per-card sequence cap; `eligibleSampleCount`.
- `FSRSOptimizer.swift` — protocol: `func optimize(_ dataset: OptimizationDataset, from initial: FSRSParameters, progress: @Sendable (Double) -> Void) async -> OptimizationResult`.
- `LiveFSRSOptimizer.swift` — Adam + finite-difference gradients + `w[0..3]` pretraining + BCE clipping + clamping + `os_signpost` interval.
- `MockFSRSOptimizer.swift` — returns a stubbed `OptimizationResult`.
- `OptimizationResult.swift` — `baselineLoss`, `optimizedLoss`, `optimizedParameters: FSRSParameters`, `weightDeltas: [Double]`, `achievedRetention: Double`.
- `OptimizedParametersStore.swift` — persist/load one global `FSRSParameters` (Codable blob via file or a tiny `@Model`); `resolveParameters(eligibleSampleCount:) -> FSRSParameters` (default when `< threshold`); `threshold = 512`.

**Modify:**
- `CardStore.swift` — add `optimizationReviewLogs()` narrow batched projection sorted by `(cardID, reviewedAt)`.
- Scheduling call site (the place that constructs `FSRSParameters` for `FSRS6Engine`) — read from `OptimizedParametersStore.resolveParameters` instead of always `.default`.

**Create — `AnghkooeyUI/Optimization/`:**
- `OptimizeScheduleView.swift` + view-model — trigger, progress bar, before/after summary, "unlocks at N samples" empty state.

**Create — tests + fixtures:**
- `App/AnghkooeyTests/OptimizationDatasetTests.swift`
- `App/AnghkooeyTests/FSRSOptimizerParityTests.swift` (+ fixture JSON under `App/AnghkooeyTests/Fixtures/`)
- `App/AnghkooeyTests/FSRSOptimizerConvergenceTests.swift`
- `App/AnghkooeyTests/OptimizedParametersStoreTests.swift`
- `scripts/generate_fsrs_optimizer_fixture.py` (Codex-authored; pins py-fsrs version)

---

## Tasks (to be expanded into bite-sized TDD steps before execution)

### T1 — OptimizationDataset (replay-based)
Build ordered per-card sequences from `ReviewLog`. **Critical (Codex review #3/#6):** do NOT train on stored `stabilityBefore`/`difficultyBefore` (computed under default `w`); the dataset carries only `(elapsedDays, rating, sameDay)` and state is replayed inside the loss under candidate params. Eligible loss samples = non-first, non-same-day reviews. Cap per-card sequence length to match py-fsrs. Tests: eligibility filtering, same-day exclusion, sequence cap, `eligibleSampleCount`.

### T2 — py-fsrs parity fixture (Codex, Python)
`scripts/generate_fsrs_optimizer_fixture.py`: synth/sample a review-log dataset, run the **pinned** py-fsrs optimizer, emit JSON `{ reviews, baselineLoss, optimizedLoss, optimizedW }`. Document the pinned py-fsrs version in the fixture header and ADR-0004 (note: scheduler is `ts-fsrs v5.4.0`; both FSRS-6/length-21; version skew documented, not assumed away).

### T3 — LiveFSRSOptimizer (Opus; Codex fresh-eyes review)
Loss = BCE(predicted recall vs pass/fail), inputs clipped to `[1e-7, 1-1e-7]`. Predicted recall via `FSRS6Engine` forward replay under candidate params. Central finite-difference gradients with per-parameter epsilon scaling. Adam; clamp params to FSRS-6 ranges each step. Pretrain `w[0..3]` (initial stability) before main descent, replicating py-fsrs semantics. Deterministic (fixed seed, fixed shuffle, fixed epochs). Wrap the run in an `os_signpost` interval. **Escalation trigger:** if T2 parity can't be hit within tolerance with finite differences, escalate to analytic gradients (documented in ADR-0004).

### T4 — OptimizedParametersStore + threshold gate
Persist one global `FSRSParameters`. `resolveParameters(eligibleSampleCount:)` returns `.default` when `< 512`, else the stored optimized set. `FSRSParameters.default` stays immutable. Tests: under-threshold → default; at/above → stored.

### T5 — Scheduling call-site resolution
Route the scheduler's parameter source through `OptimizedParametersStore.resolveParameters`. Regression: existing FSRS parity tests (default params) must stay green — the resolver returns `.default` for all current/empty-history cases.

### T6 — CardStore.optimizationReviewLogs() projection
Narrow, batched fetch projecting only the fields the dataset needs, sorted by `(cardID, reviewedAt)`. Avoids walking full `Card` graphs (slow once Anki import created thousands of logs). Test: ordering + projection correctness.

### T7 — OptimizeScheduleView
Manual "Optimize my schedule" trigger; progress via the optimizer's progress callback; before/after summary from `OptimizationResult`; "unlocks at N samples" when under threshold (N = computed eligible-sample count, not raw log count).

### T8 — PERFORMANCE.md + ADR-0004 + exit review (Opus)
`PERFORMANCE.md`: `os_signpost`/Instruments trace of an optimization run on a realistically-sized seeded collection, with time/CPU-budget commentary. ADR-0004 per spec §M8.7. ARCHITECTURE.md M8 section. foundation.md re-check.

---

## Validation / Exit Gates (M8)
- Build green; optimizer tests pass.
- **py-fsrs parity within tolerance (loss-based, not exact weights)** — built/passing before optimizer math is considered done.
- Convergence-on-synthetic recovers known params within parameter-family tolerance.
- Under-threshold returns `FSRSParameters.default`.
- `PERFORMANCE.md` updated with a real optimization-run trace.
- ADR-0004 merged; ARCHITECTURE.md appended; foundation.md re-check.
- Device QA: seed ≥512-eligible-sample collection → optimize → before/after shown → subsequent scheduling uses optimized params.

---

## Expansion checklist (do this session-of-execution, not now)
1. Confirm py-fsrs latest version + pin it; verify its eligibility/pretraining semantics against its current source (they evolve).
2. Decide finite-difference step sizes per-parameter against the real loss surface (this needs data).
3. Confirm tolerance numbers for parity + convergence empirically.
4. Bind T5 to the exact current scheduling call site (find via `grep -rn "FSRSParameters.default\|FSRS6Engine(" Packages App`).
5. Expand T1–T8 into bite-sized failing-test → impl → commit steps per writing-plans.
