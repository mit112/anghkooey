# v2 Design — Cloze Deletion Cards (M7) + Personal FSRS Optimization (M8)

**Date:** 2026-05-28
**Status:** Approved (brainstorming complete; Codex design review incorporated)
**Supersedes scope notes in:** `memory/project_v2_scope.md`
**Authoritative for product scope:** `foundation.md` (§Out-of-scope-for-v1 list — cloze and FSRS optimization were explicitly deferred to v2)

---

## 0. Framing & roadmap

v2 closes the two highest-signal remaining portfolio gaps while widening the product surface. Two milestones are designed in depth now; the rest are explicitly deferred.

| | Milestone | Closes skill gap | Status |
|---|---|---|---|
| **M7** | Cloze deletion cards | `@Generable` depth (gap #1) | **designed — build first** |
| **M8** | Personal FSRS optimization | algorithm correctness + MetricKit/`os_signpost`/Instruments perf write-up (gap #5) | **designed — build second** |
| — | iPad-optimized UI | — | **deferred**, App-Store-traction-gated → its own spec→plan cycle when usage data justifies it |
| — | `BGProcessingTask` auto-optimization | — | **future** follow-up to M8 (manual trigger proven first) |
| — | Per-tag parameter sets | — | backlog (data-starved per tag; revisit only for very large collections) |
| — | AI-generated mnemonic images; contextual-application cards | — | backlog (`project_v2_scope`) |
| — | macOS / watchOS / visionOS | — | **never for this project** (`foundation.md`) |

**Ordering rationale.** Cloze ships first: it is immediate user-visible value that compounds with the AI authoring already shipped, and it deepens the `@Generable` story. FSRS optimization ships second because it is only meaningful once a user has accumulated review history (≥512 eligible samples), and it is the higher-risk math port — letting real review logs accumulate during M7 gives M8 better validation data. FSRS optimization strictly precedes any iPad work ("a bigger canvas for a worse algorithm is backwards").

**Why MetricKit is *not* the FSRS training source.** MetricKit collects performance/diagnostic telemetry, not review outcomes. The optimizer trains on `ReviewLog`. The link to gap #5 is that the optimizer is a compute-heavy on-device task: instrumenting its run with `os_signpost`/Instruments is the `PERFORMANCE.md` story (does the optimization fit a sane time/CPU budget on real-sized collections?).

---

## M7 — Cloze deletion cards

### M7.1 Product behavior

A user captures a passage and chooses **Cloze** instead of **Q&A**. The on-device model proposes the passage with salient terms marked as cloze deletions. The user toggles/adds/removes deletions in a tap-to-blank editor, then accepts. Each deletion becomes an independently-scheduled card (Anki-style siblings) sharing the source text. During review, sibling cards are buried so reviewing one does not leak the answer to another.

### M7.2 Data model (schema V5, lightweight migration V4→V5)

Add to `Card`, all `Optional` for migration safety (per `feedback_swiftdata_versioned_namespacing` — new migration fields must be Optional):

| Field | Type | Meaning |
|---|---|---|
| `cardType` | `CardType?` | `.qa` / `.cloze`. Reads nil-coalesce to `.qa` for migrated cards. |
| `clozeGroupID` | `UUID?` | Shared by all siblings from one source passage; `nil` for Q&A. |
| `clozeIndex` | `Int?` | Which deletion this card hides (1-based, like Anki `c1`/`c2`). |
| `clozeSourceText` | `String?` | The authored marked template, stored per-sibling. Invariant: **all siblings in a group store identical source text.** |
| `clozeBuriedUntil` | `Date?` | When set and in the future, this card is held out of review (sibling-bury state). Distinct from `dueAt`. |

`CardType` is a new `public enum CardType: Int, Codable, Sendable, CaseIterable { case qa = 0; case cloze = 1 }` — mirrors `CardState`'s pinned-`Int`-raw-value pattern, which already coexists with the CloudKit container. **CloudKit V5 schema validation is the first M7 task** (see M7.7), not end-of-milestone cleanup.

**`question`/`answer` remain baked rendered strings.** For a cloze card: `question` = source text with *this* deletion rendered as `[…]` and all *other* deletions revealed (their answers shown inline); `answer` = the hidden term(s) for this index. Consequence: the review UI and the FSRS scheduler are **completely unchanged** — a cloze card is a `Card` with baked text plus grouping/bury metadata.

**Immutability invariant.** Cloze groups are immutable after creation. There is **no per-card `clozeSourceText` edit path**. Editing means either a group-level "rebuild siblings" operation (out of scope for M7 unless trivial) or re-authoring. The card editor must not expose partial edits that desync siblings. This is what makes baked strings safe (Codex review item #4).

### M7.3 Marker grammar + parser (the reusable core)

Cloze content is carried as Anki-style markup:

```
The {{c1::mitochondria}} is the {{c2::powerhouse::organelle hint}} of the cell
```

Grammar: `{{c<N>::answer}}` or `{{c<N>::answer::hint}}`, `N` ≥ 1.

`ClozeMarkupParser` (pure value-type logic in `AnghkooeyCore`):
- Parses markup → `ClozeTemplate(sourceText: String, deletions: [ClozeDeletion])` where `ClozeDeletion = (index: Int, answer: String, hint: String?)`.
- Renders each sibling's `question`/`answer` for a given `clozeIndex`.
- **Validates and is authoritative** (Codex item #9): rejects nested markers, unclosed markers, duplicate indices, zero deletions, and enforces a max deletion count. Malformed markup never reaches persistence.

This one parser serves three consumers: AI output, the manual tap-to-blank editor, and a **future** Anki cloze import path (cloze note types were filtered out in v1.5; this unblocks them later).

### M7.4 Authoring pipeline (Intelligence)

- `@Generable ClozeDraft { var markedText: String; var proposedTags: [String] }`
- `@Generable ClozeResponse { var items: [ClozeDraft] }`
- `ClozeAuthoringService` protocol + `LiveClozeAuthoringService` (streams via `LanguageModelSession`, reuses the `SnapshotAccumulator` pattern from `LiveCardAuthoringService`) + `MockClozeAuthoringService`.
- Flow: AI proposes `markedText` → `ClozeMarkupParser` validates → user edits in the tap-to-blank editor (the editor, not raw AI output, is the source of truth) → on accept, `CardStore.createClozeCards(from: ClozeTemplate, tags:)` fans the template into N sibling `Card`s sharing a fresh `clozeGroupID`.

### M7.5 Sibling burying (persistent, not session-only)

Codex review item #1 (CRITICAL): a session-only in-memory queue filter resurfaces siblings on app relaunch/widget/foreground-reload. Correct design:

- When any sibling card is reviewed, set `clozeBuriedUntil = startOfNextLocalDay` on the *other* not-yet-reviewed due siblings in the same `clozeGroupID`.
- The due-cards query excludes cards whose `clozeBuriedUntil` is in the future.
- `dueAt`/FSRS state is never touched — burying is a separate field, so M8 training data stays clean.
- The due-cards fetch gains a deterministic sort before filtering (the current fetch is unordered).

### M7.6 Anki importer compatibility fix (do now, even though cloze import stays deferred)

Codex review item #8 (HIGH): `AnkiNoteMapper` currently dedups on `sourceSpan = "anki:<noteId>"`. Anki cloze notes produce multiple cards from one note; note-ID-only identity would collapse siblings and silently corrupt imports.

- Change Anki source identity to `anki:<noteId>:<cardOrd>`.
- Explicitly skip Anki cloze note types in the importer with a documented reason (cloze Anki import remains deferred past v2; when enabled, it routes through `ClozeMarkupParser`, not the Basic Q/A path).

### M7.7 File map

**Core (`AnghkooeyCore`):**
- `Persistence/CardType.swift` — `Int`-raw enum.
- `Persistence/AnghkooeySchemaV5.swift` — `Card` with the five new fields.
- `Persistence/AnghkooeyModelContainer.swift` / migration plan — V4→V5 lightweight stage.
- `Cloze/ClozeTemplate.swift` — `ClozeTemplate`, `ClozeDeletion` value types.
- `Cloze/ClozeMarkupParser.swift` — parse + validate + render.
- `Persistence/CardStore.swift` — `createClozeCards(from:tags:)` fan-out; due-cards bury filter + deterministic sort.
- `Import/AnkiNoteMapper.swift` — ordinal-aware source identity + cloze skip.

**Intelligence (`AnghkooeyIntelligence`):**
- `Cloze/ClozeDraft.swift`, `Cloze/ClozeResponse.swift` (`@Generable`).
- `Cloze/ClozeAuthoringService.swift` (protocol), `Cloze/LiveClozeAuthoringService.swift`, `Cloze/MockClozeAuthoringService.swift`.

**UI (`AnghkooeyUI`):**
- `Cloze/ClozeAuthoringView.swift` — generate + tap-to-blank editor + accept→fan-out.
- Q&A / Cloze mode toggle in the existing capture entry point.

**Tests (`App/AnghkooeyTests`):**
- `ClozeMarkupParserTests` (parameterized — parse/validate/render round-trips + malformed-input edge cases).
- `ClozeAuthoringServiceTests` (mock-backed).
- `SchemaMigrationV5Tests`.
- `CloudKitV5SchemaTests` — container builds against V5 (first task).
- `CardStoreClozeTests` — fan-out + persistent sibling burying across simulated sessions.
- `AnkiNoteMapperTests` — ordinal identity + cloze skip.

### M7.8 ADR

**ADR-0003 (Opus-authored, Codex fresh-eyes review):** cloze data model (one scheduled card per deletion, baked `question`/`answer`, group immutability invariant), the marker grammar, and persistent-bury design. Records the rejected alternatives (one-card-all-blanks; render-on-the-fly).

---

## M8 — Personal FSRS optimization

### M8.1 Product behavior

In Settings/stats, the user taps **Optimize my schedule**. If they have fewer than the eligible-sample threshold, they see "not enough review history yet — unlocks at N samples." Otherwise the app runs an on-device optimization with visible progress and shows a before/after summary (baseline vs optimized log-loss, target retention, notable interval changes). The optimized parameters then drive future scheduling.

### M8.2 Training data — `OptimizationDataset` (replay-based)

Codex review item #3 + #6 (HIGH — correctness): the optimizer must **replay card state under the candidate parameters**, not reuse the logged `stabilityBefore`/`difficultyBefore` (those were computed under the *default* `w` and are wrong for a candidate `w`).

- Source: `ReviewLog`, grouped by stable card ID, sorted by `reviewedAt`.
- Each card becomes an ordered sequence of `(elapsedDays, rating, sameDayFlag)`.
- The forward replay (state evolution) happens **inside the loss** under the candidate parameters, starting from empty state.
- **Eligible loss samples** = non-first, non-same-day reviews only (same-day learning steps update state but do not contribute to loss — py-fsrs semantics).
- Per-card sequence length is capped to match py-fsrs.
- `CardStore.optimizationReviewLogs()` — a narrow, batched, projected fetch sorted by `(cardID, reviewedAt)` (Codex item #10 — do not walk full `Card` relationship graphs; this matters once Anki import has created thousands of logs).

### M8.3 Optimizer — `LiveFSRSOptimizer`

- **Loss:** binary cross-entropy between predicted recall (from the existing parity-verified `FSRS6Engine` forward pass — *no second math surface*) and actual pass/fail. BCE inputs clipped to `[1e-7, 1-1e-7]`.
- **Gradients:** central finite differences with per-parameter epsilon scaling (the 21 weights span very different magnitudes).
- **Optimizer:** Adam; parameters clamped to FSRS-6 valid ranges each step.
- **Initial-stability pretraining (`w[0..3]`):** replicate py-fsrs's pretraining of the initial-stability weights before the main descent (these are the hardest to recover from a bad init).
- **Determinism:** fixed seed, deterministic mini-batch shuffle, fixed epoch count — required so the parity harness is reproducible.
- **Instrumentation:** the whole run is wrapped in an `os_signpost` interval. That interval is the `PERFORMANCE.md` measurement.
- Emits `OptimizationResult` (baseline loss, optimized loss, per-weight delta, requested/achieved retention).

**Decision (Codex pushback resolved):** finite-difference gradients are retained rather than porting analytic backprop. Rationale: the loss is computed on *actual* `elapsedDays` (smooth retrievability), not the rounded *scheduled* interval, so interval rounding does not enter the gradient; clamp-boundary zero-gradients affect analytic gradients equally. The genuine risk Codex surfaced is optimizer *semantics* (eligibility filtering, `w[0..3]` pretraining, BCE clipping, epsilon scaling), which ADR-0004 owns. If the py-fsrs parity harness (built **first**) proves finite differences cannot reach tolerance, escalate to analytic gradients — measure before assuming.

### M8.4 Parameter storage & application

- `OptimizedParametersStore` persists one **global** optimized 21-weight `FSRSParameters` (Codable blob).
- Scheduling call site resolves **optimized-or-default**: if eligible-sample count `< threshold` → use `FSRSParameters.default`; else use the stored optimized set.
- `FSRSParameters.default` stays immutable and ADR-0002-pinned. It is never mutated.
- **Threshold (Codex item #5):** gate on **eligible-sample count ≥ 512** (py-fsrs semantics), *not* raw `ReviewLog.count`. The "unlock at N" UI reflects the computed eligible-sample count.

### M8.5 Validation (Definition of Done)

Mirrors the ADR-0002 FSRS parity approach; per `feedback_fixture_parity_over_unit_tests`, parity is part of DoD.

1. **py-fsrs parity harness (built first, before optimizer math).** Codex (Python) generates a fixture: a review-log dataset → py-fsrs-optimized `w` and its baseline/optimized loss. Pin one py-fsrs version (note: scheduler is pinned to `ts-fsrs v5.4.0`; both are FSRS-6 / length-21; the version skew is documented, not assumed away).
2. **Assertion is loss/calibration-based, not exact weights** (Codex item #6): same eligible-sample count, comparable baseline loss, optimized-loss improvement within tolerance. Exact-vector equality is dishonest given init/mini-batch order/local minima.
3. **Convergence on synthetic data:** generate reviews from *known* parameters; assert the optimizer recovers them within a parameter-family tolerance (catches the boundary-degeneracy bug class from `feedback_fixture_parity_over_unit_tests`).
4. **Under-threshold returns default** (gate test).

### M8.6 File map

**Core (`AnghkooeyCore/Scheduling/Optimization/`):**
- `FSRSOptimizer.swift` (protocol), `LiveFSRSOptimizer.swift`, `MockFSRSOptimizer.swift`.
- `OptimizationDataset.swift` (replay-based sample builder).
- `OptimizedParametersStore.swift` (persistence + threshold gate + optimized-or-default resolution).
- `OptimizationResult.swift`.
- `CardStore.swift` — add `optimizationReviewLogs()` projection.

**UI (`AnghkooeyUI/Optimization/`):**
- `OptimizeScheduleView.swift` — trigger, progress, before/after, "unlocks at N" state.

**Tests (`App/AnghkooeyTests`):**
- `FSRSOptimizerParityTests` (vs py-fsrs fixture, loss-based).
- `FSRSOptimizerConvergenceTests` (synthetic known-param recovery).
- `OptimizationDatasetTests` (eligibility filtering, replay correctness, sequence cap).
- `OptimizedParametersStoreTests` (threshold gate, optimized-or-default).

No `AnghkooeyIntelligence` changes — M8 is pure Core math.

### M8.7 ADR

**ADR-0004 (Opus-authored, Codex fresh-eyes review):** numerical (finite-difference) vs analytic gradients with the correctness-over-speed rationale and the escalation trigger; numerical-stability decisions (central differences, per-param epsilon, BCE clipping, clamping); replication of py-fsrs eligibility + `w[0..3]` pretraining semantics; global-parameter scope; eligible-sample threshold; storage; loss-based validation strategy.

---

## Model routing (per-task; concrete Codex role per `feedback_codex_concrete_roles_in_plans`)

| Task | Model | Codex role |
|---|---|---|
| ADR-0003, ADR-0004 | **Opus** | reviewer (fresh eyes) |
| Cloze schema V5 + migration + CloudKit V5 test | Sonnet | none |
| `ClozeMarkupParser` (+ template/render/validate) | Sonnet authors failing parameterized tests + skeleton | **Codex primary impl** (contract-first) |
| Cloze authoring service (`@Generable`, Live/Mock) | Sonnet | reviewer |
| Cloze UI (tap-to-blank editor, mode toggle) | Sonnet | none |
| `CardStore` cloze fan-out + persistent burying | Sonnet | reviewer |
| `AnkiNoteMapper` ordinal identity + cloze skip | Sonnet | none |
| `OptimizationDataset` (replay sample builder) | Sonnet authors failing tests + skeleton | **Codex primary impl** (contract-first) |
| py-fsrs parity fixture generation (Python) | Sonnet orchestrates | **Codex primary impl** |
| `LiveFSRSOptimizer` (gradient/loss/Adam/pretraining) | **Opus** (math-critical) | **Codex fresh-eyes review** |
| `OptimizedParametersStore` + threshold gate | Sonnet | none |
| Optimization UI | Sonnet | none |
| `PERFORMANCE.md` write-up (optimizer trace) | **Opus** | none |
| Milestone exit reviews (M7, M8) | **Opus** | reviewer |

Codex sandbox cannot run `swift build`/`xcodebuild` (`feedback_codex_sandbox`): Codex writes diffs/tests, Claude verifies locally. Codex-as-reviewer can stall on remote API — use a ~10-min timeout with fallback to `ecc:code-reviewer` (`feedback_codex_reviewer_latency`).

---

## Exit gates

**M7:**
- `xcodebuild` build green; all cloze tests pass.
- CloudKit V5 container builds (first-task gate).
- `ClozeMarkupParser` parameterized parse/validate/render round-trips + malformed-input edge cases pass.
- V4→V5 migration test passes.
- Persistent sibling-bury test passes across *simulated relaunch* (not just one in-memory session).
- `AnkiNoteMapper` ordinal-identity + cloze-skip tests pass.
- Device QA: author a passage as cloze → edit a deletion → accept → N sibling cards created → review one → siblings buried until next day (survives app relaunch).
- ADR-0003 merged.
- `foundation.md` §out-of-scope re-check (per `feedback_foundation_recheck_at_milestone_close`); ARCHITECTURE.md appended.

**M8:**
- Build green; optimizer tests pass.
- **py-fsrs parity harness passes (loss-based tolerance), built before optimizer math.**
- Convergence-on-synthetic recovers known params within tolerance.
- Under-threshold returns `FSRSParameters.default` (gate test).
- `PERFORMANCE.md` updated with an `os_signpost`/Instruments trace of a real optimization run on a realistically-sized seeded collection, with time/CPU budget commentary.
- ADR-0004 merged.
- Device QA: seed a ≥-threshold collection → run optimize → before/after summary shown → subsequent scheduling uses optimized params.
- ARCHITECTURE.md appended.

---

## Open items flagged for the implementation plan (not blockers)

- Exact name/shape of the current due-cards/review-queue API the bury filter hooks into — bind during planning.
- Whether a group-level "rebuild siblings" edit is cheap enough to include in M7 or is itself deferred.
- Pinned py-fsrs version for the parity fixture (choose at fixture-build time; document in ADR-0004).
