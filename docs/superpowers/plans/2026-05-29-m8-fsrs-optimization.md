# M8 — Personal FSRS Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Expanded from** `docs/superpowers/plans/2026-05-28-m8-fsrs-optimization-skeleton.md` on 2026-05-29. The skeleton is retained for history; **this file supersedes it** as the execution-ready plan.

**Goal:** On-device personal FSRS-6 parameter optimization — fit the 21 weights to the user's own `ReviewLog` history via Adam + finite-difference gradient descent over the parity-verified `LiveFSRS6Engine` forward model, gated at ≥512 eligible samples and applied globally to scheduling.

**Architecture:** `OptimizationDataset` reconstructs ordered per-card review sequences from a narrow `ReviewLog` projection, carrying only `(elapsedDays, rating, sameDay)` per review — **never** the logged `stabilityBefore`/`difficultyBefore` (those were computed under default `w` and are wrong for a candidate `w`). `LiveFSRSOptimizer` runs Adam over binary-cross-entropy loss, computing predicted recall by **replaying memory state under candidate parameters** through the existing `LiveFSRS6Engine` primitives (`nextMemoryState`, `forgettingCurve`) — no second math surface — with central finite-difference gradients. `OptimizedParametersStore` persists one global optimized weight set in the app-group container (so the widget reads it too), resolving optimized-or-default at the scheduling call site. A manual UI triggers the run wrapped in an `os_signpost` interval feeding `PERFORMANCE.md`.

**Tech Stack:** Swift 6, `LiveFSRS6Engine`/`FSRSParameters`/`ReviewLog` (existing AnghkooeyCore), `OSSignposter` (`CoreLog.poiSignposter`), Swift Testing; Python `fsrs` (py-fsrs, pinned at fixture-build time) for the parity fixture.

**Source spec:** `docs/superpowers/specs/2026-05-28-v2-cloze-fsrs-design.md` (§M8).

> ⚠️ **ADR number is `ADR-0005`, not `0004`.** `docs/DECISIONS/0004-cloze-data-model.md` already exists (M7). The skeleton incorrectly said "ADR-0004" throughout — every reference in this plan is corrected to **`docs/DECISIONS/0005-fsrs-optimization.md`**.

---

## Expansion checklist results (run 2026-05-29)

These are the answers to the skeleton's §Expansion checklist. Read before executing.

**1. py-fsrs version + pin + semantics.**
- Use the **`fsrs`** PyPI package (open-spaced-repetition/py-fsrs), which ships the integrated `Optimizer` class with `compute_optimal_parameters()` for FSRS-6 (21 weights, `w20 ∈ [0.1, 0.8]`). This is *not* the older separate `FSRS-Optimizer`/`fsrs-optimizer` package — do not use that one.
- **Do not hard-code a version number blindly** (silent-fallback risk, cf. `reference_codex_models`). In **T2**, the executor runs `pip index versions fsrs`, picks the latest stable **FSRS-6 / 21-parameter** release (must be ≥ a release whose `default_parameters` has length 21), pins it **exactly** in `scripts/fsrs-optimizer/requirements.txt` (e.g. `fsrs==X.Y.Z`), and echoes the resolved version into both the fixture JSON header (`meta.pyfsrs_version`) and ADR-0005. Note in ADR-0005: scheduler is pinned to `ts-fsrs v5.4.0`; optimizer fixture uses py-fsrs `X.Y.Z`; both are FSRS-6 / length-21; **version skew is documented, not assumed away** (ADR-0002 precedent).
- **Eligibility + pretraining semantics must be read from the pinned py-fsrs source at fixture-build time** (they evolve across releases). T2 records the exact observed semantics (which reviews are filtered from loss; how `w[0..3]` initial-stability pretraining is performed) in a comment block at the top of `generate_fsrs_optimizer_fixture.py` and in ADR-0005. The Swift optimizer (T3) replicates *that recorded behavior*, not a remembered version of it.

**2. Finite-difference step sizes.** Provisional: central differences with per-parameter **relative** epsilon `eps_i = max(1e-5, 1e-4 * |w_i|)` (the 21 weights span ~`0.001`–`8.3`, so a fixed absolute epsilon is wrong). **These are starting values to calibrate against the real loss surface in T3** once the T2 fixture exists. T3's parity step calibrates and records the final epsilon rule in ADR-0005.

**3. Parity + convergence tolerances.** Cannot be set blind — they depend on the generated fixture. The TDD tasks below are structured so the **fixture is generated first**, the executor **reads the observed numbers**, and *then* writes the assertion with `observed ± tolerance`. Provisional tolerances (refine in T2/T3):
   - Parity: eligible-sample count matches py-fsrs **exactly**; Swift `optimizedLoss ≤ baselineLoss`; `|swiftOptimizedLoss − pyfsrsOptimizedLoss| ≤ 0.01` absolute BCE **or** ≤ 5% relative, whichever is looser.
   - Convergence: do **not** assert per-weight equality. Assert (a) `optimizedLoss` within 2% of loss-under-true-params, and (b) mean predicted recall ≈ mean actual pass-rate within `0.02` (calibration).

**4. T5 call sites — bound exactly (verified 2026-05-29).** Two production default-init sites of `LiveFSRS6Engine()`:
   - `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewScreen.swift:16` (default arg) — **constructed at** `App/Anghkooey/ContentView.swift:17` `ReviewScreen(store: appState.cardStore)`.
   - `App/Anghkooey/WidgetGradeReconciler.swift:26` (default arg) — **constructed at** `App/Anghkooey/AppState.swift:89`.
   - Default args cannot be `async`, so resolution happens in `AppState` (which owns `cardStore` and can `await`). T5 injects a resolved engine at both construction sites. `grep -rn "LiveFSRS6Engine()" Packages App | grep -v Tests` confirmed these are the only two non-test default-init sites.

**5. T1–T8 expanded into bite-sized failing-test → impl → commit steps below.**

---

## Model routing

| Task | Model | Codex role |
|---|---|---|
| T0 Scaffolding (value types, protocol, mock) | Sonnet | none |
| T1 `OptimizationDataset` (replay sample builder) | Sonnet authors failing tests + skeleton | **Codex primary impl** (contract-first) |
| T2 py-fsrs parity fixture (Python) | Sonnet orchestrates | **Codex primary impl** |
| T3 `LiveFSRSOptimizer` (loss/gradient/Adam/pretraining) | **Opus** (math-critical) | **Codex fresh-eyes review** |
| T4 `OptimizedParametersStore` + threshold gate | Sonnet | none |
| T5 scheduling call-site optimized-or-default resolution | Sonnet | **Codex reviewer** |
| T6 `CardStore.optimizationReviewLogs()` projection | Sonnet | none |
| T7 `OptimizeScheduleView` (trigger + progress + before/after) | Sonnet | none |
| T8 `PERFORMANCE.md` trace + ADR-0005 + exit review | **Opus** | reviewer |

Codex sandbox cannot run `swift build`/`xcodebuild` (`feedback_codex_sandbox`): Codex writes diffs/tests, Claude verifies locally. Codex-as-reviewer can stall on remote API — use a ~10-min timeout with fallback to `ecc:code-reviewer` (`feedback_codex_reviewer_latency`). For T3, the parent Opus session writes the math; Codex does a **fresh-eyes review** of the gradient/pretraining/clipping logic afterward.

