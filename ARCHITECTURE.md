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
