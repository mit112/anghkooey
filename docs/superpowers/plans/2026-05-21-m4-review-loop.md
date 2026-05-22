# M4 Review Loop — FSRS-6 scheduling driving the card review UI
**Date:** 2026-05-21
**Branch:** `m4/review-loop`
**Plan source:** `docs/superpowers/plans/2026-05-20-rewind-implementation-plan.md §M4`
**Locked design (this document):** product decisions confirmed 2026-05-21 with `/model opus` exit review on M3.

---

## Locked product decisions

These are the trade-offs resolved with the project owner before any code is written. Treat as authoritative.

1. **Grade UX**: 2-button (Got it / Missed it) at the UI surface. Maps internally to FSRS-6 `Rating.good` and `Rating.again` respectively. The full 4-rating value is stored in `ReviewLog` so a 4-button UI can be added later without a data migration.
2. **Card schema**: front/back only (`Card.question` / `Card.answer`). Cloze deletion is out of scope for v1.
3. **CardAuthor timing**: drain-time. `AppState` runs `LiveCardAuthoringService.author(...)` after the drainer resolves text, *before* presenting the review sheet. The sheet shows a `CardDraft` (M2 type), not raw text.
4. **Empty state**: strict — "No cards due" when the due list is empty. No "study extras" affordance.
5. **Persistence boundary**: `CardStore` actor in `AnghkooeyCore`. Wraps SwiftData `ModelContext`. Exposes async API. The app target talks to `CardStore`, not `ModelContext`, so module boundaries stay clean and CloudKit migration is unblocked.
6. **Scope cut-line**: just the review loop. No decks, no tags UI (the `Tag` model already exists; we leave it dormant), no search, no statistics. WidgetKit and MetricKit dashboards belong to M5.

---

## Exit gate

- [ ] User accepts a `CardDraft` on the review sheet → a SwiftData `Card` is created with FSRS initial state, persisted, and immediately appears in the due list.
- [ ] User reviews a due card with Got it / Missed it → `Card.stability`, `Card.difficulty`, `Card.state`, `Card.dueAt`, `Card.lastReviewedAt` are updated via `LiveFSRS6Engine`, a `ReviewLog` is appended, and the change is persisted.
- [ ] Empty state shows when no cards are due (no zero-state visual jank).
- [ ] CardStore + grade-mapping + ReviewSession have unit-test coverage; full AnghkooeyCore + AnghkooeyIntelligence + AnghkooeyUI suites green.
- [ ] Anghkooey scheme builds clean (no new warnings) on iOS Simulator + iPhone 15 device.
- [ ] Demo path validated end-to-end on device: share a tweet via the Share Extension → review sheet appears with AI-authored Q&A → Accept → switch to Review tab → see one due card → Got it → due list empty.
- [ ] Updated `ARCHITECTURE.md` (M4 section) and brief addition to `PERFORMANCE.md` (M4 has no perf claims; just note that review tap → next-card latency is <100 ms median).

**Cut-line:** if `LiveCardAuthoringService` proves too slow at drain-time, demote the draft pipeline to use `MockCardAuthoringService` behind an `INTELLIGENCE_LIVE` compile flag for the demo path. The schema, store, scheduler, and review UI all ship regardless — the AI authoring tax is the only optional piece.

---

## Architecture

```
[InboxDrainer (M3)]
     │ resolvedText
     ▼
[AppState.enqueue(resolvedText:)]               ─── App target
     │                                              (composition root)
     │ LiveCardAuthoringService.author(...)
     ▼
[CardDraft] ───────────────────────────────────► AnghkooeyIntelligence (M2)
     │
     ▼
[CardReviewSheet] — shows question + answer
     │ on Accept
     ▼
[CardStore.create(from: CardDraft)] ───────────► AnghkooeyCore (M4)
     │
     ▼
[SwiftData Card { state: .new, dueAt: .now }]
     │
     ▼
[ReviewSession.fetchDue() → ReviewView]
     │ user grades with Got it / Missed it
     ▼
[ReviewSession.submit(grade)]
     │ LiveFSRS6Engine.next(card:rating:now:)
     ▼
[CardStore.apply(SchedulerOutput, to: Card)]
     │ persists Card + appends ReviewLog
     ▼
[ReviewSession.advanceQueue()]  → next due card or empty state
```

`CardStore` is the only `@MainActor`-free path to SwiftData. `ReviewSession` is `@MainActor @Observable` and owns the in-flight review state.