**Dependency order:** T0 → T1 → T2 → T3 → T4 → T6 → T5 → T7 → T8. (T6 feeds T5's resolution and T3's real-data smoke; T2 must precede T3's parity test.)

---

## Verification setup (read once)

All Core tests run via the package test target. Per memory (`feedback_xcodebuild_codesign_resource_fork`, `feedback_xcodebuild_needs_project_flag`, `feedback_ios26_sim_name`):

```bash
# AnghkooeyCore unit tests (T0,T1,T3,T4,T6) — package builds standalone (feedback_swift_test_package_limitations)
cd Packages/AnghkooeyCore && swift test 2>&1 | tail -30

# App-target tests (anything touching @Model containers / AppState / UI) — via xcodebuild:
xcodebuild test \
  -project App/Anghkooey.xcodeproj \
  -scheme Anghkooey \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/anghkooey-derived-data \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_STYLE=Manual \
  2>&1 | tail -40
```

Ignore SourceKit "Cannot find type" diagnostics on freshly-written files when the build/test passes (`feedback_sourcekit_stale_in_harness`). Use `python3` for any in-place pbxproj/file edits — `sed -i` is aliased to `sd` and corrupts pbxproj (`feedback_sed_aliased_to_sd`).

New Core source files land under `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/Optimization/` and need **no** pbxproj registration (SPM globs sources). New **app-target** test files and the UI view *do* need target wiring — follow `feedback_app_test_target_wiring` and `xcode-16-synchronized-folders-no-pbxproj-edit`.

---

## File Map

**Create — `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/Optimization/`:**
- `ReviewSample.swift` — value type: `(elapsedDays: Double, rating: Rating, sameDay: Bool)`.
- `OptimizationReviewLogRow.swift` — value type: `(cardID: UUID, reviewedAt: Date, rating: Rating, elapsedDays: Double)` — the narrow projection row produced by T6.
- `OptimizationDataset.swift` — builds ordered per-card `[ReviewSample]` from rows; eligibility (non-first, non-same-day); per-card sequence cap; `eligibleSampleCount`.
- `OptimizationResult.swift` — `baselineLoss`, `optimizedLoss`, `optimizedParameters: FSRSParameters`, `weightDeltas: [Double]`, `achievedRetention: Double`.
- `FSRSOptimizer.swift` — protocol.
- `MockFSRSOptimizer.swift` — returns a stubbed `OptimizationResult`.
- `LiveFSRSOptimizer.swift` — Adam + finite-difference gradients + `w[0..3]` pretraining + BCE clipping + clamping + `os_signpost` interval (T3, Opus).
- `OptimizedParametersStore.swift` — persist/load one global `FSRSParameters` (Codable JSON in app-group container); `resolveParameters(eligibleSampleCount:) -> FSRSParameters`; `threshold = 512`.
- `SeededGenerator.swift` — deterministic SplitMix64 `RandomNumberGenerator` for reproducible mini-batch shuffles.

**Modify:**
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/FSRSParameters.swift` — add `func withWeights(_ w: [Double]) -> FSRSParameters` (T4).
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardStore.swift` — add `optimizationReviewLogs()` to protocol + actor + mock (T6).
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Logging/CoreLog.swift` — document the new `"fsrs-optimization"` signpost interval name (T3).
- `App/Anghkooey/AppState.swift` — own `scheduler` + `refreshScheduler()` resolution; rebuild `widgetReconciler` with resolved engine (T5).
- `App/Anghkooey/ContentView.swift:17` — pass `scheduler: appState.scheduler` to `ReviewScreen` (T5).

**Create — `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Optimization/`:**
- `OptimizeScheduleView.swift` + `OptimizeScheduleViewModel` — trigger, progress bar, before/after summary, "unlocks at N samples" empty state (T7).

**Create — tests + fixtures:**
- `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/OptimizationDatasetTests.swift` (T1)
- `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/FSRSOptimizerParityTests.swift` (T3)
- `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/FSRSOptimizerConvergenceTests.swift` (T3)
- `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/OptimizedParametersStoreTests.swift` (T4)
- `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/Fixtures/fsrs-optimizer-parity.json` (T2, Codex-generated)
- `App/AnghkooeyTests/CardStoreOptimizationLogsTests.swift` (T6)
- `scripts/fsrs-optimizer/generate_fsrs_optimizer_fixture.py` + `requirements.txt` (T2, Codex-authored)

**Create — `docs/DECISIONS/0005-fsrs-optimization.md`** (T8, Opus).

---

## Task T0 — Scaffolding: value types, protocol, mock

**Files:**
- Create: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/Optimization/ReviewSample.swift`
- Create: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/Optimization/OptimizationReviewLogRow.swift`
- Create: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/Optimization/OptimizationResult.swift`
- Create: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/Optimization/FSRSOptimizer.swift`
- Create: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/Optimization/MockFSRSOptimizer.swift`
- Create: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/Optimization/SeededGenerator.swift`

- [ ] **Step 1: Create the value types**

`ReviewSample.swift`:
```swift
import Foundation

/// One review in a card's replayed history, decoupled from `ReviewLog`.
///
/// Carries ONLY the inputs the optimizer needs. It deliberately does NOT carry
/// `stabilityBefore`/`difficultyBefore`: those were computed under the default
/// `w` and are wrong for any candidate `w`. State is replayed inside the loss.
public struct ReviewSample: Equatable, Sendable {
    /// UTC calendar-day diff from the prior review (0 on the first review and
    /// on same-day reviews). Matches `ReviewLog.elapsedDays`.
    public let elapsedDays: Double
    /// The grade the user gave.
    public let rating: Rating
    /// True when this review fell on the same UTC day as the prior one
    /// (`elapsedDays == 0` for a non-first review). Same-day reviews update
    /// state but never contribute to the loss (py-fsrs semantics).
    public let sameDay: Bool

    public init(elapsedDays: Double, rating: Rating, sameDay: Bool) {
        self.elapsedDays = elapsedDays
        self.rating = rating
        self.sameDay = sameDay
    }
}
```

`OptimizationReviewLogRow.swift`:
```swift
import Foundation

/// Narrow value-type projection of one `ReviewLog`, produced by
/// `CardStoreProtocol.optimizationReviewLogs()`. Carries only the four fields
/// the dataset needs so the fetch never walks full `Card` graphs (Codex #10).
public struct OptimizationReviewLogRow: Equatable, Sendable {
    public let cardID: UUID
    public let reviewedAt: Date
    public let rating: Rating
    public let elapsedDays: Double

    public init(cardID: UUID, reviewedAt: Date, rating: Rating, elapsedDays: Double) {
        self.cardID = cardID
        self.reviewedAt = reviewedAt
        self.rating = rating
        self.elapsedDays = elapsedDays
    }
}
```

`OptimizationResult.swift`:
```swift
import Foundation

/// Outcome of one optimization run. Surfaced to the UI as the before/after summary.
public struct OptimizationResult: Equatable, Sendable {
    /// Mean BCE loss over eligible samples under `FSRSParameters.default`.
    public let baselineLoss: Double
    /// Mean BCE loss over eligible samples under `optimizedParameters`.
    public let optimizedLoss: Double
    /// The fitted parameter set (default with optimized `w`).
    public let optimizedParameters: FSRSParameters
    /// Per-weight delta `optimized.w[i] - initial.w[i]` (length 21).
    public let weightDeltas: [Double]
    /// Mean predicted recall over eligible samples under `optimizedParameters`
    /// (the model's achieved retention on the user's own history).
    public let achievedRetention: Double

    public init(
        baselineLoss: Double,
        optimizedLoss: Double,
        optimizedParameters: FSRSParameters,
        weightDeltas: [Double],
        achievedRetention: Double
    ) {
        self.baselineLoss = baselineLoss
        self.optimizedLoss = optimizedLoss
        self.optimizedParameters = optimizedParameters
        self.weightDeltas = weightDeltas
        self.achievedRetention = achievedRetention
    }
}
```

`FSRSOptimizer.swift`:
```swift
import Foundation

/// Contract for fitting a personal FSRS-6 weight set to a user's review history.
public protocol FSRSOptimizer: Sendable {
    /// Fit `initial.w` to `dataset`. `progress` is called with values in `0...1`.
    /// Returns the baseline/optimized losses and the fitted parameters.
    func optimize(
        _ dataset: OptimizationDataset,
        from initial: FSRSParameters,
        progress: @Sendable (Double) -> Void
    ) async -> OptimizationResult
}
```

`MockFSRSOptimizer.swift`:
```swift
import Foundation

/// Deterministic stub for UI/integration tests. Reports a fixed improvement
/// and emits a few progress ticks.
public struct MockFSRSOptimizer: FSRSOptimizer {
    public var result: OptimizationResult

    public init(result: OptimizationResult? = nil) {
        self.result = result ?? OptimizationResult(
            baselineLoss: 0.50,
            optimizedLoss: 0.42,
            optimizedParameters: .default,
            weightDeltas: Array(repeating: 0, count: 21),
            achievedRetention: 0.9
        )
    }

    public func optimize(
        _ dataset: OptimizationDataset,
        from initial: FSRSParameters,
        progress: @Sendable (Double) -> Void
    ) async -> OptimizationResult {
        for tick in 1...4 { progress(Double(tick) / 4.0) }
        return result
    }
}
```

`SeededGenerator.swift`:
```swift
import Foundation

/// Deterministic SplitMix64 RNG so mini-batch shuffles are reproducible across
/// runs (required for a stable parity harness). Not cryptographic.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { self.state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd Packages/AnghkooeyCore && swift build 2>&1 | tail -10`
Expected: `Build complete!` (note: `OptimizationDataset` is referenced by the protocol/mock but does not exist yet — **define an empty placeholder** to compile, then T1 fills it).

Add a placeholder `OptimizationDataset.swift`:
```swift
import Foundation

/// Replay-based training dataset. **Placeholder — filled in T1.**
public struct OptimizationDataset: Sendable, Equatable {
    public let cardSequences: [[ReviewSample]]
    public init(cardSequences: [[ReviewSample]] = []) { self.cardSequences = cardSequences }
    public var eligibleSampleCount: Int { 0 }
}
```

Re-run `swift build` → `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/Optimization/
git commit -m "feat(m8): optimization value types, FSRSOptimizer protocol + mock"
```

---

## Task T1 — OptimizationDataset (replay sample builder)

> **Codex primary impl, contract-first.** Sonnet writes the failing tests + the type signature; Codex makes them pass. Per `project_collaboration_workflow`.

**Files:**
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/Optimization/OptimizationDataset.swift`
- Test: `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/OptimizationDatasetTests.swift`

**Contract (Sonnet writes this signature first):**
```swift
public struct OptimizationDataset: Sendable, Equatable {
    /// Per-card ordered review sequences. Index 0 in each is the first review.
    public let cardSequences: [[ReviewSample]]

    /// Maximum reviews kept per card. Confirm the exact py-fsrs default in T2;
    /// provisional value below. Sequences longer than this keep the LAST N.
    public static let maxSequenceLength = 200  // TODO(T2): confirm vs pinned py-fsrs source

    /// Build from a flat projection. Rows are grouped by `cardID`, each group
    /// sorted by `reviewedAt`, then capped to `maxSequenceLength` (keep most
    /// recent). `sameDay = (elapsedDays == 0)`.
    public init(rows: [OptimizationReviewLogRow])

    /// Count of samples that contribute to the loss: non-first (index > 0)
    /// AND non-same-day (`!sameDay`).
    public var eligibleSampleCount: Int
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import AnghkooeyCore

@Suite("OptimizationDataset")
struct OptimizationDatasetTests {
    private func row(_ card: UUID, _ day: Int, _ rating: Rating, elapsed: Double) -> OptimizationReviewLogRow {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return OptimizationReviewLogRow(
            cardID: card,
            reviewedAt: base.addingTimeInterval(Double(day) * 86_400),
            rating: rating,
            elapsedDays: elapsed
        )
    }

    @Test("groups rows by card and orders by reviewedAt")
    func grouping() {
        let a = UUID(), b = UUID()
        let rows = [
            row(a, 2, .good, elapsed: 2),
            row(b, 0, .again, elapsed: 0),
            row(a, 0, .good, elapsed: 0),   // out of order on purpose
        ]
        let ds = OptimizationDataset(rows: rows)
        #expect(ds.cardSequences.count == 2)
        // Card a: two reviews, ordered day0 then day2
        let seqA = ds.cardSequences.first { $0.count == 2 }!
        #expect(seqA[0].elapsedDays == 0)
        #expect(seqA[1].elapsedDays == 2)
    }

    @Test("eligible = non-first AND non-same-day")
    func eligibility() {
        let c = UUID()
        // first(day0,e0) | same-day(day0,e0) | real(day3,e3) | real(day10,e7)
        let rows = [
            row(c, 0, .good, elapsed: 0),
            row(c, 0, .hard, elapsed: 0),   // same-day → excluded
            row(c, 3, .good, elapsed: 3),   // eligible
            row(c, 10, .good, elapsed: 7),  // eligible
        ]
        let ds = OptimizationDataset(rows: rows)
        #expect(ds.eligibleSampleCount == 2)
    }

    @Test("first review is never eligible even if elapsed > 0")
    func firstNeverEligible() {
        let c = UUID()
        let rows = [row(c, 5, .good, elapsed: 5)] // single first review
        let ds = OptimizationDataset(rows: rows)
        #expect(ds.eligibleSampleCount == 0)
    }

    @Test("sequence longer than cap keeps the most recent N")
    func cap() {
        let c = UUID()
        let n = OptimizationDataset.maxSequenceLength
        var rows: [OptimizationReviewLogRow] = []
        for day in 0...(n + 50) { rows.append(row(c, day, .good, elapsed: day == 0 ? 0 : 1)) }
        let ds = OptimizationDataset(rows: rows)
        #expect(ds.cardSequences[0].count == n)
    }

    @Test("sameDay flag set iff elapsedDays == 0")
    func sameDayFlag() {
        let c = UUID()
        let rows = [row(c, 0, .good, elapsed: 0), row(c, 1, .good, elapsed: 1)]
        let ds = OptimizationDataset(rows: rows)
        #expect(ds.cardSequences[0][0].sameDay == true)
        #expect(ds.cardSequences[0][1].sameDay == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/AnghkooeyCore && swift test --filter OptimizationDataset 2>&1 | tail -20`
Expected: FAIL — placeholder `init(cardSequences:)` doesn't match `init(rows:)`; `eligibleSampleCount` returns 0.

- [ ] **Step 3: Codex implements `init(rows:)` + `eligibleSampleCount`**

Hand the contract + failing tests to Codex (`codex:rescue` or contract-first dispatch). Reference implementation Codex should produce:
```swift
public init(rows: [OptimizationReviewLogRow]) {
    let grouped = Dictionary(grouping: rows, by: \.cardID)
    self.cardSequences = grouped.values.map { group in
        let ordered = group.sorted { $0.reviewedAt < $1.reviewedAt }
        let capped = ordered.suffix(Self.maxSequenceLength)
        return capped.map {
            ReviewSample(elapsedDays: $0.elapsedDays, rating: $0.rating, sameDay: $0.elapsedDays == 0)
        }
    }
}

public var eligibleSampleCount: Int {
    cardSequences.reduce(0) { acc, seq in
        acc + seq.enumerated().filter { idx, s in idx > 0 && !s.sameDay }.count
    }
}
```
Remove the placeholder `init(cardSequences:)` or keep it `internal` for test fixtures — keep it `public` only if a test needs to inject sequences directly (the convergence test in T3 does). **Keep both inits public.**

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/AnghkooeyCore && swift test --filter OptimizationDataset 2>&1 | tail -20`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/Optimization/OptimizationDataset.swift \
        Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/OptimizationDatasetTests.swift
git commit -m "feat(m8): OptimizationDataset replay sample builder + eligibility"
```

---

## Task T2 — py-fsrs parity fixture (Codex, Python)

> **Codex primary impl.** Codex authors the Python; Claude runs it locally (Codex sandbox can't pip-install reliably) and commits the JSON. This is the **DoD-critical** parity oracle, built **before** T3's optimizer math.

**Files:**
- Create: `scripts/fsrs-optimizer/generate_fsrs_optimizer_fixture.py`
- Create: `scripts/fsrs-optimizer/requirements.txt`
- Create: `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/Fixtures/fsrs-optimizer-parity.json`

- [ ] **Step 1: Pin py-fsrs**

```bash
python3 -m pip index versions fsrs   # pick latest stable FSRS-6 / 21-param release
```
Write the exact version to `scripts/fsrs-optimizer/requirements.txt`:
```
fsrs==X.Y.Z   # resolved 2026-05-29; FSRS-6, len(default_parameters)==21
```

- [ ] **Step 2: Codex authors the generator**

`scripts/fsrs-optimizer/generate_fsrs_optimizer_fixture.py` must:
1. Build a **deterministic synthetic** review-log dataset (fixed `random.seed(42)`): ~60–120 cards, mixed ratings, multi-day intervals, some same-day pairs, enough to clear the 512-eligible threshold comfortably (so the fixture also exercises the gated path). Emit each review as `{card_id, reviewed_at_iso, rating(1..4), elapsed_days}` — the **same four fields** as `OptimizationReviewLogRow`, so Swift and Python consume identical inputs.
2. Construct py-fsrs `ReviewLog`/`Optimizer` from that dataset and call `compute_optimal_parameters()`.
3. Compute baseline loss (mean BCE under `default_parameters`) and optimized loss (under the fitted `w`) using py-fsrs's own loss, over **its** eligible-sample set.
4. **Record observed semantics** in a top-of-file comment block: which reviews py-fsrs filters from the loss (first / same-day / other), and the `w[0..3]` pretraining procedure. T3 replicates exactly this.
5. Emit JSON:
```json
{
  "meta": {
    "pyfsrs_version": "X.Y.Z",
    "generated_at": "<iso>",
    "seed": 42,
    "eligible_sample_count": <int>,
    "fsrs_version": "FSRS-6.0"
  },
  "reviews": [ {"card_id": "...", "reviewed_at": "...", "rating": 3, "elapsed_days": 2.0}, ... ],
  "baseline_loss": <double>,
  "optimized_loss": <double>,
  "optimized_w": [ <21 doubles> ]
}
```

- [ ] **Step 3: Claude runs it locally + commits the JSON**

```bash
cd scripts/fsrs-optimizer
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
python3 generate_fsrs_optimizer_fixture.py > ../../Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/Fixtures/fsrs-optimizer-parity.json
deactivate
```
Verify: `python3 -c "import json,sys; d=json.load(open('Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/Fixtures/fsrs-optimizer-parity.json')); print(d['meta']['eligible_sample_count'], d['baseline_loss'], d['optimized_loss'])"`
Expected: eligible count ≥ 512; `optimized_loss < baseline_loss`.

> The `Fixtures` dir is already a `.process` resource in `AnghkooeyCore/Package.swift:32` — no Package.swift change needed.

- [ ] **Step 4: Record the observed numbers** in the plan margin / ADR-0005 draft (baseline_loss, optimized_loss, eligible_sample_count, pyfsrs_version). T3's parity assertion uses these.

- [ ] **Step 5: Commit**

```bash
git add scripts/fsrs-optimizer/ \
        Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/Fixtures/fsrs-optimizer-parity.json
git commit -m "feat(m8): py-fsrs parity fixture generator + pinned fixture JSON"
```

---

## Task T3 — LiveFSRSOptimizer (Opus; Codex fresh-eyes review)

> **Math-critical — runs on Opus.** Replays state under candidate params through `LiveFSRS6Engine` internals (same module → `@usableFromInline internal` methods `nextMemoryState`, `forgettingCurve` are accessible). Per `feedback_fixture_parity_over_unit_tests`, parity is part of DoD. After Opus implements, dispatch Codex for a **fresh-eyes review** of the gradient/pretraining/clipping/eligibility logic (10-min timeout → fallback `ecc:code-reviewer`).

**Files:**
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/Optimization/LiveFSRSOptimizer.swift`
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Logging/CoreLog.swift`
- Test: `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/FSRSOptimizerConvergenceTests.swift`
- Test: `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/FSRSOptimizerParityTests.swift`

### Replay + loss reference (the one math surface)

For a candidate `FSRSParameters` `p`, instantiate `let engine = LiveFSRS6Engine(parameters: p)` once and replay each card sequence:
- Maintain `(state: CardState, s: Double, d: Double)`, starting `(.new, 0, 0)`.
- For each `sample` at index `i`:
  - **If eligible (`i > 0 && !sample.sameDay`)**: predicted recall `r = engine.forgettingCurve(elapsedDays: sample.elapsedDays, stability: s)`; clip to `[1e-7, 1-1e-7]`; label `y = (sample.rating == .again) ? 0.0 : 1.0`; accumulate BCE `-(y*log(r) + (1-y)*log(1-r))`.
  - **Advance state** (eligible or not, including same-day and first): use `engine.nextMemoryState(d: d, s: s, t: Int(sample.elapsedDays), g: sample.rating)` → new `(d, s)`; set `state = .review` after the first review. (First review hits the seed path `d==0 && s==0` → init stability/difficulty.)
- Mean BCE = `totalLoss / eligibleCount`.

> Intervals/due dates are **not** computed — the loss uses *actual* `elapsedDays`, not scheduled intervals (spec §M8.3 decision: this is why finite differences are sound). Predicted recall and state evolution are the only math, both from the parity-verified engine.

### Contract

```swift
public struct LiveFSRSOptimizer: FSRSOptimizer {
    public struct Config: Sendable {
        public var epochs: Int = 100               // calibrate in step 5
        public var batchSize: Int = 256
        public var learningRate: Double = 0.01
        public var seed: UInt64 = 42
        public init() {}
    }
    public init(config: Config = Config())
    public func optimize(_ dataset: OptimizationDataset, from initial: FSRSParameters,
                         progress: @Sendable (Double) -> Void) async -> OptimizationResult
    // internal, tested directly:
    func meanLoss(_ dataset: OptimizationDataset, parameters: FSRSParameters) -> Double
    func gradient(_ dataset: OptimizationDataset, parameters: FSRSParameters) -> [Double]  // finite diff
    func pretrainInitialStability(_ dataset: OptimizationDataset, into w: inout [Double])   // w[0..3]
}
```

- [ ] **Step 1: Write the convergence test (TDD, generate-then-assert)**

Generate synthetic reviews from a **known** `w` (perturb `.default.w` by a fixed vector), build the dataset, run the optimizer from `.default`, and assert loss/calibration recovery — **not** weight equality.

```swift
import Testing
import Foundation
@testable import AnghkooeyCore

@Suite("FSRSOptimizer convergence")
struct FSRSOptimizerConvergenceTests {
    @Test("recovers a known parameter family within tolerance")
    func convergesOnSynthetic() async {
        // 1. Known params: default with a small deterministic perturbation.
        var trueW = FSRSParameters.default.w
        trueW[8] += 0.3; trueW[9] += 0.05; trueW[10] += 0.2
        let trueParams = FSRSParameters.default.withWeights(trueW)

        // 2. Generate synthetic eligible-rich sequences (helper below).
        let dataset = SyntheticReviews.dataset(under: trueParams, cards: 200, seed: 7)
        #expect(dataset.eligibleSampleCount >= 512)

        let opt = LiveFSRSOptimizer()
        let lossUnderTrue = opt.meanLoss(dataset, parameters: trueParams)

        // 3. Optimize from default.
        let result = await opt.optimize(dataset, from: .default, progress: { _ in })

        // 4. Loss recovery within 2% of loss-under-true-params.
        #expect(result.optimizedLoss <= lossUnderTrue * 1.02)
        #expect(result.optimizedLoss < result.baselineLoss)
        // 5. Calibration: mean predicted recall ≈ mean actual pass-rate ± 0.02.
        let cal = SyntheticReviews.calibration(dataset, parameters: result.optimizedParameters)
        #expect(abs(cal.meanPredicted - cal.meanActual) <= 0.02)
    }
}
```

Write a `SyntheticReviews` test helper (same file or a `Fixtures`-adjacent test util) that, given `FSRSParameters`, replays a `SeededGenerator` to emit `OptimizationReviewLogRow`s by sampling pass/fail from the true forgetting curve at random intervals, and a `calibration(_:parameters:)` returning `(meanPredicted, meanActual)`. **This helper reuses the same replay logic** — keep it DRY by calling the optimizer's `internal` replay, or factor replay into a `RecallReplay` helper both use.

- [ ] **Step 2: Run → fail** (`swift test --filter Convergence`) — `LiveFSRSOptimizer` is empty. Expected: build/compile failure.

- [ ] **Step 3: Opus implements `LiveFSRSOptimizer`**

Implement, in order:
1. `meanLoss` via the replay above.
2. `gradient`: central finite difference per weight, `eps_i = max(1e-5, 1e-4 * |w_i|)` (provisional — calibrate step 5).
3. `pretrainInitialStability`: replicate the **recorded** py-fsrs `w[0..3]` procedure from the T2 fixture comment block. Group first→second-review outcomes by first rating; fit each initial stability. Clamp to FSRS-6 ranges.
4. `optimize`: pretrain `w[0..3]` → Adam over mini-batches (`SeededGenerator(seed:)` shuffle) for `epochs` → clamp each weight to FSRS-6 valid ranges every step (`w20 ∈ [0.1, 0.8]`, etc.) → compute baseline/optimized loss + deltas + achievedRetention → wrap the whole run in `CoreLog.poiSignposter.beginInterval("fsrs-optimization", ...)` / `endInterval`. Emit `progress(epoch/epochs)`.

Add to `CoreLog.swift` the interval name in the `poiSignposter` doc comment: `"fsrs-optimization"`.

- [ ] **Step 4: Run convergence test → pass**, iterating on Adam LR / epochs until green. (`swift test --filter Convergence`)

- [ ] **Step 5: Write + pass the parity test (read fixture, assert observed ± tolerance)**

```swift
import Testing
import Foundation
@testable import AnghkooeyCore

@Suite("FSRSOptimizer parity vs py-fsrs")
struct FSRSOptimizerParityTests {
    struct Fixture: Codable { /* meta, reviews, baseline_loss, optimized_loss, optimized_w */ }

    @Test("matches py-fsrs loss improvement within tolerance")
    func parity() async throws {
        let url = Bundle.module.url(forResource: "fsrs-optimizer-parity", withExtension: "json")!
        let fx = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let rows = fx.reviews.map { /* → OptimizationReviewLogRow */ }
        let dataset = OptimizationDataset(rows: rows)

        // Eligible count must match py-fsrs EXACTLY (same filtering semantics).
        #expect(dataset.eligibleSampleCount == fx.meta.eligibleSampleCount)

        let opt = LiveFSRSOptimizer()
        let result = await opt.optimize(dataset, from: .default, progress: { _ in })

        #expect(result.baselineLoss == approx(fx.baselineLoss, abs: 0.001)) // same inputs+default w → same baseline
        #expect(result.optimizedLoss <= result.baselineLoss)
        // Loss-based parity (NOT weight equality): see plan §Expansion checklist #3.
        let absOK = abs(result.optimizedLoss - fx.optimizedLoss) <= 0.01
        let relOK = abs(result.optimizedLoss - fx.optimizedLoss) <= 0.05 * fx.optimizedLoss
        #expect(absOK || relOK)
    }
}
```
> If finite differences cannot reach this tolerance after epsilon/LR/epoch calibration, **escalate to analytic gradients** (spec §M8.3 trigger) and document the switch in ADR-0005. Measure before assuming.

- [ ] **Step 6: Codex fresh-eyes review** of `LiveFSRSOptimizer.swift` (eligibility filter, pretraining, BCE clipping, epsilon scaling, clamping). 10-min timeout → `ecc:code-reviewer` fallback. Apply fixes.

- [ ] **Step 7: Run full Core suite** (`cd Packages/AnghkooeyCore && swift test 2>&1 | tail -20`) — all green, including existing FSRS parity tests (default params untouched).

- [ ] **Step 8: Commit**

```bash
git add Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/Optimization/LiveFSRSOptimizer.swift \
        Packages/AnghkooeyCore/Sources/AnghkooeyCore/Logging/CoreLog.swift \
        Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/FSRSOptimizer*Tests.swift
git commit -m "feat(m8): LiveFSRSOptimizer — replay loss, finite-diff Adam, w0-3 pretraining"
```

---

## Task T4 — OptimizedParametersStore + threshold gate

**Files:**
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/FSRSParameters.swift`
- Create: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/Optimization/OptimizedParametersStore.swift`
- Test: `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/OptimizedParametersStoreTests.swift`

- [ ] **Step 1: Add `withWeights` to FSRSParameters**

```swift
public extension FSRSParameters {
    /// Returns a copy of `self` with `w` replaced. Used to apply optimized
    /// weights onto the immutable `.default` configuration (retention,
    /// learning steps, etc. are preserved; only `w` is personalised).
    func withWeights(_ newW: [Double]) -> FSRSParameters {
        FSRSParameters(
            w: newW,
            requestRetention: requestRetention,
            maximumInterval: maximumInterval,
            enableFuzz: enableFuzz,
            enableShortTerm: enableShortTerm,
            learningStepsSeconds: learningStepsSeconds,
            relearningStepsSeconds: relearningStepsSeconds
        )
    }
}
```

- [ ] **Step 2: Write the failing tests**

```swift
import Testing
import Foundation
@testable import AnghkooeyCore

@Suite("OptimizedParametersStore")
struct OptimizedParametersStoreTests {
    private func tempStore() -> OptimizedParametersStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return OptimizedParametersStore(containerURL: dir)
    }

    @Test("under threshold returns default regardless of stored value")
    func underThresholdReturnsDefault() throws {
        let store = tempStore()
        var w = FSRSParameters.default.w; w[8] += 1.0
        try store.save(FSRSParameters.default.withWeights(w))
        let resolved = store.resolveParameters(eligibleSampleCount: 511)
        #expect(resolved == FSRSParameters.default)
    }

    @Test("at/above threshold returns stored optimized set")
    func atThresholdReturnsStored() throws {
        let store = tempStore()
        var w = FSRSParameters.default.w; w[8] += 1.0
        let optimized = FSRSParameters.default.withWeights(w)
        try store.save(optimized)
        #expect(store.resolveParameters(eligibleSampleCount: 512) == optimized)
    }

    @Test("above threshold with no stored value falls back to default")
    func noStoredValueFallsBack() {
        let store = tempStore()
        #expect(store.resolveParameters(eligibleSampleCount: 5000) == FSRSParameters.default)
    }

    @Test("persists across store instances (same container)")
    func persistsAcrossInstances() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var w = FSRSParameters.default.w; w[0] += 0.5
        try OptimizedParametersStore(containerURL: dir).save(FSRSParameters.default.withWeights(w))
        let reloaded = OptimizedParametersStore(containerURL: dir).resolveParameters(eligibleSampleCount: 1000)
        #expect(reloaded.w[0] == FSRSParameters.default.w[0] + 0.5)
    }

    @Test("threshold constant is 512")
    func thresholdValue() { #expect(OptimizedParametersStore.threshold == 512) }
}
```

- [ ] **Step 3: Run → fail** (`swift test --filter OptimizedParametersStore`) — type doesn't exist.

- [ ] **Step 4: Implement the store**

```swift
import Foundation

/// Persists one GLOBAL optimized FSRS-6 weight set and resolves
/// optimized-or-default at the scheduling call site.
///
/// Stored as JSON in the app-group container so the widget extension reads the
/// same file. Only `w` is persisted; everything else is rebuilt onto
/// `FSRSParameters.default` (which stays ADR-0002-immutable).
public struct OptimizedParametersStore: Sendable {
    /// Eligible-sample count below which `.default` is always used (py-fsrs gate).
    public static let threshold = 512

    private let fileURL: URL

    public init(containerURL: URL) {
        self.fileURL = containerURL.appendingPathComponent("optimized-fsrs-params.json")
    }

    private struct Blob: Codable { let w: [Double] }

    public func save(_ parameters: FSRSParameters) throws {
        let data = try JSONEncoder().encode(Blob(w: parameters.w))
        try data.write(to: fileURL, options: .atomic)
    }

    /// The stored optimized set, or `nil` if none persisted / unreadable.
    public func loadOptimized() -> FSRSParameters? {
        guard let data = try? Data(contentsOf: fileURL),
              let blob = try? JSONDecoder().decode(Blob.self, from: data),
              blob.w.count == 21 else { return nil }
        return FSRSParameters.default.withWeights(blob.w)
    }

    /// Optimized-or-default. Returns `.default` when `eligibleSampleCount < threshold`
    /// OR when no optimized set is stored.
    public func resolveParameters(eligibleSampleCount: Int) -> FSRSParameters {
        guard eligibleSampleCount >= Self.threshold, let optimized = loadOptimized() else {
            return .default
        }
        return optimized
    }
}
```

- [ ] **Step 5: Run → pass.** `swift test --filter OptimizedParametersStore` → 5 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/FSRSParameters.swift \
        Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/Optimization/OptimizedParametersStore.swift \
        Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/OptimizedParametersStoreTests.swift
git commit -m "feat(m8): OptimizedParametersStore + threshold gate + FSRSParameters.withWeights"
```

---

## Task T6 — CardStore.optimizationReviewLogs() projection

> Done before T5 because T5's resolution calls it. Narrow projection: reads only `card.id` off each `ReviewLog` (not question/answer/tags) — Codex item #10. A denormalized `ReviewLog.cardID` would remove even the `card.id` relationship access, but that is a schema V6 migration and is **out of M8 scope** — note it in ADR-0005 as a future optimization.

**Files:**
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardStore.swift` (protocol + `CardStore` actor + `MockCardStore`)
- Test: `App/AnghkooeyTests/CardStoreOptimizationLogsTests.swift` (needs a real `ModelContainer` → app target)

- [ ] **Step 1: Add to the protocol**

In `CardStoreProtocol`:
```swift
/// Returns a narrow projection of every `ReviewLog`, sorted by
/// `(cardID, reviewedAt)`, for the FSRS optimizer. Projects only the four
/// fields `OptimizationDataset` needs — it does not materialise full `Card`
/// graphs (Codex #10).
func optimizationReviewLogs() async throws -> [OptimizationReviewLogRow]
```

- [ ] **Step 2: Write the failing test** (app target — real container)

```swift
import Testing
import Foundation
import SwiftData
@testable import AnghkooeyCore

@Suite("CardStore.optimizationReviewLogs")
struct CardStoreOptimizationLogsTests {
    private func makeStore() throws -> CardStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: Schema(AnghkooeySchemaV5.models), configurations: config)
        return CardStore(container: container)
    }

    @Test("projects and sorts review logs by (cardID, reviewedAt)")
    func projectionAndOrder() async throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = LiveFSRS6Engine()
        // Create one card, review it twice on different days.
        let snap = try await store.create(question: "q", answer: "a", sourceSpan: nil, now: now)
        let card = SchedulingCard.newCard(due: now)
        let out1 = try engine.next(card: card, rating: .good, now: now)
        try await store.apply(out1, to: snap.id, grade: .good, now: now)
        let day3 = now.addingTimeInterval(3 * 86_400)
        let out2 = try engine.next(card: out1.card, rating: .good, now: day3)
        try await store.apply(out2, to: snap.id, grade: .good, now: day3)

        let rows = try await store.optimizationReviewLogs()
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.cardID == snap.id })
        #expect(rows[0].reviewedAt <= rows[1].reviewedAt)
        #expect(rows[1].elapsedDays == 3)  // day diff captured by the engine
    }
}
```
Wire the new test file into the `AnghkooeyTests` target per `feedback_app_test_target_wiring` (GENERATE_INFOPLIST_FILE=YES + scheme Testables entry) and `xcode-16-synchronized-folders-no-pbxproj-edit`.

- [ ] **Step 3: Run → fail** (xcodebuild test command from §Verification setup, `-only-testing:AnghkooeyTests/CardStoreOptimizationLogsTests`).

- [ ] **Step 4: Implement in the `CardStore` actor**

```swift
public func optimizationReviewLogs() async throws -> [OptimizationReviewLogRow] {
    let descriptor = FetchDescriptor<ReviewLog>(sortBy: [SortDescriptor(\.reviewedAt)])
    let logs = try modelContext.fetch(descriptor)
    let rows: [OptimizationReviewLogRow] = logs.compactMap { log in
        guard let cardID = log.card?.id else { return nil }  // orphan logs skipped
        return OptimizationReviewLogRow(
            cardID: cardID, reviewedAt: log.reviewedAt,
            rating: log.rating, elapsedDays: log.elapsedDays)
    }
    return rows.sorted {
        $0.cardID == $1.cardID ? $0.reviewedAt < $1.reviewedAt
                               : $0.cardID.uuidString < $1.cardID.uuidString
    }
}
```

And in `MockCardStore` (derive rows from the recorded `reviewLogs` tuples):
```swift
public func optimizationReviewLogs() async throws -> [OptimizationReviewLogRow] {
    reviewLogs.map { entry in
        OptimizationReviewLogRow(
            cardID: entry.cardID,
            reviewedAt: entry.output.log.reviewedAt,
            rating: entry.grade,
            elapsedDays: entry.output.log.elapsedDays)
    }
    .sorted { $0.cardID == $1.cardID ? $0.reviewedAt < $1.reviewedAt
                                     : $0.cardID.uuidString < $1.cardID.uuidString }
}
```

- [ ] **Step 5: Run → pass.**

- [ ] **Step 6: Commit**

```bash
git add Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardStore.swift \
        App/AnghkooeyTests/CardStoreOptimizationLogsTests.swift
git commit -m "feat(m8): CardStore.optimizationReviewLogs() narrow projection"
```

---

## Task T5 — Scheduling call-site optimized-or-default resolution

> **Codex reviewer.** Routes the scheduler's parameter source through `OptimizedParametersStore`. Default args can't be `async`, so resolution lives in `AppState`. Regression bar: existing parity tests stay green — the resolver returns `.default` for all current/empty-history cases.

**Files:**
- Modify: `App/Anghkooey/AppState.swift`
- Modify: `App/Anghkooey/ContentView.swift:17`
- Test: extend `App/AnghkooeyTests/CardStoreOptimizationLogsTests.swift` or a new `AppStateSchedulerResolutionTests.swift`

- [ ] **Step 1: Write the failing test** (AppState resolves default under threshold)

```swift
@Suite("AppState scheduler resolution")
@MainActor
struct AppStateSchedulerResolutionTests {
    @Test("under-threshold history resolves to default params")
    func defaultUnderThreshold() async {
        let store = MockCardStore()  // empty → 0 eligible
        let appState = AppState(cardStore: store)
        await appState.refreshScheduler()
        let engine = appState.scheduler as? LiveFSRS6Engine
        #expect(engine?.parameters == FSRSParameters.default)
    }
}
```

- [ ] **Step 2: Run → fail** (`refreshScheduler`/`scheduler` don't exist).

- [ ] **Step 3: Implement in AppState**

Add an `OptimizedParametersStore` (app-group container URL) and a resolved engine:
```swift
// stored properties
private(set) var scheduler: any FSRS6Engine = LiveFSRS6Engine()
private let optimizedParamsStore: OptimizedParametersStore
private var widgetReconciler: WidgetGradeReconciler   // change `let` → `var`
private let widgetContainerURL: URL                    // capture for reconciler rebuild
```
In `init`, after computing `containerURL`:
```swift
self.optimizedParamsStore = OptimizedParametersStore(containerURL: containerURL)
self.widgetContainerURL = containerURL
```
Add the method:
```swift
/// Resolve optimized-or-default FSRS params from accumulated history and
/// rebuild the scheduler + widget reconciler to use them. Call on launch,
/// after a drain, and after an optimization run completes.
func refreshScheduler() async {
    let rows = (try? await cardStore.optimizationReviewLogs()) ?? []
    let eligible = OptimizationDataset(rows: rows).eligibleSampleCount
    let params = optimizedParamsStore.resolveParameters(eligibleSampleCount: eligible)
    let engine = LiveFSRS6Engine(parameters: params)
    self.scheduler = engine
    self.widgetReconciler = WidgetGradeReconciler(
        store: cardStore,
        bridge: WidgetBridge(containerURL: widgetContainerURL),
        scheduler: engine)
}
```
Call `await refreshScheduler()` at the end of `drain()` (and once at startup — add a `Task { await refreshScheduler() }` after init wiring, or in the app's `.task`). Pass the resolved engine to the UI.

- [ ] **Step 4: Update ContentView** `App/Anghkooey/ContentView.swift:17`:
```swift
ReviewScreen(store: appState.cardStore, scheduler: appState.scheduler)
```

- [ ] **Step 5: Run → pass.** Then run the **full** existing Core parity suite to confirm no regression:
`cd Packages/AnghkooeyCore && swift test 2>&1 | tail -20` → all green (default params unchanged).

- [ ] **Step 6: Codex review** of the AppState diff (engine rebuild correctness, no retain cycle in the `drain()` call). 10-min timeout → `ecc:code-reviewer`.

- [ ] **Step 7: Commit**

```bash
git add App/Anghkooey/AppState.swift App/Anghkooey/ContentView.swift \
        App/AnghkooeyTests/AppStateSchedulerResolutionTests.swift
git commit -m "feat(m8): resolve optimized-or-default FSRS params at scheduling call sites"
```

---

## Task T7 — OptimizeScheduleView

**Files:**
- Create: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Optimization/OptimizeScheduleView.swift`
- (No new package wiring — file lands under the globbed `AnghkooeyUI` sources.)
- Test: `Packages/AnghkooeyUI/Tests/AnghkooeyUITests/Optimization/OptimizeScheduleViewModelTests.swift`

> AnghkooeyUI's package test target has a plugin limitation when run via `swift test` (`feedback_swift_test_package_limitations`); run the view-model test via the app scheme's UI package tests through xcodebuild, or keep the view-model logic testable as a plain `@MainActor @Observable` class exercised in the app target. Prefer testing the **view model**, not the SwiftUI view.

- [ ] **Step 1: Write the failing view-model test**

```swift
import Testing
import Foundation
@testable import AnghkooeyUI
@testable import AnghkooeyCore

@MainActor
@Suite("OptimizeScheduleViewModel")
struct OptimizeScheduleViewModelTests {
    @Test("under threshold shows locked state with eligible count")
    func lockedState() async {
        let vm = OptimizeScheduleViewModel(
            store: MockCardStore(),               // 0 eligible
            optimizer: MockFSRSOptimizer(),
            paramsStore: OptimizedParametersStore(containerURL: FileManager.default.temporaryDirectory))
        await vm.refresh()
        #expect(vm.isUnlocked == false)
        #expect(vm.eligibleSampleCount == 0)
        #expect(vm.unlockThreshold == 512)
    }

    @Test("running the optimizer publishes progress then a result")
    func runProducesResult() async {
        let vm = OptimizeScheduleViewModel(
            store: MockCardStore(),
            optimizer: MockFSRSOptimizer(),
            paramsStore: OptimizedParametersStore(containerURL: FileManager.default.temporaryDirectory))
        await vm.optimize()
        #expect(vm.result?.optimizedLoss == 0.42)   // MockFSRSOptimizer default
        #expect(vm.progress == 1.0)
    }
}
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement the view model + view**

`OptimizeScheduleViewModel` (`@MainActor @Observable`): holds `eligibleSampleCount`, `isUnlocked` (`count >= OptimizedParametersStore.threshold`), `unlockThreshold = OptimizedParametersStore.threshold`, `progress: Double`, `result: OptimizationResult?`, `isRunning`. `refresh()` computes `eligibleSampleCount` via `OptimizationDataset(rows: store.optimizationReviewLogs()).eligibleSampleCount`. `optimize()` builds the dataset, calls `optimizer.optimize(_:from: .default, progress:)` updating `progress` on the main actor, then `try? paramsStore.save(result.optimizedParameters)` and stores `result`.

`OptimizeScheduleView`: locked empty state ("Not enough review history yet — unlocks at \(unlockThreshold) reviews (\(eligibleSampleCount) so far)"); a "Optimize my schedule" button; a `ProgressView(value: progress)` while running; a before/after summary (baseline vs optimized loss, achieved retention, count of weights changed from `weightDeltas`). After a successful run, the caller (host screen) should `await appState.refreshScheduler()` so new scheduling picks up the saved params — document this in the view's header and trigger it via a callback `onOptimized: () async -> Void`.

- [ ] **Step 4: Run → pass.**

- [ ] **Step 5: Commit**

```bash
git add Packages/AnghkooeyUI/Sources/AnghkooeyUI/Optimization/ \
        Packages/AnghkooeyUI/Tests/AnghkooeyUITests/Optimization/
git commit -m "feat(m8): OptimizeScheduleView + view-model (trigger, progress, before/after, locked state)"
```

---

## Task T8 — PERFORMANCE.md trace + ADR-0005 + exit review (Opus)

**Files:**
- Modify: `PERFORMANCE.md`
- Create: `docs/DECISIONS/0005-fsrs-optimization.md`
- Modify: `ARCHITECTURE.md` (append M8 section — never edit prior sections, per `reference_architecture_md`)
- Re-read: `foundation.md` §out-of-scope

- [ ] **Step 1: Capture the os_signpost / Instruments trace**

Seed a realistically-sized collection (≥512 eligible samples — reuse `SyntheticReviews` or the T2 fixture data loaded into a real container on a booted simulator/device), trigger an optimization run, and capture the `"fsrs-optimization"` interval. Per `feedback_simulator_ui_interaction`, `xctrace` on mock-store tests gives near-zero durations (useless) — run against a **real seeded container** on device or a booted sim, not a mock. Record wall-clock duration, CPU, and peak memory.

- [ ] **Step 2: Write the PERFORMANCE.md section** — optimization run time/CPU/memory on the seeded collection, with commentary on whether it fits a sane on-device budget (this is the gap-#5 senior signal). Include the Instruments screenshot/trace reference.

- [ ] **Step 3: Author ADR-0005** (`docs/DECISIONS/0005-fsrs-optimization.md`), covering (spec §M8.7):
  - finite-difference vs analytic gradients, correctness-over-speed rationale, and the escalation trigger (and whether it fired);
  - numerical-stability decisions: central differences, the **final calibrated** per-param epsilon rule, BCE clipping `[1e-7, 1-1e-7]`, clamping to FSRS-6 ranges;
  - replication of py-fsrs eligibility + `w[0..3]` pretraining semantics, citing the **pinned py-fsrs version** and the recorded-semantics block from T2 (and the `ts-fsrs v5.4.0` scheduler / py-fsrs optimizer version-skew note);
  - global-parameter scope (one weight set, not per-tag); eligible-sample threshold = 512; app-group JSON storage; the deferred `ReviewLog.cardID` denormalization;
  - loss-based (not weight-equality) validation strategy.

- [ ] **Step 4: Append the ARCHITECTURE.md M8 section** — the optimizer's one-math-surface design, replay-based dataset, storage/resolution flow.

- [ ] **Step 5: foundation.md re-check** — confirm M8 lands within v2 scope and no v1 omissions resurfaced (`feedback_foundation_recheck_at_milestone_close`).

- [ ] **Step 6: Opus milestone exit review** — verify all M8 exit gates below. Codex reviewer pass on ADR-0005 (fresh eyes).

- [ ] **Step 7: Commit**

```bash
git add PERFORMANCE.md docs/DECISIONS/0005-fsrs-optimization.md ARCHITECTURE.md
git commit -m "docs(m8): PERFORMANCE.md optimizer trace, ADR-0005, ARCHITECTURE.md M8 section"
```

---

## Validation / Exit Gates (M8)

- [ ] `cd Packages/AnghkooeyCore && swift test` green; full app-target test suite green.
- [ ] **py-fsrs parity within tolerance (loss-based, not exact weights)** — `FSRSOptimizerParityTests` passes; eligible-sample count matches py-fsrs exactly.
- [ ] Convergence-on-synthetic recovers known params within loss + calibration tolerance (`FSRSOptimizerConvergenceTests`).
- [ ] Under-threshold returns `FSRSParameters.default` (`OptimizedParametersStoreTests` + `AppStateSchedulerResolutionTests`).
- [ ] Existing FSRS parity tests (default params) still green — no scheduling regression.
- [ ] `PERFORMANCE.md` updated with a real optimization-run trace on a ≥512-eligible seeded collection (not a mock store).
- [ ] ADR-0005 merged; ARCHITECTURE.md appended; foundation.md re-check done.
- [ ] Device QA: seed ≥512-eligible-sample collection → tap Optimize → progress + before/after shown → subsequent scheduling uses optimized params (verify via a card whose next interval changes).

---

## Self-review notes (author, 2026-05-29)

- **Spec coverage:** §M8.2 → T1/T6; §M8.3 → T3; §M8.4 → T4/T5; §M8.5 (DoD) → T2/T3 parity + convergence + T4 gate; §M8.6 file map → T0/T1/T3/T4/T6/T7; §M8.7 ADR → T8. All §M8 subsections mapped.
- **Type consistency:** `OptimizationReviewLogRow` (T0) is the single row type consumed by `OptimizationDataset.init(rows:)` (T1), produced by `optimizationReviewLogs()` (T6), and decoded in the parity test (T3). `withWeights` (T4) is used by T3 convergence + T4 store + resolution. `eligibleSampleCount` name is consistent across T1/T4/T5/T7. `scheduler`/`refreshScheduler` consistent T5↔T7.
- **Data-dependent values flagged, not invented:** `maxSequenceLength`, finite-diff epsilon, epochs/LR, and all parity/convergence tolerances are marked provisional with a generate-then-assert TDD structure so the executor calibrates against the real T2 fixture rather than asserting blind.
- **Known judgment call deferred to execution:** T3's `w[0..3]` pretraining math is intentionally specified at contract level (replicate the T2-recorded py-fsrs procedure) — this is the one task routed to **Opus** precisely because it needs judgment against the py-fsrs source as oracle.
