# Anghkooey — Architecture

> Living document. Each milestone appends a section; earlier sections are not
> edited after they close. Source of truth for structure decisions; rationale
> lives in `docs/DECISIONS/`.

---

## M1 — AnghkooeyCore: Schema + FSRS-6 Engine

**Branch:** `m1/swiftdata-models`  
**Status:** complete (parity gate green, 198 tests pass)  
**ADR:** `docs/DECISIONS/0002-fsrs-reference.md`

### Package topology

```
Anghkooey (app target)
└── AnghkooeyCore  (this milestone)
    ├── Persistence/   — SwiftData @Model classes + schema versioning
    ├── Scheduling/    — FSRS-6 engine + protocol + mock
    └── Logging/       — CoreLog factory (OSLog)
```

`AnghkooeyCore` is a pure-logic SPM package. The build system enforces that it
imports nothing from SwiftUI, UIKit, FoundationModels, or Vision
(`scripts/m1-forbidden-patterns.sh` runs on every PR).

---

### SwiftData schema — v1

Three `@Model final class` types make up schema version `AnghkooeySchemaV1`
(identifier `1.0.0`):

| Model | Role |
|---|---|
| `Card` | The unit of learning. Carries both content (`question`/`answer`) and FSRS scheduling state (`stability`, `difficulty`, `dueAt`, `state`). |
| `ReviewLog` | Immutable audit record of one review event. Pre-review snapshot (`stabilityBefore`, `difficultyBefore`, `stateBefore`) enables replay. |
| `Tag` | User-defined label. Many-to-many with `Card` via `@Relationship`. |

**Relationships:**
- `Card.reviewLogs ↔ ReviewLog.card` — one-to-many, `deleteRule: .cascade`.
  Deleting a card deletes its history.
- `Card.tags ↔ Tag.cards` — many-to-many, `@Relationship(inverse:)` on the
  `Tag` side.

**Case-insensitive tag uniqueness:** `@Attribute(.unique)` on a Swift `String`
cannot model case folding. `Tag` stores both `name` (display, original casing)
and `normalizedName` (`name.lowercased().trimmed`, also `@Attribute(.unique)`).
Insert-time callers must use `Tag.normalize(_:)` to derive the stored form.

**Schema versioning:** `AnghkooeyMigrationPlan` is scaffolded from day one with
empty `stages`. The call-site shape never changes when v2 lands; adding a new
`@Model` property is additive and requires no migration stage in SwiftData.

**Test container:** `AnghkooeyModelContainer.makeInMemoryContainer()` builds a
`ModelContainer` backed by `isStoredInMemoryOnly: true`. All downstream tests
call this; no test writes to a real on-disk store.

---

### FSRS-6 engine

#### Reference implementation

The Swift port is derived from **`ts-fsrs v5.4.0`** pinned at commit
`80bab011a7f496b06c99924d54e772cf258244f2` (see ADR-0002). That SHA is the
single oracle for:

- The 21-element default weight vector (`FSRSParameters.default`)
- All mathematical formulas (forgetting curve, stability updates, interval
  computation)
- The parity test fixture set (`Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/Fixtures/fsrs6-parity.json`)

Changing any default constant or formula without regenerating the fixtures and
updating ADR-0002 is a parity-harness breaker.

#### Type surface

| Type | Kind | Role |
|---|---|---|
| `FSRS6Engine` | `protocol` | Single-method contract: `next(card:rating:now:) throws -> SchedulerOutput` |
| `FSRSParameters` | `struct` | 21-weight vector + retention/interval/fuzz/short-term flags. `FSRSParameters.default` is pinned by ADR-0002. |
| `SchedulingCard` | `struct` | In-memory snapshot of a card's scheduling state. Decoupled from the `Card` SwiftData model so the engine stays a pure function. |
| `SchedulerOutput` | `struct` | `(card: SchedulingCard, log: ReviewLogEntry)` returned atomically so persistence can write both rows in one transaction. |
| `ReviewLogEntry` | `struct` | Pre-review snapshot captured inside `next(...)`. Field names mirror `ReviewLog` for a zero-rename mapping at the persistence boundary. |
| `CardState` | `enum` | `.new / .learning / .review / .relearning` — Int raws pinned for migration safety. |
| `Rating` | `enum` | `.again=1 / .hard=2 / .good=3 / .easy=4` — FSRS spec raw values, pinned. |
| `LiveFSRS6Engine` | `struct` | Production FSRS-6 port. |
| `MockFSRS6Engine` | `struct` | Deterministic placeholder with a pinned contract. Used by downstream packages that need a scheduler-shaped collaborator without FSRS-6 fidelity. |
| `SchedulingError` | `enum` | Input-validation errors (`reviewedBeforeLastReview`, `invalidNewCardSnapshot`, `unsupportedParameterLength`). |

#### Short-term vs long-term scheduler

FSRS-6 has two scheduler modes controlled by `FSRSParameters.enableShortTerm`:

**Short-term (default, `enableShortTerm == true`):**  
New and learning cards progress through the step machine (`learningStepsSeconds`
/ `relearningStepsSeconds`). Within a single calendar day (`elapsedDays == 0`),
the stability update short-circuits to `nextShortTermStability` — a grade-boosted
formula that does not use the forgetting curve (retrievability = 1 at elapsed=0).  
The review-state hard/good/easy interval triple mirrors this: at `elapsed == 0`,
each grade's stability comes from `nextShortTermStability` rather than
`nextRecallStability` (this was the T4 math bug closed in commit `3fae069`).

**Long-term (`enableShortTerm == false`):**  
Not specialised in this milestone. Callers passing this flag get the basic
dispatch with no step-machine entries. The default parameter set (ADR-0002)
uses short-term, so parity is unaffected. A dedicated long-term path can land
without API change.