---

## Handoff Ledger

Convention from M1/M2/M3: Claude authors failing tests + public API skeletons (contract-first). Codex makes them pass. Claude verifies locally and reviews diffs.

| Task | Contract author | Implementer | Verifier |
|------|----------------|-------------|----------|
| M4.1 Migrate `AppState.CardDraft` to use M2 `CardDraft` (Intelligence) | Claude | Claude | Claude |
| M4.2 `AppState` calls `LiveCardAuthoringService.author` between drain and enqueue | Claude (tests) | Codex | Claude |
| M4.3 `CardStore` actor + protocol in `AnghkooeyCore` | Claude (tests + skeleton) | Codex | Claude |
| M4.4 `ReviewGrade` enum + FSRS `Rating` mapping | Claude | Claude | Claude |
| M4.5 `CardReviewSheet` update — show question/answer fields, not raw text | Claude | Claude | Claude |
| M4.6 `ReviewView` SwiftUI — front → reveal → 2-button | Claude | Claude | Claude |
| M4.7 `ReviewSession` `@MainActor @Observable` view model | Claude (tests + skeleton) | Codex | Claude |
| M4.8 `ReviewScreen` + tab routing + empty state | Claude | Claude | Claude |
| M4.9 `AnghkooeyApp` SwiftData ModelContainer wiring + CardStore injection | Claude | Claude | Claude |
| M4.10 Integration test: share → author → accept → review → schedule | Claude | Claude | Claude |
| M4.11 `ARCHITECTURE.md` M4 section + `PERFORMANCE.md` review-tap note | Claude | Claude | Claude |

---

## Task breakdown

### M4.1 — Replace local `CardDraft` with the M2 type
**Target:** `App/Anghkooey/AppState.swift`
**Owner:** Claude

Current state: `AppState` defines its own `struct CardDraft { let id; let resolvedText }`. Replace with the `CardDraft` already exported by `AnghkooeyIntelligence` (fields `question`, `answer`, `proposedTags`, `sourceSpan`). The intelligence draft is `Equatable + Codable + Sendable + @Generable`, not `Identifiable` — wrap it in an `IdentifiedDraft { id: UUID; draft: CardDraft }` for sheet binding.

**Why this is task 1:** every subsequent task assumes a richer draft. Doing this first makes M4.2 and M4.5 mechanical.

---

### M4.2 — `AppState` runs CardAuthor on drain
**Target:** `App/Anghkooey/AppState.swift`
**Contract author:** Claude · **Implementer:** Codex

Currently `AppState.enqueue(resolvedText:)` (called by `DrainerBridge.didReadItem`) wraps the string in the old `CardDraft` and presents the sheet. Replace with:

```swift
fileprivate func enqueue(resolvedText: String) async {
    do {
        let draft = try await cardAuthor.author(from: resolvedText)
        pendingDrafts.append(IdentifiedDraft(draft: draft))
        if presentedDraft == nil { advanceQueue() }
    } catch {
        // Foundation Models unavailable / refusal — fall back to a stub
        // draft so capture is never silently lost.
        let fallback = CardDraft(question: resolvedText, answer: "(edit to add answer)")
        pendingDrafts.append(IdentifiedDraft(draft: fallback))
        if presentedDraft == nil { advanceQueue() }
    }
}
```

`cardAuthor` is `any CardAuthoringService` injected into `AppState.init` (default: `LiveCardAuthoringService()`). Tests inject `MockCardAuthoringService`.

**Tests (Claude authors first):**
- `enqueue_runsCardAuthor_andQueuesDraft`
- `enqueue_onAuthoringFailure_queuesFallbackDraft`
- `enqueue_preservesQueueOrder_acrossMultipleDrains`

---

### M4.3 — `CardStore` actor in AnghkooeyCore
**Target:** `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardStore.swift`
**Contract author:** Claude (skeleton + tests) · **Implementer:** Codex

Public API:

```swift
public protocol CardStoreProtocol: Sendable {
    func create(from draft: CardDraft, now: Date) async throws -> Card.Snapshot
    func dueCards(asOf now: Date) async throws -> [Card.Snapshot]
    func apply(_ output: SchedulerOutput, to cardID: UUID, grade: Rating, now: Date) async throws
    func count() async throws -> (total: Int, due: Int)
}

public actor CardStore: CardStoreProtocol {
    public init(container: ModelContainer)
    // ...
}
```

