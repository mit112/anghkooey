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

---

## M3 — Capture Pipeline: Share Extension + Inbox + Camera

**Branch:** `m3/capture-share-extension`
**Status:** code complete (M3.10 baselines pending device run)
**Spec:** `docs/superpowers/plans/2026-05-21-m3-capture.md`
**ADR:** `docs/DECISIONS/0003-app-group-inbox.md`

### Capture topology

```
Anghkooey.xcodeproj
├── Anghkooey                    (app target — SwiftUI scene + AppState)
│   └── AVCaptureSession         (Camera/CameraView; MockCaptureSession in sim)
└── AnghkooeyShare               (Share Extension — UIKit ShareViewController)

Packages/AnghkooeyCore/Inbox/
├── InboxConstants.swift         (App Group ID, dir layout, limits, schema v1)
├── InboxItem.swift              (Codable; .text or .imageRef)
├── InboxWriter.swift            (actor; SHA-256 dedup, atomic rename, Darwin post)
├── InboxDrainer.swift           (actor; sorts by capturedAt, OCRs imageRefs, evicts orphans)
└── InboxNotifier.swift          (CFNotificationCenter Darwin observer)
```

### Cross-process inbox protocol

Share Extension and main app share an App Group container; the inbox lives at
`<container>/inbox/*.json` (text + image-ref descriptors) and
`<container>/inbox/images/*.heic`. The extension writes atomically (`*.json.tmp`
→ rename), then posts a Darwin notification. The main app drains on launch, on
foreground (`scenePhase == .active`), and on Darwin notification — all routed
through `InboxDrainer.drain()`, which is actor-serialised so concurrent
triggers coalesce via a plain `isDraining` guard (no repeat-loop).

