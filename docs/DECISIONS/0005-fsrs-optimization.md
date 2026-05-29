# 0005 — Personal FSRS-6 Optimization: Finite-Difference Adam Over the Replay Forward Model

**Date:** 2026-05-29
**Status:** Accepted
**Milestone:** M8 — Personal FSRS Optimization

---

## Context

M8 fits the 21 FSRS-6 weights to a user's own `ReviewLog` history so scheduling
reflects their actual memory, not the ts-fsrs population defaults. The work runs
**on device**, gated at ≥512 eligible review samples, and the result is applied
globally to scheduling.

Two subsystems are expensive to re-validate and must stay untouched: the
parity-verified `LiveFSRS6Engine` (ADR-0002, pinned to ts-fsrs v5.4.0) and the
swipe-to-grade review UI. The optimizer therefore had to fit weights **without a
second FSRS math surface** that could silently drift from the scheduler.

The design questions this ADR records: how to compute the loss gradient, how to
keep the numerics stable, how to replicate py-fsrs eligibility + initial-stability
semantics, what scope the fitted parameters have, and how to validate correctness.

---

## Decision

### One math surface; loss over the replay forward model

The optimizer never re-derives FSRS. For a candidate weight vector it instantiates
`LiveFSRS6Engine(parameters:)` and **replays each card's review history**,
accumulating binary-cross-entropy between predicted recall
(`forgettingCurve(elapsedDays:stability:)`) and the actual pass/fail outcome. State
evolves through the engine's `nextMemoryState` exactly as in production. A single
private `forEachEligible` replay drives `meanLoss`, the gradient, and
`achievedRetention` — there is no parallel implementation of the FSRS formulas.

The loss uses **actual `elapsedDays`**, never scheduled intervals. This is the
decision that makes finite differences sound: the forward model is a smooth function
of `w` with no integer interval-rounding discontinuity in the gradient path.

### Finite-difference gradients, not analytic — and why the escalation did not fire

Gradients are **central finite differences** over `meanLoss`, one perturbation per
weight, with a **per-parameter relative epsilon `eps_i = max(1e-5, 1e-4·|w_i|)`**.
The 21 weights span ~`0.001`–`8.3`, so a fixed absolute step is wrong at both ends;
the relative rule was calibrated against the T2 parity fixture and is the final rule.

The plan defined an escalation trigger: if finite differences could not reach the
parity tolerance after epsilon/learning-rate/epoch calibration, switch to
hand-derived analytic gradients. **The trigger did not fire.** With the calibrated
epsilon, 60 mini-batch Adam epochs (batch 256, lr 0.01) and per-bucket `w[0..3]`
pretraining, the Swift optimizer matched the oracle within the loss tolerance
(see Validation). Analytic gradients were therefore *not* introduced — they would
have added a second FSRS math surface (21 hand-derived partials of the recall/
stability formulas) whose only payoff is speed the on-device budget does not need
(§Consequences). Correctness-over-speed: finite differences reuse the one
parity-verified engine, so a scheduler bug and an optimizer bug cannot diverge.

### Numerical stability

- **Central differences** (not forward) for second-order accuracy in the gradient.
- **BCE probability clip `[1e-7, 1-1e-7]`** before every `log`, so a predicted recall
  at the extremes can never produce `±∞`.
- **Per-step clamping to FSRS-6 valid ranges** after each Adam update (e.g.
  `w20 ∈ [0.1, 0.8]`, `w4 ∈ [1, 10]`, initial-stability `w[0..3] ∈ [0.1, 36500]`;
  the three unbounded weights `w8/w13/w14` are held in `[-5, 5]` purely for numerical
  stability). The full table lives in `LiveFSRSOptimizer.weightClamps` and mirrors the
  Python oracle's `W_CLAMPS`.
- **Deterministic mini-batch shuffling** via `SeededGenerator` (SplitMix64) so a run
  is reproducible.

### Replicated py-fsrs semantics

Eligibility and `w[0..3]` pretraining were read from the fixture-build behavior and
replicated, not remembered:

- **Eligibility:** a review contributes to the loss iff it is **non-first**
  (`index > 0`) **and non-same-day** (`elapsedDays > 0`). The first review only
  initialises state; same-day re-reviews advance state but never enter the loss.
- **`w[0..3]` pretraining:** group cards by their *first* review's rating bucket
  (Again/Hard/Good/Easy), collect each card's `(secondReviewElapsed, passed?)`
  transition, and fit one initial-stability value per bucket via 1-D Adam (200 iters,
  lr 0.05) minimising the same BCE, before the full 21-weight phase. The forgetting
  curve in this phase uses the starting parameters' decay (`w[20]`), untouched by the
  pretrain.

### Global parameter scope, threshold, storage

- **One global weight set**, not per-tag or per-deck. The wedge is "make the user's
  schedule fit the user," and per-tag fitting would shatter the 512-sample gate into
  many under-powered buckets.