`Card.Snapshot` is a `Sendable` value-type view of a `Card` (UUID + question + answer + dueAt + state + stability + difficulty). SwiftData `@Model` classes are not `Sendable`; we shuttle snapshots across the actor boundary and never let the live `Card` escape `CardStore`.

`apply(_:to:grade:now:)`:
1. Fetch `Card` by `id` inside the actor's `ModelContext`.
2. Update FSRS fields (`stability`, `difficulty`, `dueAt`, `lastReviewedAt`, `state`) from `SchedulerOutput`.
3. Append a `ReviewLog` (the M0 model already exists) with the user-facing grade.
4. `try modelContext.save()`.

Note that `CardDraft.proposedTags` are **not** wired in M4 — Tag UI is M5+. Drop them in the draft → Card conversion but keep `sourceSpan`.

**Tests (Claude authors first, Codex implements actor):**
- `create_persistsCard_withNewState_andDueNow`
- `dueCards_returnsOnlyCardsWithDueAtBeforeOrEqualToNow`
- `apply_updatesFSRSFields_andAppendsReviewLog`
- `apply_persistsAcrossStoreReopen` (round-trip through a recreated ModelContainer)
- `count_returnsTotalAndDueSeparately`

In-memory test container: `ModelContainer(for: AnghkooeySchemaV1.allModels, configurations: ModelConfiguration(isStoredInMemoryOnly: true))`.

---

### M4.4 — `ReviewGrade` → FSRS `Rating` mapping
**Target:** `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/ReviewGrade.swift`
**Owner:** Claude

```swift
public enum ReviewGrade: String, Codable, Sendable, CaseIterable {
    case missed
    case gotIt

    public var fsrsRating: Rating {
        switch self {
        case .missed: return .again
        case .gotIt:  return .good
        }
    }
}
```

Trivially testable; ships with three assertions (case count, each mapping).

**Why a dedicated type and not just `Rating` everywhere:** keeps the UI layer ignorant of FSRS internals; lets the 4-button UI (if we add one) compile cleanly without UI calling FSRS types directly.

---

### M4.5 — `CardReviewSheet` shows Q&A, not raw text
**Target:** `App/Anghkooey/CardReviewSheet.swift`
**Owner:** Claude

Two labeled fields (`Question` / `Answer`) shown above the existing Accept/Skip buttons. Both fields are read-only in v1 (editing-before-accept is M5). The `sourceSpan`, if present, is shown collapsed below the answer as `Source: "..."` — text-only, no styling work.

---

### M4.6 — `ReviewView` SwiftUI in AnghkooeyUI
**Target:** `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewView.swift`
**Owner:** Claude

State machine:

```
.idle → .question(shown) → .revealed → .grading → next card or .empty
```

- `.question(shown)`: large centered text, a single "Show answer" button.
- `.revealed`: question stays, answer fades in below, two buttons appear (`Missed it` red-tinted on left, `Got it` accent-tinted on right). No haptic flourish in v1 — that's M5 polish.
- `.empty`: subdued "No cards due. Capture something via the Share Extension to start." with an SF Symbol.

`ReviewView` takes `session: ReviewSession` as `@Bindable`. No FSRS imports — talks to the session only.

---

### M4.7 — `ReviewSession` `@MainActor @Observable` view model
**Target:** `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewSession.swift`
**Contract author:** Claude · **Implementer:** Codex

Public surface:

```swift
@MainActor
@Observable
public final class ReviewSession {
    public init(store: any CardStoreProtocol, scheduler: any FSRS6Engine, clock: @Sendable @escaping () -> Date = { .now })

    public private(set) var currentCard: Card.Snapshot?
    public private(set) var isAnswerRevealed: Bool
    public private(set) var queueRemaining: Int
    public private(set) var state: ReviewSessionState  // .loading | .reviewing | .empty | .error

    public func loadDueQueue() async
    public func revealAnswer()
    public func submit(grade: ReviewGrade) async
}
```

Flow inside `submit`: build `SchedulingCard` from the snapshot → `scheduler.next(card:rating:now:)` → `store.apply(output, to: id, grade:, now:)` → `currentCard = queue.popFirst()` → if empty, switch state to `.empty`.

**Tests (Claude authors first):**
- `loadDueQueue_populatesCurrent_andQueueRemaining`
- `submit_gotIt_callsScheduler_withGoodRating_andAdvances`
- `submit_missed_callsScheduler_withAgainRating_andAdvances`
- `submit_onLastCard_movesToEmpty`
- `revealAnswer_idempotent`