`OCRServiceProtocol` lives in `AnghkooeyIntelligence`; `InboxDrainer` accepts
any conforming implementation. The app composition root wires the live
`LiveOCRServiceDataAdapter` (Data → CGImage bridge over M2's `LiveOCRService`).
Drainer tests inject `MockOCRService`.

### Sheet queue + delegate bridge

`AppState` (`@MainActor @Observable`) owns the drainer, a `DrainerBridge`
relay (private final class implementing `InboxDrainerDelegate`, weak-references
AppState), and a single `pendingCards: [CardDraft]` queue. Drained text →
`enqueue` → `advanceQueue` sets `presentedCard`, SwiftUI binds the sheet.
Accept and Skip both call `advanceQueue` to drain the queue one card at a
time. `Card(from:)` materialisation is M4's job.

### Latency instrumentation (M3.10)

`CoreLog.poiSignposter` returns an `OSSignposter` on category
`"PointsOfInterest"` using the host bundle ID as subsystem — shared between
the extension and the app processes so Instruments groups all three intervals
on the same Points of Interest track:

| Interval                       | Begin                                                | End                                                  |
|--------------------------------|------------------------------------------------------|------------------------------------------------------|
| `share-tap-to-inbox-write`     | `ShareViewController.processSharedContent` entry     | scope exit (after `InboxWriter.write` returns)       |
| `inbox-drain`                  | `InboxDrainer.drain()` (after isDraining guard)      | scope exit of `drain()`                              |
| `card-review-sheet-ready`      | `AppState.advanceQueue()` when `presentedCard` set   | `CardReviewSheet.onAppear → cardReviewSheetDidAppear` |

Median share-tap → review-sheet baseline is captured into `PERFORMANCE.md` on
a physical device (the share sheet and OCR latency do not represent on
simulator). M5 does the full perf write-up.

### Privacy

`App/AnghkooeyShare/PrivacyInfo.xcprivacy` declares
`NSPrivacyAccessedAPICategoryFileTimestamp` with reason code `DDA9.1` for the
extension's inbox file I/O. The main app's existing `PrivacyInfo.xcprivacy`
covers Vision/OCR. `CFNotificationCenter` Darwin is not a required-reason API.

---

## M4 — Review Loop

**Branch:** `m4/review-loop`  
**Status:** complete

### Package topology

```
Anghkooey (app target)
├── AnghkooeyCore          — CardStore actor, Card.Snapshot, ReviewGrade
│   └── Persistence/       — CardStore, CardNotifications
│   └── Scheduling/        — ReviewGrade (FSRS-6 Rating bridge)
├── AnghkooeyIntelligence  — CardAuthoringService.author(from:) convenience
└── AnghkooeyUI            — ReviewSession, ReviewView, ReviewScreen
    └── Review/
```

### Data flow

```
[InboxDrainer]
     │ resolvedText
     ▼
AppState.enqueue(resolvedText:) async            — App target
     │ CardAuthoringService.author(from:)
     ▼
IdentifiedDraft ──────────────────────────────► AnghkooeyIntelligence.CardDraft
     │ sheet(item:)
     ▼
CardReviewSheet (Accept / Skip)
     │ onAccept: AppState.acceptDraft()
     │           → CardStore.create(question:answer:sourceSpan:now:)
     │           → Notification.anghkooeyCardAccepted
     ▼
ReviewScreen.onReceive(.anghkooeyCardAccepted)
     │ session.loadDueQueue()
     ▼
ReviewSession (AnghkooeyUI)
     │ currentCard: Card.Snapshot
     ▼
ReviewView: question → "Show Answer" → Got it / Missed it
     │ session.submit(grade:)
     │ LiveFSRS6Engine.next(card:rating:now:)
     ▼
CardStore.apply(output, to: cardID, grade:, now:)
     │ Card updated + ReviewLog appended
     ▼
session.advanceQueue() → next card or .empty
```

### Module seams

| Boundary | Payload | Direction |
|----------|---------|-----------|
| App → AnghkooeyCore | `CardStore.create(question:answer:sourceSpan:now:)` | App → Core |
| App → AnghkooeyUI | `ReviewScreen(store:)` + `Notification.anghkooeyCardAccepted` | App → UI |
| AnghkooeyUI → AnghkooeyCore | `CardStoreProtocol`, `FSRS6Engine`, `ReviewGrade` | UI → Core |
| AnghkooeyIntelligence → App | `IdentifiedDraft(draft: CardDraft)` | Intelligence → App |

### Card.Snapshot pattern

`Card` is a SwiftData `@Model` class and is not `Sendable`. `CardStore` is an
actor. To avoid escaping SwiftData objects across actor boundaries, `CardStore`
converts all `Card` instances to `Card.Snapshot` (a `Sendable` struct) before
returning them. Callers hold snapshots only; they pass the card's `UUID` back to
`CardStore.apply(_:to:)` when submitting a grade. This pattern keeps SwiftData's
single-context requirement contained within the actor and makes the CloudKit
migration (M5+) trivial — the actor's ModelContext swaps; callers don't change.

### M4 schema note

`reps`, `lapses`, `learningSteps`, `scheduledDays`, `elapsedDays` are not stored
in the M4 `Card` model. `Card.Snapshot.schedulingCard` defaults these to 0.
Cards in `.review` state have correct `stability`/`difficulty`/`due`; only the
step-machine position is lost across restarts. Acceptable for v1 single-user
flow. M5 extends the schema.

### Out-of-scope in M4

Tags, decks, statistics, WidgetKit, CloudKit sync, card editing before accept,
4-button grading, audio/image cards.

## M5 — Polish

### M5.A — Schema V2 (step-machine persistence)

Introduced `AnghkooeySchemaV2.Card` adding `reps`, `lapses`, `learningSteps`,
`scheduledDays`, `elapsedDays` as optional (`Int?` / `Double?`) columns. Optional
types are required for lightweight V1 → V2 migration: SwiftData's `.lightweight`
stage leaves new columns NULL for V1-era rows; nullable avoids Core Data's
non-optional validation error on migrated rows.

Migration from V1 is `MigrationStage.lightweight`. Downstream code references
the top-level `public typealias Card = AnghkooeySchemaV2.Card`; future
migrations swap the alias and add a stage without rippling through call sites.

`Card.Snapshot` exposes non-optional `Int` / `Double` for all five fields (via
`?? 0`), so callers and tests are unchanged. `Card.Snapshot.schedulingCard` no
longer zero-fills step-machine state, closing the M4 carry-over noted above.
`CardStore.apply` and `MockCardStore.apply` persist the new fields from
`SchedulerOutput`.

### M5.0 — Verification: production bug in accept flow

Sim verification (2026-05-22) revealed `AppState.acceptDraft()` advanced the
sheet queue and posted `.anghkooeyCardAccepted` without ever calling
`cardStore.create()`. Every accepted draft was silently dropped; the SwiftData
store stayed empty. Fix: capture `presentedDraft` before `advanceQueue()`, then
`Task { try? await cardStore.create(...) }`. Commit `4345f0c`.

### M5.B — Performance instrumentation (Lane B)

Added two `OSSignposter` intervals on category `"PointsOfInterest"`:

- **`review-tap`** (`ReviewSession.submit`) — wraps FSRS scheduling math +
  `CardStore.apply` (`ModelContext.save`) + queue-advance state mutation.
  Measures full tap-to-next-card latency. Implementation: `import OSLog` +
  `CoreLog.poiSignposter.beginInterval`/`defer endInterval` at top of `submit`.

- **`ai-draft-generation`** (`LiveCardAuthoringService.generateDrafts`) — wraps
  the inner `Task` from generation start to `continuation.finish()`. Measures
  full FoundationModels on-device generation time. Uses `IntelligenceLog.poiSignposter`
  (same `"PointsOfInterest"` category, same subsystem at runtime → same Instruments
  track as Core's intervals).

`IntelligenceLog` gains a `poiSignposter: OSSignposter` computed property matching
`CoreLog.poiSignposter`'s category.

`MetricsReceiver` (`NSObject`/`MXMetricManagerSubscriber`) added to app target.
Registered via `MXMetricManager.shared.add(metricsReceiver)` in `AnghkooeyApp.init()`.
Logs `MXMetricPayload` and `MXDiagnosticPayload` JSON to OSLog category `"MetricKit"`.
First payload delivered ~24 hours after first real-device run.

PERFORMANCE.md instrumentation table now has 5 intervals. M5 baseline section
(measured numbers + Instruments screenshot) pending one Instruments run + Opus
prose session.

### M5.C — Privacy manifest audit + App Store metadata

Required-reason API audit (2026-05-22):

| API category | Target | Reason | Source |
|---|---|---|---|
| `NSPrivacyAccessedAPICategoryFileTimestamp` | Anghkooey (main app) | `3B52.1` | `InboxDrainer` reads `contentModificationDateKey` and `attributesOfItem` on app-managed inbox files |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | AnghkooeyShare (ext) | `DDA9.1` | `InboxWriter` checks inbox for existing items received from other apps via Share Sheet |

No other required-reason APIs are used in production code (no disk space, no system
boot time, no active keyboard, no UserDefaults access).

`App/Anghkooey/PrivacyInfo.xcprivacy` updated: was an empty array; now declares
`FileTimestamp/3B52.1` plus the required top-level keys (`NSPrivacyTracking: false`,
`NSPrivacyCollectedDataTypes: []`). `AnghkooeyShare/PrivacyInfo.xcprivacy` was
already correct.

Required-reason table added to `README.md`. App Store metadata draft at
`docs/STORE/metadata.md` (description, keywords, screenshot plan, submission checklist).

### M5.D — UX polish + eval harness

- **Haptics.** `ReviewView` grade buttons use `.sensoryFeedback(.success, trigger:)`
  and `.sensoryFeedback(.error, trigger:)` driven by `@State` boolean toggles
  (`gotItTrigger` / `missedItTrigger`). Boolean-toggle triggers are the SwiftUI
  idiomatic shape — value-equality, no per-event identity to manage.
- **Empty state.** Review tab empty state copy is now "All caught up" with
  `checkmark.circle.fill`. Implies completion rather than absence (the M4 copy
  read like a bug to first-time users).
- **Eval harness.** `EvalRunner` SwiftPM executable in `AnghkooeyIntelligence`
  with three pinned fixtures (biology / vocabulary / history). Pass threshold
  80%. Run script + golden-update flag documented in `docs/EVALS/m5-eval-run.md`.
  Requires Apple Intelligence; first run deferred to device.

### M5.E — Resilience

- **Offline fallback path.** `AppState.enqueue`'s `catch` block already converted
  any `AuthoringError` to a fallback `CardDraft(question: <captured text>,
  answer: "(edit to add answer)")`. Lane E adds
  `enqueue_onModelUnavailable_queuesFallbackDraft` to lock this — the test
  asserts the fallback shape on `AuthoringError.unavailable`, the airplane-mode
  failure mode.
- **Soak / hang monitoring.** `MetricsReceiver` from M5.B already logs
  `MXHangDiagnosticPayload` to OSLog (`MetricKit` category). No additional code
  needed for E2; the 30-min soak result is captured by reading the Console
  payload ~24 h after a device run. Hang budget: 0 hangs >250 ms during review
  tab interaction.
- **Manual verification checklist.** `docs/EVALS/resilience-checklist.md`
  enumerates the device steps for E1 (airplane mode), E2 (30-min soak), and E3
  (lower-tier device — iPhone SE / 15 fallback path). All three require
  hardware not present in the current environment; checklist is the artifact.

### M5 closeout status

Code-complete. Physical-device verification deferred for: real Instruments
trace + numbers (replacing the code-analysis estimates in `PERFORMANCE.md`),
30-min soak, airplane-mode manual run, lower-tier device run, and eval-harness
first-run. Each item has a reproducible procedure in `PERFORMANCE.md`,
`docs/EVALS/resilience-checklist.md`, or `docs/EVALS/m5-eval-run.md`. These are
intentionally not blocking the M5 PR — they're TestFlight-window work.

148 tests green at M5 close: 94 Core, 39 Intelligence, 7 UI, 8 app-target.

## M5.5 — V1 Feature Completion

### M5.5C — Cushion Mode + Freeze

Two grace features from `foundation.md §4`.

**Cushion Mode** lives entirely inside `ReviewSession`. `loadDueQueue()` fetches
all due cards, exposes `backlogTotal` for honest UI copy, and — when
`backlogTotal > backlogThreshold && backlogTotal > dailyBatchCap` — caps the
working queue to `dailyBatchCap` (defaults: 20 and 50, both injectable via
`init` for tests). `isCushionActive` is the boolean the UI uses to show the
"Showing today's batch — N of M due" banner. This is a queue-shaping decision,
not a scheduler change — FSRS-6 still sees the true card state. The veil is
honest by design (per foundation: "be honest about that internally and
externally").

**Freeze** is a user-toggled "I'm away" state. `FreezeController`
(`@Observable` `@MainActor`) records `frozenSince` via a `FreezeStorage` seam
(production: `UserDefaultsFreezeStorage`; tests: `InMemoryFreezeStorage`). On
`unfreeze(now:)`, elapsed days = `floor((now - frozenSince) / 86_400)`; the
controller calls `CardStore.shiftAllDueDates(byDays:)` which iterates every
card in a single SwiftData transaction and adds `days * 86_400` seconds to
each `dueAt`. Same-day unfreeze is a no-op (0 days). Negative shift is rejected
with `PersistenceError.invalidShift`.

`CardStoreProtocol` gains `shiftAllDueDates(byDays:)` and `allCards()` (the
latter also serves the Library surface in Lane T). The Settings tab hosts the
Freeze toggle plus read-only Cushion thresholds.

148 + 8 = 156 tests at lane close (3 Cushion + 3 CardStore shift + 5
FreezeController tests added; ReviewSession constructor change forced no
existing-test edits because all tests use default cap/threshold values).

### M5.5G — 4-grade rating system

Replaces the 2-button "Got it / Missed it" UI with the full FSRS-6 four-grade
rating: **Again / Hard / Good / Easy**.

`ReviewGrade` (in `AnghkooeyCore/Scheduling/`) was the only change point.
`Rating` already had 4 cases; `CardStore.apply(grade:)` already accepted
`Rating` directly — no persistence layer change was needed. The migration
strategy used `@available(*, deprecated, renamed:)` shims (`missed → .again`,
`gotIt → .good`) so the build stayed green while call sites were updated
incrementally; shims were deleted at lane close.

`ReviewSession.submit(grade: ReviewGrade)` was unchanged — the new
`fsrsRating` computed property on the expanded enum routes all 4 cases to their
FSRS counterparts. `MockFSRS6Engine` already handled all 4 `Rating` cases and
records `output.log.rating = rating`, so new tests for `.hard` and `.easy`
routes needed no mock changes.

`ReviewView` replaced the 2-button `HStack` with a 2×2 `VStack(HStack, HStack)`
grid. Tint mapping: Again = `.red`, Hard = `.orange`, Good = default
(`.borderedProminent`), Easy = `.blue` (`.borderedProminent`). Sensory feedback:
`.error` for Again, `.impact(weight: .medium)` for Hard, `.success` for
Good/Easy.

156 → 99 Core tests after lane close (net +2: 5 new ReviewGrade mapping tests
replaced 3 old 2-case tests; `ReviewSessionTests` grew from 4 to 6 tests
covering all 4 grade routes plus retained empty-state and idempotency tests).

---

## M5.5S — Swipe-to-grade + Edit-before-accept

**Branch:** `main`
**Status:** complete
**Plan:** `docs/superpowers/plans/2026-05-22-m5.5s-swipe-and-edit.md`

### What changed

**`CardStore.update(id:question:answer:)`** — new protocol method + `CardStore` actor impl + `MockCardStore` stub. Updates only `question`, `answer`, and `updatedAt`; FSRS fields are untouched. Rollback on save failure guards against dirty context leaking into subsequent saves. Tested in `CardStoreUpdateTests.swift` (6 Swift Testing tests).

**`ReviewSession.submitEdit(question:answer:)`** — calls `store.update`, refreshes the in-memory `currentCard` snapshot so `ReviewView` reflects edits immediately. Non-fatal on error.

**Swipe gesture layer in `ReviewView`** — `DragGesture(minimumDistance: 20)` with `simultaneousGesture` on the reviewing body VStack. Mapping: left→Again, right→Good, up→Easy, down→edit sheet. Visual feedback: colour-tinted overlay (red/green/blue/grey) + card tilt/offset during drag. Haptic feedback reuses existing `sensoryFeedback` triggers.

Three hardening constraints applied after Codex review:
- **Diagonal dead zone:** `abs(dx) > abs(dy) * 1.5 || abs(dy) > abs(dx) * 1.5` required before any action fires — prevents near-45° ambiguity.
- **Velocity guard:** `abs(velocity) >= 100 pt/s` — distinguishes deliberate swipe from a slow content scroll activating the outer gesture via `simultaneousGesture`.
- **Left-edge exclusion:** `startLocation.x > 20` — prevents iOS system back-swipe from triggering `.good`.

**`CardEditSheet`** — private SwiftUI struct at the bottom of `ReviewView.swift`. Two `TextEditor` fields initialised from the current card snapshot; Save calls `session.submitEdit`; Cancel dismisses without saving.

**`CardReviewSheet` edit-before-accept** — question/answer `Text` views promoted to `TextEditor` fields. `onAccept` signature changed to `(String, String) -> Void`. `AppState.acceptDraft(question:answer:)` added; zero-arg `acceptDraft()` shim delegates to it so existing tests compile unchanged.

### Invariants

- `CardStore.update` only touches `question`, `answer`, `updatedAt`; all FSRS fields remain from the last `apply(...)` call.
- Swipe grades are guarded behind `session.isAnswerRevealed`; down-swipe (edit) fires regardless of reveal state.
- No tags in the Lane S edit sheet — `Card.Snapshot` gains a `tags` field in Lane T; the `update` signature is extended there.

### Test count after lane close

105 Core tests (18 suites) — net +6 from `CardStoreUpdateTests`. 13 app-target tests unchanged.

## M5.5T — Tags UI + Library Surface

**Date:** 2026-05-22

### What shipped
- `Card.Snapshot.tags: [String]` — populated from the existing `Card.tags: [Tag]` SwiftData relationship. No schema migration was needed; tags were already in V1/V2. The snapshot projects tag names as a sorted `[String]` array. `Card.Snapshot` now also conforms to `Identifiable` (needed by `LibraryView`'s sheet binding).
- `CardStoreProtocol.create(question:answer:sourceSpan:tags:now:)` — new required method. A protocol extension provides the no-tags variant for all existing call sites (backward-compat, no churn).
- `CardStoreProtocol.update(id:question:answer:tags:)` — replaces the Q/A-only variant. Callers must pass explicit `tags:`; no backward-compat extension is provided to prevent silently clearing tags at unmigrated call sites.
- `CardStore.findOrCreateTags(_:)` — private actor method; case-insensitive dedup via `Tag.normalizedName`. V1 does not garbage-collect orphaned tags.
- **Rollback fix:** `CardStore.apply` and `CardStore.shiftAllDueDates` now call `modelContext.rollback()` before rethrowing a save failure (parity with `update`, per Lane S note).
- `TagEditorView` — internal SwiftUI struct in `AnghkooeyUI/Shared`; horizontal chip row + add-tag text field. Shared by `CardEditSheet` (review loop) and `LibraryCardEditView`.
- `LibraryView` — public view in `AnghkooeyUI/Library`; loads all cards via `store.allCards()`, tag filter chips, tap-to-edit.
- `LibraryCardEditView` — public view; edits Q/A/tags directly via `store.update`; `onSave` callback reloads parent.
- Library tab added to `ContentView` (4th tab, `books.vertical` icon).
- `AppState.acceptDraft` now passes `draft.proposedTags` to `cardStore.create` — AI-proposed tags are honored on accept.

### Design decisions
- **`[String]` not `[Tag]` in Snapshot** — `Card.Snapshot` is a `Sendable` value type crossing actor boundaries. SwiftData `@Model` objects are reference types bound to their `ModelContext`; they cannot safely escape the actor. Tags are projected as sorted display names.
- **No orphan cleanup** — Tag rows no longer referenced by any card are kept. The tag table is small in v1; a cleanup sweep is deferred to v2.
- **Backward-compat extension for `create`, not for `update`** — A `create` shim with `tags: []` is safe (new card starts untagged). An `update` shim with `tags: []` would silently clear existing tags at every unmigrated call site; omitting it forces the compiler to catch them.

---

## M5.5M — Mnemonic Button

**Date:** 2026-05-22

### What shipped

**`AnghkooeySchemaV3`** — new `mnemonic: String?` column on `Card`. `AnghkooeyMigrationPlan` extended to three schemas / two stages; both V1→V2 and V2→V3 are lightweight. `AnghkooeyModelContainer.makeInMemoryContainer()` updated to V3. All V2-era rows receive `NULL` for `mnemonic` on first open. `CardStoreTests` and `SchemaMigrationTests` updated to use V3 schema refs (they had stale V1 container creation that caused a fatal cast with V3.Card).

**`Card.Snapshot.mnemonic: String?`** — projects the stored value across the actor boundary. All `MockCardStore` snapshot-reconstruction sites (`apply`, `shiftAllDueDates`, `update`) pass `mnemonic: old.mnemonic` to preserve the field through in-memory operations.

**`CardStoreProtocol.updateMnemonic(id:mnemonic:)`** — new protocol method in `AnghkooeyCore`. Silent no-op for unknown ids. Rollback on save failure. Implemented in `CardStore` actor and `MockCardStore`.

**`MnemonicService` protocol + `LiveMnemonicService`** in `AnghkooeyIntelligence`. `LiveMnemonicService` calls `LanguageModelSession(instructions:).streamResponse(to:generating:MnemonicResponse.self)` and collects the final `snapshot.content.mnemonic` value after the stream ends. `@Generable MnemonicResponse { var mnemonic: String }` is the structured output type. `MockMnemonicService` returns a fixed string or throws a configured error.

**`ReviewSession`** (in `AnghkooeyUI`) gains `mnemonicService: (any MnemonicService)?` (default nil, backward-compatible init), `currentMnemonic: String?`, `isMnemonicLoading: Bool`, and `isMnemonicAvailable: Bool`. `loadDueQueue` seeds `currentMnemonic` from `currentCard?.mnemonic`. `submit(grade:)` resets it to the next card's stored mnemonic (from the queue snapshot) or nil on empty. `generateMnemonic()` calls the service, sets `currentMnemonic`, then persists via `store.updateMnemonic` (non-fatal on error).

**`ReviewView`** `mnemonicSection` — shown only when `isAnswerRevealed`. Three states: button ("Generate Mnemonic", `.purple` tint) → loading HStack → italic mnemonic text. Wired below `answerSection` in the scroll content.

### Invariants

- `AnghkooeyCore` has no import of `AnghkooeyIntelligence`. `MnemonicService` protocol and `LiveMnemonicService` live in Intelligence; `CardStoreProtocol.updateMnemonic` lives in Core.
- Mnemonic generation is fully optional: `ReviewSession` without an injected `MnemonicService` never shows the button (`isMnemonicAvailable == false`).
- Generation failures are non-fatal: the button remains visible for retry; `currentMnemonic` stays nil.
- The mnemonic persists across sessions: on next `loadDueQueue`, `currentMnemonic` is seeded from the stored `Card.Snapshot.mnemonic`.
- `make generate` drops xcprivacy from PBXResourcesBuildPhase (xcodegen fragility) — now handled automatically (#56): `make generate` runs `scripts/patch_privacy_info.py` (also wired as a `postGenCommand`), which re-adds all three targets' entries (app/share/widget → 12 PrivacyInfo lines total), and `scripts/ci.sh` fails if any are missing. No manual patch step; do not re-apply it by hand.

### Test counts after lane close

- Core: 120 tests in 20 suites (was 112; +8 from `CardStoreMnemonicTests`)
- Intelligence: +4 from `MockMnemonicServiceTests` (run via `swift test` in package dir)
- App target: 21 tests in 4 suites (was 13; +8 from `ReviewSessionMnemonicTests`)

---

## v1.1 Lane K — Cumulative LTM Metric

**Date:** 2026-05-27
**Status:** complete

`LTMConfig` (AnghkooeyCore/Scheduling) defines a stability-threshold metric:
a card counts as "committed to long-term memory" once FSRS-6 `stability >= 21`
days. `CardStore.longTermMemoryCount(thresholdDays:)` uses a `fetchCount`
predicate; the protocol default reduces over `allCards()`. `ReviewSession.ltmCount`
loads alongside the due queue; `ReviewView` shows "N committed to long-term
memory". Independent of due date and Cushion Mode — by design, it never shrinks
on a missed day. (foundation §3 principle 3.)

---

## v1.1 Lane A — Ambient Clipboard Capture

**Date:** 2026-05-27
**Status:** complete

`ClipboardCaptureCoordinator` (`@Observable @MainActor`) inspects `UIPasteboard.general.string`
on every app foreground. Text ≥ 20 chars whose SHA-256 hash (trimmed+lowercased) is not in
a `UserDefaults`-backed FIFO ring (capacity 50) surfaces a `pendingOffer`. `ClipboardBanner`
renders a non-intrusive `.safeAreaInset` banner. Accepting routes the text through
`AppState.enqueue(resolvedText:)` — the same path as Share Sheet / OCR. Never auto-inserts
cards. Dismiss or accept marks the hash offered. `InMemoryOfferStore` allows pure-Swift
test isolation without touching `UserDefaults`.

---

## v1.1 Lane I — AppIntents + Siri Capture

**Date:** 2026-05-27
**Status:** complete

`AddToAnghkooeyIntent` (AppIntents) accepts a text parameter, writes it via
`InboxWriter.write(text:sourceApp:"siri")` to the shared App Group inbox
(`group.com.mitsheth.anghkooey`). On next foreground, the existing `InboxDrainer`
authors flashcard drafts from it — identical to the Share Sheet path. No new
entitlements required (App Group already present). `AnghkooeyShortcuts`
(`AppShortcutsProvider`) donates 4 phrases including `\(.applicationName)` to
Siri/Spotlight. Closes 2026 iOS skill gap #2 (AppIntents + Siri/Spotlight donation).
All `static var` protocol witnesses use `nonisolated(unsafe)` for Swift 6
strict-concurrency compliance.

---

## v1.1 Lane W — WidgetKit Interactive Review Widget

**Date:** 2026-05-28
**Status:** complete (device QA pending — see exit gate)

`AnghkooeyWidget` (app-extension target) shows the most-due card and two
interactive `Button(intent:)` controls ("Again" / "Good") using the iOS 17+
interactive widget API. The widget never touches SwiftData; it reads
`widget/due-snapshot.json` via `WidgetBridge` and appends grade decisions to
`widget/grades.jsonl`. On app foreground, `WidgetGradeReconciler` (wired into
`AppState.drain()`) replays queued grades through `store.apply(...)`, deduplicates
by decision UUID (in-memory), then rewrites the snapshot. See ADR-0010 for the
idempotency design and the cross-relaunch crash-window trade-off. Closes 2026 iOS
skill gap #3 (WidgetKit + interactive widget buttons).

---

## v1.1 Lane C2 — CloudKit Private DB Sync

**Date:** 2026-05-28
**Status:** code-complete; device sync QA deferred (two-device test requires
provisioned CloudKit container — see ADR-0011 exit gate)

`SyncMode` enum (`.local` / `.cloudKit(containerID:)`) selects the storage backend
at launch. `AnghkooeyModelContainer.makeContainer(syncMode:)` uses the same
`AnghkooeySchemaV3` + `AnghkooeyMigrationPlan` for both modes. `SyncPreference`
reads/writes a `UserDefaults` bool; the app reads it once in `init()`. A Settings
toggle exposes the preference with a relaunch note. Also fixed: (1) the latent V1-
schema / no-migration-plan bug in `AnghkooeyApp.init()`; (2) duplicate-checksum
crash from `ReviewLog`/`Tag` appearing in multiple schema versions; (3) iOS 26
auto-CloudKit activation requires `cloudKitDatabase: .none` for local mode.
Closes 2026 iOS skill gap #4. See ADR-0011.

## M7 — Cloze Deletion Cards

**Branch:** `m7/cloze-cards`
**Status:** code-complete; device QA pending (simulator UI interaction is
unreliable in CI — no `simctl`/MCP tap, AppleScript flaky — so the
TextEditor → parse-preview → Accept loop is verified by unit tests, not
on-device taps)
**ADR:** `docs/DECISIONS/0004-cloze-data-model.md`

M7 adds Anki-style cloze deletion cards. The design constraint was to leave the
FSRS-6 scheduler and the swipe-to-grade review UI **completely unchanged** — both
already consume a `Card` as two opaque pre-rendered strings (`question`/`answer`).
The data model decision (one `Card` per deletion, baked strings, sibling group)
is recorded in ADR-0004.

### Package topology additions

```
AnghkooeyCore/
└── Cloze/
    ├── ClozeTemplate.swift        — ClozeDeletion, ClozeTemplate, ClozeParseError value types
    └── ClozeMarkupParser.swift    — pure grammar authority for {{cN::answer::hint}}

AnghkooeyIntelligence/
└── Cloze/
    ├── ClozeDraft.swift           — @Generable; markedText + proposedTags
    ├── ClozeResponse.swift        — @Generable; items: [ClozeDraft]
    ├── ClozeAuthoringService.swift
    ├── LiveClozeAuthoringService.swift
    └── MockClozeAuthoringService.swift

AnghkooeyUI/
└── Cloze/
    └── ClozeAuthoringView.swift   — ClozeAuthoringViewModel (@Observable) + ClozeAuthoringView
```

### Schema

`AnghkooeySchemaV5` adds 5 Optional cloze fields to `Card` — `cardType`,
`clozeGroupID`, `clozeIndex`, `clozeSourceText`, `clozeBuriedUntil`. V4→V5 is a
lightweight migration (new Optional fields default to nil on existing rows). Q&A
cards leave all five nil. `AnghkooeyModelContainer` registers V5 as the current
schema and adds the V4→V5 stage to the migration plan.

### Data flow

```
passage text
  → ClozeAuthoringService.generateClozeDrafts(from:)   (Intelligence; @Generable ClozeDraft)
  → user edits markup in ClozeAuthoringView            (UI; live parse preview)
  → ClozeMarkupParser.parse(markedText)                (Core; produces ClozeTemplate)
  → CardStore.createClozeCards(from:tags:now:)         (Core; fans out N siblings)
  → N sibling Cards sharing a clozeGroupID
```

On review, `CardStore.apply` buries the unreviewed siblings of the graded card
until the next local day via `clozeBuriedUntil`, preventing same-session answer
leak between deletions of the same passage.

A Q&A / Cloze segmented control in ContentView's Capture tab routes between the
camera/OCR Q&A path and the text-editor cloze path. `MockClozeAuthoringService`
is wired in ContentView with a TODO for `LiveClozeAuthoringService`.

### Invariants

- **`ClozeMarkupParser` is the single grammar authority** for `{{cN::answer::hint}}`.
  AI output, the manual editor, and future Anki import all parse through it;
  unknown spans pass through verbatim. It rejects all 7 error cases (noDeletions,
  unclosedMarker, nestedMarker, duplicateIndex, nonPositiveIndex, emptyAnswer,
  tooManyDeletions).
- **Cloze cards are immutable post-creation.** No edit path in `CardStore.update`
  (stays Q&A-oriented) or the Library UI. Re-authoring replaces the group.
- **`dueCards` uses the `distantPast` sentinel pattern** for the `#Predicate` over
  the Optional `clozeBuriedUntil` — SwiftData's `#Predicate` cannot express
  `nil`-as-not-buried directly, so nil is coalesced to `distantPast`.
- **Review UI and FSRS scheduler are unchanged** — they see pre-rendered
  `question`/`answer` strings and have no awareness of cloze structure.

### AnkiNoteMapper (T5)

Ordinal-aware source identity so multiple cards from one Anki cloze note map to
distinct siblings; Anki cloze note types are skipped on import (cloze import is a
later increment — for now they do not silently produce malformed Q&A cards).

### Tests

85 tests across 20 suites; **84 pass.** New in M7: 11 `ClozeMarkupParserTests`
(T3), 2 `CardStoreClozeTests` (T4 — fan-out + `reviewingOneSiblingBuriesOthersUntilNextDay`),
2 `ClozeAuthoringViewModelTests` (T7 — `acceptFansOutSiblings`,
`rendersQuestionHidingTargetRevealingSiblings`), plus `SchemaMigrationV5Tests`
(`migrationPlanHasFiveSchemasAndFourStages`, `v4RowsGainNilClozeFieldsUnderV5`)
and the CloudKit V5 container gate (T2).

**Pre-existing failure (not M7):** `AnkiImporterTests.import_reviewCard_preservesDueDate`
fails (`card.dueAt` nil vs expected `2024-02-22`). This pre-dates M7 and is
unrelated to cloze — tracked separately.

## M8 — Personal FSRS-6 Optimization

M8 fits the 21 FSRS-6 weights to the user's own review history on device, gated at
≥512 eligible samples and applied globally to scheduling. Design rationale and the
numerical-stability decisions are in **ADR-0005**; the performance trace is in
**PERFORMANCE.md §M8**. This section records the structure.

**One math surface (the load-bearing decision).** `LiveFSRSOptimizer` computes the
loss by *replaying* each card's history through the existing, parity-verified
`LiveFSRS6Engine` primitives (`forgettingCurve`, `nextMemoryState`) under a candidate
weight vector — it never re-implements the FSRS formulas. A single private
`forEachEligible` replay drives `meanLoss`, the finite-difference gradient, and
`achievedRetention`. A scheduler bug and an optimizer bug therefore cannot diverge.

**Replay-based dataset (no leaked state).** `OptimizationDataset` reconstructs ordered
per-card `[ReviewSample]` sequences from a narrow `OptimizationReviewLogRow` projection
carrying only `(cardID, reviewedAt, rating, elapsedDays)`. It deliberately drops the
logged `stabilityBefore`/`difficultyBefore` — those were computed under default `w` and
are wrong for any candidate `w`; state is replayed inside the loss instead. Eligibility
(`index > 0 && elapsedDays > 0`) and the per-card sequence cap live here.

**Optimization pipeline.** `optimize(_:from:progress:)`:
1. `meanLoss` under `.default` → baseline.
2. `pretrainInitialStability` fits `w[0..3]` per first-review rating bucket (1-D Adam).
3. 60 mini-batch Adam epochs over the 21-weight vector; central finite-difference
   gradient with per-parameter relative epsilon; per-step clamping to FSRS-6 ranges;
   `SeededGenerator` (SplitMix64) for reproducible shuffles.
4. `meanLoss` under fitted `w` → optimized; deltas + `achievedRetention`.
The whole run is wrapped in the `"fsrs-optimization"` `OSSignposter` interval.

**Storage + resolution flow.** `OptimizedParametersStore` persists only the 21-element
`w` as JSON in the app-group container (so the widget reads the same set), rebuilding it
onto the ADR-0002-immutable `.default` via `FSRSParameters.withWeights`.
`resolveParameters(eligibleSampleCount:)` returns the stored set at/above the 512 gate
and `.default` otherwise. `AppState.refreshScheduler()` owns resolution: it reads
`CardStore.optimizationReviewLogs()`, counts eligible samples, resolves the engine, and
rebuilds both the `ReviewScreen` scheduler (via `ContentView`) and the
`WidgetGradeReconciler`. It runs on launch, after each drain, and after an optimization
run. Default-arg call sites cannot be `async`, which is why resolution lives in
`AppState` rather than at the `LiveFSRS6Engine()` defaults.

**UI.** `OptimizeScheduleView` + `OptimizeScheduleViewModel` (AnghkooeyUI) surface the
locked "unlocks at N reviews" empty state, the trigger, a progress bar, and the
before/after summary, calling back to `AppState.refreshScheduler()` on completion.
Hosted in `SettingsView` under a "Schedule optimization" `NavigationLink`; reads
`appState.cardStore` and `appState.optimizedParamsStore` directly.

**Parity oracle.** `scripts/fsrs-optimizer/` generates the loss-based parity fixture with
a self-contained stdlib FD-Adam oracle running the same algorithm (py-fsrs's torch
optimizer was unavailable on the build machine — see ADR-0005 for the deviation and its
honest tradeoff). Validation is loss-based, never weight-equality.

## M9 — Solid From First Tap (activation + trust)

M9 adds no new product scope; it hardens the first-run experience so a new user is
never blocked, never ambushed by a permission prompt at launch, and rewarded on every
review. The §4 audit at this milestone found **no v1 scope gaps** — all in-scope
surfaces (Share Sheet, camera/Vision OCR, FoundationModels Q&A authoring with mandatory
user review, FSRS-6 default scheduling, swipe-to-grade + haptics, Cushion Mode, Freeze,
tags, local SwiftData) remain present. The "No streaks / grace over guilt" principle
(§3) was explicitly upheld: the new session summary reports `reviewed` and `% remembered`
only — no streak counter, no shame copy.

**Manual card creation (front door).** `CardEditorViewModel` (AnghkooeyUI, `@MainActor
@Observable`) drives a dual-mode (`.create` / `.edit(Card.Snapshot)`) editor with a
per-mode `Kind` (`.qa` / `.cloze`). `canSave` branches on kind — Q&A requires non-blank
trimmed Q+A; cloze requires `ClozeMarkupParser.parse` to yield ≥1 deletion. Save routes
to the existing `CardStoreProtocol` primitives (`create(question:answer:sourceSpan:tags:now:)`
for Q&A, `createClozeCards(from:tags:now:)` for cloze) — no new store surface. The editor
is reached from a Library `＋` toolbar item; cloze authoring reuses the M7 markup parser
rather than adding a second cloze path.

**Availability-honest AI capture.** `CaptureAvailabilityModel` (a pure `Sendable` struct)
maps `AuthoringAvailability` → UX: `shouldOfferAI` and a nil-when-available
`bannerMessage` covering `deviceNotEligible` / `appleIntelligenceNotEnabled` /
`modelNotReady`, each routing the user to manual entry instead of a dead end. `ContentView`
now wires the **live** `LiveClozeAuthoringService` (mock removed). `AppState.enqueue`'s
authoring-failure path no longer inserts an opaque `"(edit to add answer)"` stub — it
surfaces a `CardDraft(question: resolvedText, answer: "")` so captured text is never lost
and still passes through the mandatory review sheet (no silent insertion, §4-consistent).

**Permission hygiene.** The camera authorization request moved out of cold-launch into
`CameraView.task` (instantiated only when the Capture/Q&A surface is on screen), with a
denied-state fallback offering *Open Settings* and a layer-backed `PreviewUIView`. The
required `NSCameraUsageDescription` purpose string was added to `Info.plist` (its absence
traps on first access). Clipboard detection uses non-prompting `UIPasteboard.hasStrings`;
the actual content read happens only in the user-initiated banner-accept action, so no
paste prompt fires at launch.

**Review loop polish.** `IntervalProjection` (AnghkooeyCore) projects, per `Rating`, the
seconds-until-next-due by calling the existing `FSRS6Engine.next` (never re-deriving
intervals) and formats compact labels (`<1m` / `10m` / `1d` / `1.5mo`), shown under each
grade button; NaN/∞ is guarded. `ReviewSession` exposes `currentIntervals` and a
`remainingCount` progress counter. `ReviewSummary` accumulates per-session stats for the
session-complete screen.

**First-run onboarding + starter deck.** `OnboardingState` (`@Observable`, `UserDefaults`-
backed `hasCompletedOnboarding` flag) gates a 3-page `OnboardingView` presented as a
`fullScreenCover`. `SampleDeckLoader` (App target) decodes the bundled `SampleDeck.json`
(12 mixed-topic cards) through `CardStoreProtocol.create`, with a `jsonData:` injection
seam so tests avoid a bundle dependency. Empty states in Review and Library are
actionable `ContentUnavailableView`s (Add a card / Import from Anki / Load sample deck).

**Trust hardening.** Library `load()` now distinguishes load-failure from empty-deck
(`loadFailed` error state vs. empty state) instead of swallowing errors into `cards = []`;
touched `try?`/`catch {}` sites gained logging or user-visible surfacing. New surfaces got
a VoiceOver + Dynamic Type pass.

**Tests.** 107 app tests across 28 suites, all green. New in M9: `IntervalProjectionTests`
(projection ordering + label formatting), `CardEditorViewModelTests` (create/edit/validation
+ cloze), `CaptureAvailabilityModelTests`, `ReviewSummaryTests`, `OnboardingStateTests`,
`SampleDeckLoaderTests`, plus the `AppStateEnqueue` fallback test. The pre-existing
`acceptDraft persists…` test was de-flaked (bounded poll vs. fixed `Task.yield()`s) to make
the full-suite green deterministic. On-device-only paths (live FoundationModels authoring,
camera OCR, torch) remain covered by the device-QA exit gate, not the simulator suite.