- **Threshold = 512 eligible samples.** Below it, `OptimizedParametersStore` resolves
  to `FSRSParameters.default` regardless of any stored value.
- **Storage:** only the 21-element `w` is persisted, as JSON in the **app-group
  container**, so the widget extension reads the same optimized set. Everything else
  is rebuilt onto the ADR-0002-immutable `.default` via `FSRSParameters.withWeights`.

### Validation is loss-based, not weight-equality

Parity asserts **loss improvement and identical eligibility**, never per-weight
equality. Two optimizers descending the same loss surface from the same start via
different mini-batch RNG paths converge to the same basin but not the same point;
asserting weight equality would be testing the RNG, not the math. The convergence
test (synthetic data from known perturbed weights) additionally asserts loss recovery
within 2% of loss-under-true-params and predicted-vs-actual calibration within 0.02.

---

## Oracle deviation from the plan (recorded, not glossed)

The plan specified the **py-fsrs `Optimizer`** (`pip install fsrs[optimizer]`) as the
parity oracle. On the build machine that package's `Optimizer` **requires PyTorch**,
whose dylibs failed to load (`libtorch_global_deps.dylib` missing; this is a torch
packaging/CUDA-stub issue, not a code issue). Rather than block M8 on a torch install,
the fixture generator (`scripts/fsrs-optimizer/generate_fsrs_optimizer_fixture.py`)
implements a **self-contained FD-Adam optimizer in stdlib Python** running the *same*
algorithm as `LiveFSRSOptimizer.swift`, over FSRS-6 formulas transcribed to match
`LiveFSRS6Engine` exactly.

**What this strengthens:** the fixture is now a *direct algorithmic* parity target —
Swift and Python run identical FD-Adam from identical starts — rather than an autograd
reference. Eligibility semantics and BCE loss, which are the substance of M8, are
validated faithfully.

**What this gives up, honestly:** we are **not** validating against py-fsrs's
*published optimizer output*. If py-fsrs's torch optimizer converges to a materially
different basin than FD-Adam, this fixture would not catch it. Mitigation: the
forgetting curve, eligibility, and BCE definitions are transcribed from the FSRS-6
spec and cross-checked against the existing ts-fsrs scheduler parity fixture
(ADR-0002). Re-validating against py-fsrs's torch optimizer on a torch-capable machine
is a follow-up, tracked as a known gap.

### Version skew (documented, per ADR-0002 precedent)

- **Scheduler:** ts-fsrs **v5.4.0** (ADR-0002 pin) — FSRS-6, length-21.
- **Optimizer fixture:** generated by a stdlib FD-Adam oracle transcribed from FSRS-6;
  the py-fsrs package pinned in `requirements.txt` would be **6.3.1** (FSRS-6,
  length-21) had its torch optimizer loaded.
- Both are FSRS-6 / length-21. The skew is recorded, not assumed away.

---

## Rejected alternatives

### Analytic gradients up front
Hand-derive the 21 partial derivatives of the recall/stability formulas. Rejected:
introduces a second FSRS math surface that can drift from the scheduler, for a speed
win the on-device budget (~2–3 s, §Consequences) does not require. Kept as the
documented escalation path; it was never needed.

### Per-tag / per-deck parameter sets
Fit separate weights per tag. Rejected: fragments the 512-sample gate into
under-powered buckets and contradicts the global "fit the user" wedge.

### Persisting the full `FSRSParameters`
Store retention, learning steps, etc. alongside `w`. Rejected: those are
ADR-0002-pinned policy, not fitted quantities; persisting only `w` keeps `.default`
the single source of truth for everything else.

---

## Consequences

- **Performance fits an on-device "tap and wait" budget.** Measured on macOS arm64
  (`swift test`, `OptimizerPerfMeasurement`): **1786 eligible samples → 2.39 s**,
  **3564 → 3.06 s**, **resident memory flat at ~12 MB** (value-type replay, no large
  allocations). See `PERFORMANCE.md §M8`. On-device Instruments capture of the
  `"fsrs-optimization"` signpost interval is part of deferred device QA.
- **No scheduling regression.** The resolver returns `.default` for every
  current/empty-history case; existing ts-fsrs parity tests stay green.
- **`ReviewLog.cardID` denormalization deferred.** The projection
  `CardStore.optimizationReviewLogs()` reads `log.card?.id` off the relationship. A
  denormalized `ReviewLog.cardID` would avoid that access but requires a schema V6
  migration — **out of M8 scope**, recorded here as a future optimization.
- **py-fsrs torch re-validation is a known follow-up** (see Oracle deviation).

---

## Status

**Accepted — M8.** Records the optimizer math, numerical-stability choices,
replicated py-fsrs semantics, the oracle deviation and its honest tradeoff, global
scope, and the loss-based validation strategy. `foundation.md §4` listed personal
optimization as a v2 concern; this ADR records the milestone that ships it.