#### Data-flow through `next(...)`

```
caller
  │  SchedulingCard + Rating + Date
  ▼
LiveFSRS6Engine.next(card:rating:now:)
  │
  ├─ validate (w.count == 21, now ≥ lastReview, new-card invariant)
  ├─ compute elapsedDays (UTC calendar-day diff via dateDiffInUTCDays)
  ├─ build ReviewLogEntry (pre-review snapshot)
  │
  ├─ .new / .learning / .relearning ──▶ nextMemoryState → applyLearningSteps
  │                                        (step machine: due within 24 h → stay
  │                                         in state; else graduate to .review)
  │
  └─ .review
       ├─ .again ──▶ nextForgetStability → applyLearningSteps (relearning)
       │                                    + lapses += 1
       └─ .hard/.good/.easy
            ├─ compute hard/good/easy stability triple
            │   (short-term branch at elapsed==0; recall branch otherwise)
            ├─ nextInterval for each
            ├─ enforce hard ≤ good < easy monotonicity
            └─ pick interval for chosen rating
  │
  ▼
SchedulerOutput(card: updated SchedulingCard, log: ReviewLogEntry)
```

---

### Parameter set — ADR-0002

`FSRSParameters.default` encodes the 21-weight FSRS-6 vector from the pinned
`ts-fsrs` commit. Key scalar values:

| Parameter | Value | Meaning |
|---|---|---|
| `requestRetention` | `0.9` | Target recall probability at due date |
| `maximumInterval` | `36 500` days | Hard cap (~100 years) |
| `enableFuzz` | `false` | Deterministic for parity |
| `enableShortTerm` | `true` | Short-term step machine active |
| `learningStepsSeconds` | `[60, 600]` | 1 min → 10 min |
| `relearningStepsSeconds` | `[600]` | 10 min |
| `w[20]` (decay) | `0.1542` | FSRS-6 forgetting-curve decay constant |

---

### Test strategy

| Layer | Framework | Count |
|---|---|---|
| Persistence | Swift Testing | 7 (`PersistenceTests`) |
| Scheduling contract | Swift Testing | 18 (`SchedulingContractTests`) |
| FSRS-6 unit | Swift Testing | 48 (`FSRSAlgorithmTests`) |
| Parity harness | Swift Testing, parameterised | 150 fixtures (`FSRS6ParityTests`) |
| **Total** | | **223** |

**Parameterised parity harness** (`FSRS6ParityTests`): `@Test(arguments:)` over
150 JSON fixtures generated from the pinned `ts-fsrs` reference. Each fixture
encodes a `(card_input, rating, now)` triple and the expected `(stability,
difficulty, state, interval, due)` outputs. Tolerances: `ε = 1e-9` for
`Double` fields; exact equality for integer intervals and `CardState`. The
harness is a build-breaking gate — divergence fails CI.

**Swift Testing is primary.** XCTest is reserved for UI-layer tests (none yet
in this milestone). Parameterised tests (`@Test(arguments:)`) are used wherever
fixture-driven coverage is meaningful, closing the iOS skill gap flagged in
`ios-skill-map-2026.md` §Phase 2 item 5.

**In-memory container** (`AnghkooeyModelContainer.makeInMemoryContainer()`)
is used by all persistence tests. No test touches a real on-disk store.

---

## M2 — AnghkooeyIntelligence: Card Authoring + OCR

**Branch:** `m2/foundation-models`
**Status:** complete
**Spec:** `docs/superpowers/plans/2026-05-21-m2-intelligence.md`

### Package topology addition

```
Anghkooey (app target)
├── AnghkooeyCore      (M1 — schema + FSRS-6)
└── AnghkooeyIntelligence  (M2)
    ├── Authoring/     — CardDraft, AuthorResponse, CardAuthoringService, LiveCardAuthoringService, MockCardAuthoringService, SnapshotAccumulator
    ├── OCR/           — OCRService, LiveOCRService (Vision), MockOCRService
    ├── Eval/          — EvalFixture, RubricScorer
    └── Logging/       — IntelligenceLog
```

`AnghkooeyIntelligence` imports `AnghkooeyCore` for logging patterns only. No SwiftData, SwiftUI, or UIKit imports enforced by `scripts/m1-forbidden-patterns.sh`.

### Card authoring data flow

Text passage → `CardAuthoringService.generateDrafts(from:)` → `AsyncThrowingStream<CardDraft, Error>`. The live implementation calls `LanguageModelSession.streamResponse(to:generating:)` and routes each `ResponseStream<AuthorResponse>.Snapshot` through `SnapshotAccumulator`, which emits `CardDraft` values as each array slot reaches both `question` and `answer` non-empty. One emission per array index; later refinements discarded.

FoundationModels API verified against `arm64-apple-ios-simulator.swiftinterface`: `snapshot.content.drafts` yields `[CardDraft.PartiallyGenerated]` with all fields Optional.

### Eval harness

Two modes:
- **CI mode** — `swift test` / xcodebuild runs `EvalFixtureGateTests`: `@Test(arguments:)` over `eval-fixtures.json` golden drafts; scores each card against 4 binary rubric criteria (atomic, specific, groundedness, Q≠A); fails build if any card fails. Zero model calls.
- **Live mode** — `make eval` (from repo root) runs the `EvalRunner` executable on macOS 26 with the real model; prints per-input verdicts; `make eval-update` overwrites golden fixtures only if pass rate ≥ 80%.

### Module seam

`CardDraft` is the output type of `AnghkooeyIntelligence`. `Card(from: CardDraft)` conversion is an `AnghkooeyUI` responsibility (M3), co-located with the user-confirmation ViewModel.