---

### M4.8 — `ReviewScreen` + tab routing + empty state
**Target:** `App/Anghkooey/ContentView.swift` (becomes a `TabView`); `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewScreen.swift`
**Owner:** Claude

`ContentView` becomes a `TabView` with two tabs (kept minimal):
1. **Review** — `ReviewScreen` (wraps `ReviewView`, owns `ReviewSession` for the screen lifetime).
2. **Capture** — the existing in-app camera entry point (`CameraView`).

A future Library tab is M5+; we leave the seam (a third tab `placeholder`) only if it costs zero code.

`ReviewScreen` calls `session.loadDueQueue()` in `.task` and on `.onChange(of: scenePhase) where == .active`. Accepting a draft in `AppState` posts an internal `Notification` (or sets a published value on `AppState`) so `ReviewScreen` knows to refresh — define this as the simplest binding that works.

---

### M4.9 — `AnghkooeyApp` SwiftData wiring
**Target:** `App/Anghkooey/AnghkooeyApp.swift`
**Owner:** Claude

```swift
@main
struct AnghkooeyApp: App {
    @State private var appState: AppState
    let modelContainer: ModelContainer
    let cardStore: CardStore

    init() {
        // ...existing log subsystem config...
        let container = try! ModelContainer(for: AnghkooeySchemaV1.allModels)
        let store = CardStore(container: container)
        self.modelContainer = container
        self.cardStore = store
        self._appState = State(initialValue: AppState(
            cardAuthor: LiveCardAuthoringService(),
            store: store
        ))
    }
    // ...
}
```

`try!` is acceptable for the container — failing to open SwiftData on launch is unrecoverable in v1. Log + crash beats a silent broken state.

---

### M4.10 — Integration test: end-to-end happy path
**Target:** `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/Integration/EndToEndReviewFlowTests.swift`
**Owner:** Claude

In-process integration test (no UI). Steps:
1. Build an in-memory `CardStore` + `MockCardAuthoringService` + `LiveFSRS6Engine`.
2. Feed `"The capital of France is Paris"` through `MockCardAuthoringService.author`.
3. Call `store.create(from: draft)`.
4. Call `store.dueCards(asOf: .now)` — expect 1.
5. Build a `ReviewSession`, call `loadDueQueue()`, `revealAnswer()`, `submit(.gotIt)`.
6. Re-call `store.dueCards(asOf: .now)` — expect 0 (the card was just reviewed; FSRS pushes it to the future).
7. Re-call `store.dueCards(asOf: now + 30 days)` — expect 1.

This is the test that proves the seams are all wired.

---

### M4.11 — Docs
**Target:** `ARCHITECTURE.md`, `PERFORMANCE.md`
**Owner:** Claude

`ARCHITECTURE.md`: append an `## M4 — Review Loop` section mirroring the M3 structure (topology diagram + module seams + the `CardStore` snapshot pattern justification).

`PERFORMANCE.md`: add a one-paragraph note that M4 introduces no new signposts; review-tap → next-card latency is dominated by SwiftData `save()` and is expected to be well under 100 ms.

---

## Risk register

| Risk | Likelihood | Mitigation |
|------|-----------|-----------|
| `LiveCardAuthoringService` latency at drain-time degrades UX | Medium | M4.2 fallback path; behind `INTELLIGENCE_LIVE` flag if needed |
| SwiftData `ModelContainer` boot fails on a device with corrupted store | Low | `try!` for v1; full recovery flow is M5+ work |
| `Card.Snapshot` drift from `Card` as the schema evolves | Medium | Single conversion init `Card.Snapshot(from: Card)` + a test that asserts every field is round-tripped |
| Concurrent edits to a `Card` between snapshot fetch and `apply` | Low (single-user app, single-actor store) | `CardStore` is an actor; no two writes overlap |
| Review tab flicker when AppState pushes a draft accept | Low | M4.8 binding contract: prefer simple `await session.loadDueQueue()` on draft acceptance |

---

## Out-of-scope (deferred to M5 or later)

- Cloze deletion authoring
- Tag UI / deck organization
- Statistics dashboards / heatmaps
- WidgetKit / Live Activity entry points
- 4-button Hard/Easy grading
- Audio cards, image cards on the back of a Q&A
- iCloud / CloudKit sync wiring (schema is ready; transport is not)
- Card editing before accept
- Bulk import / OPML / Anki APKG
