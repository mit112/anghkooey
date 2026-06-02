# M9 — "Solid From First Tap" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Anghkooey feel solid the moment a new user opens it (never blocked, never ambushed by permissions) and rewarding on every review session, by adding manual card creation, wiring the on-device AI for real with honest availability fallback, fixing launch-time permission prompts, polishing the review loop, and adding a guided first-run with a one-tap sample deck.

**Architecture:** Pure scheduling/markup logic lives in `AnghkooeyCore`; AI authoring + availability in `AnghkooeyIntelligence`; SwiftUI views + small `@Observable` view-models in `AnghkooeyUI`; app-level wiring/state in `App/Anghkooey`. New logic units are isolated and unit-tested with Swift Testing; SwiftUI views follow existing file patterns. On-device AI cannot run on the simulator → a device-QA exit gate covers it.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, SwiftData, Swift Testing, FoundationModels (on-device), `xcodebuild` via XcodeBuildMCP, iPhone 17 Pro (iOS 26) simulator.

---

## Model routing & Codex roles

Per project convention (`CLAUDE.md`, memory `feedback_plans_must_route_models`, `feedback_codex_concrete_roles_in_plans`), every task carries an owner model and a named Codex role.

| Task | Owner model | Codex role |
|------|-------------|------------|
| 1 IntervalProjection (Core) | Sonnet | reviewer (math sanity) |
| 2 CardEditorViewModel | Sonnet | none |
| 3 Library ＋ + dual-mode editor | Sonnet | none |
| 4 Manual Cloze authoring | Sonnet | primary impl (markup edge cases) |
| 5 CaptureAvailabilityModel + Cloze live wiring | Sonnet | none |
| 6 AppState honest fallback | Sonnet | reviewer (concurrency) |
| 7 Permission hygiene (camera + clipboard) | Sonnet | reviewer (timing/regression) |
| 8 Review polish (intervals, progress) | Sonnet | none |
| 9 ReviewSummary (session close) | Sonnet | none |
| 10 Onboarding + flag | Sonnet | none |
| 11 SampleDeckLoader + bundled deck | Sonnet | none |
| 12 Empty-state CTAs | Sonnet | none |
| 13 Silent-failure audit | Sonnet | reviewer |
| 14 Accessibility pass | Sonnet | none |
| Milestone exit review | **Opus** | ecc:code-reviewer fallback |

Parent session orchestrates on Opus; dispatch execution subagents with `model: "sonnet"`. Codex sandbox cannot run `xcodebuild` (memory `feedback_codex_sandbox`) — Codex writes diffs/reviews, Claude verifies locally.

## Build & test commands (use everywhere below)

Build:
```bash
xcodebuild -project App/Anghkooey.xcodeproj -scheme Anghkooey \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/anghkooey-derived-data \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_STYLE=Manual build 2>&1 | tail -20
```
Test:
```bash
xcodebuild -project App/Anghkooey.xcodeproj -scheme Anghkooey \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/anghkooey-derived-data \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_STYLE=Manual test 2>&1 | tail -30
```
(SourceKit "Cannot find type" diagnostics on freshly-written files are stale; trust `xcodebuild test` — memory `feedback_sourcekit_stale_in_harness`.)

---

## File Structure

**Create:**
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/IntervalProjection.swift` — pure ratings→next-interval projection.
- `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/IntervalProjectionTests.swift`
- `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Library/CardEditorViewModel.swift` — create/edit state + validation.
- `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Capture/CaptureAvailabilityModel.swift` — `AuthoringAvailability` → UX state.
- `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewSummary.swift` — session-complete summary model + view.
- `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Onboarding/OnboardingView.swift` — guided first-run + `OnboardingState`.
- `App/Anghkooey/SampleDeck/SampleDeckLoader.swift` — loads bundled deck via store.
- `App/Anghkooey/SampleDeck/SampleDeck.json` — bundled starter cards (resource).
- Test files in `App/AnghkooeyTests/` per task.

**Modify:**
- `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Library/LibraryView.swift` — toolbar ＋, create sheet, empty CTAs.
- `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Library/LibraryCardEditView.swift` — dual-mode (create/edit), manual cloze.
- `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewView.swift` + `ReviewScreen.swift` + `ReviewSession.swift` — interval previews, progress, summary, empty CTAs.
- `App/Anghkooey/ContentView.swift` — live Cloze service, lazy Capture, onboarding gate.
- `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Camera/CameraView.swift` — defer camera request until visible.
- `App/Anghkooey/Clipboard/ClipboardCaptureCoordinator.swift` + `Clipboard/ClipboardBanner.swift` — non-prompting detection.
- `App/Anghkooey/AppState.swift` — honest authoring fallback (preserve captured text).

---

## Workstream A — Manual card creation (front door)

### Task 1: IntervalProjection (Core)

Pure helper projecting the next interval for each rating, used by the review buttons (Task 8) and worth landing first because it's the riskiest logic.

**Files:**
- Create: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/IntervalProjection.swift`
- Test: `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/IntervalProjectionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import AnghkooeyCore

@Suite struct IntervalProjectionTests {
    @Test func projectsAllFourRatingsForNewCard() throws {
        let engine = LiveFSRS6Engine()
        let card = SchedulingCard(state: .new, stability: 0, difficulty: 0,
                                  due: .now, reps: 0, lapses: 0,
                                  lastReview: nil, elapsedDays: 0, scheduledDays: 0)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let projections = IntervalProjection.project(card: card, engine: engine, now: now)

        #expect(projections.count == 4)
        // Ratings ordered again < hard < good < easy by resulting interval.
        let again = projections[.again]!, hard = projections[.hard]!
        let good = projections[.good]!, easy = projections[.easy]!
        #expect(again <= hard)
        #expect(hard <= good)
        #expect(good <= easy)
    }

    @Test func formatsShortAndLongIntervals() {
        #expect(IntervalProjection.label(seconds: 30) == "<1m")
        #expect(IntervalProjection.label(seconds: 600) == "10m")
        #expect(IntervalProjection.label(seconds: 86_400) == "1d")
        #expect(IntervalProjection.label(seconds: 4 * 86_400) == "4d")
        #expect(IntervalProjection.label(seconds: 45 * 86_400) == "1.5mo")
    }
}
```

- [ ] **Step 2: Run test, verify it fails**

Run the Core suite (Core builds standalone — memory `feedback_swift_test_package_limitations`):
```bash
cd Packages/AnghkooeyCore && swift test --filter IntervalProjectionTests 2>&1 | tail -20
```
Expected: FAIL — `IntervalProjection` undefined.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Projects the next review interval for each `Rating` without mutating state.
/// Used to show "<1m / 10m / 1d / 4d" hints under the grade buttons.
public enum IntervalProjection {

    /// Returns, per rating, the seconds-from-`now` until the card would next be due.
    public static func project(card: SchedulingCard,
                               engine: any FSRS6Engine,
                               now: Date) -> [Rating: TimeInterval] {
        var out: [Rating: TimeInterval] = [:]
        for rating in Rating.allCases {
            guard let output = try? engine.next(card: card, rating: rating, now: now) else { continue }
            out[rating] = max(0, output.card.due.timeIntervalSince(now))
        }
        return out
    }

    /// Compact human label for an interval in seconds.
    public static func label(seconds: TimeInterval) -> String {
        let minute = 60.0, hour = 3_600.0, day = 86_400.0, month = 30 * day, year = 365 * day
        switch seconds {
        case ..<minute:        return "<1m"
        case ..<hour:          return "\(Int((seconds / minute).rounded()))m"
        case ..<day:           return "\(Int((seconds / hour).rounded()))h"
        case ..<month:         return "\(Int((seconds / day).rounded()))d"
        case ..<year:          return "\(trim(seconds / month))mo"
        default:               return "\(trim(seconds / year))y"
        }
    }

    private static func trim(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))" : "\(rounded)"
    }
}
```

If `SchedulingCard`'s initializer differs from the test, adjust the test's `SchedulingCard(...)` call to the real signature (read `SchedulingCard.swift`) — do not change the projection logic.

- [ ] **Step 4: Run test, verify it passes**

```bash
cd Packages/AnghkooeyCore && swift test --filter IntervalProjectionTests 2>&1 | tail -20
```
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/IntervalProjection.swift \
        Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/IntervalProjectionTests.swift
git commit -m "feat(m9): IntervalProjection — ratings→next-interval labels for review hints"
```

---

### Task 2: CardEditorViewModel (create + edit + validation)

**Files:**
- Create: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Library/CardEditorViewModel.swift`
- Test: `App/AnghkooeyTests/CardEditorViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import AnghkooeyUI
import AnghkooeyCore

@MainActor @Suite struct CardEditorViewModelTests {
    @Test func createModeStartsEmptyAndInvalid() {
        let vm = CardEditorViewModel(mode: .create, store: MockCardStore())
        #expect(vm.question.isEmpty)
        #expect(vm.answer.isEmpty)
        #expect(vm.canSave == false)
    }

    @Test func becomesValidWhenBothFieldsNonEmpty() {
        let vm = CardEditorViewModel(mode: .create, store: MockCardStore())
        vm.question = "  Capital of France?  "
        vm.answer = "Paris"
        #expect(vm.canSave == true)
    }

    @Test func whitespaceOnlyIsInvalid() {
        let vm = CardEditorViewModel(mode: .create, store: MockCardStore())
        vm.question = "   "; vm.answer = "   "
        #expect(vm.canSave == false)
    }

    @Test func saveCreatesCardInStore() async throws {
        let store = MockCardStore()
        let vm = CardEditorViewModel(mode: .create, store: store)
        vm.question = "2+2?"; vm.answer = "4"; vm.tags = ["Math"]
        try await vm.save()
        let all = try await store.allCards()
        #expect(all.contains { $0.question == "2+2?" && $0.answer == "4" })
    }
}
```

(`MockCardStore` already exists in Core and is used by other app tests.)

- [ ] **Step 2: Run test, verify it fails**

Run via the app test command (top of plan). Expected: FAIL — `CardEditorViewModel` undefined.

- [ ] **Step 3: Implement**

```swift
import Foundation
import Observation
import AnghkooeyCore

/// Drives the dual-mode card editor (create new card or edit an existing one).
@MainActor @Observable
public final class CardEditorViewModel {

    public enum Mode: Equatable {
        case create
        case edit(Card.Snapshot)
    }

    public var question: String = ""
    public var answer: String = ""
    public var tags: [String] = []
    public private(set) var isSaving = false

    private let mode: Mode
    private let store: any CardStoreProtocol

    public init(mode: Mode, store: any CardStoreProtocol) {
        self.mode = mode
        self.store = store
        if case let .edit(card) = mode {
            question = card.question
            answer = card.answer
            tags = card.tags
        }
    }

    public var navigationTitle: String {
        if case .create = mode { return "New Card" } else { return "Edit Card" }
    }

    public var canSave: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isSaving
    }

    /// Persists the card. Create-mode inserts; edit-mode updates the existing card.
    public func save() async throws {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        defer { isSaving = false }
        switch mode {
        case .create:
            _ = try await store.create(question: q, answer: a, sourceSpan: nil, tags: tags, now: .now)
        case let .edit(card):
            try await store.update(id: card.id, question: q, answer: a, tags: tags)
        }
    }
}
```

If `CardStoreProtocol` lacks `update(id:question:answer:tags:)`, use the update method `LibraryCardEditView` already calls (read that file and match its existing save path); keep the same method here rather than inventing a new one.

- [ ] **Step 4: Run test, verify it passes** — Expected: PASS (4 tests).
- [ ] **Step 5: Commit**

```bash
git add Packages/AnghkooeyUI/Sources/AnghkooeyUI/Library/CardEditorViewModel.swift \
        App/AnghkooeyTests/CardEditorViewModelTests.swift
git commit -m "feat(m9): CardEditorViewModel — create/edit state + validation"
```

---

### Task 3: Library ＋ button + dual-mode editor view

**Files:**
- Modify: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Library/LibraryCardEditView.swift`
- Modify: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Library/LibraryView.swift`

- [ ] **Step 1:** Refactor `LibraryCardEditView` to take a `CardEditorViewModel` and support both modes. Replace its init with:

```swift
public struct LibraryCardEditView: View {
    @State private var model: CardEditorViewModel
    @Environment(\.dismiss) private var dismiss
    private let onSaved: () -> Void

    public init(mode: CardEditorViewModel.Mode,
                store: any CardStoreProtocol,
                onSaved: @escaping () -> Void) {
        _model = State(initialValue: CardEditorViewModel(mode: mode, store: store))
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Question") { TextField("Question", text: $model.question, axis: .vertical) }
                Section("Answer")   { TextField("Answer", text: $model.answer, axis: .vertical) }
                Section("Tags")     { TagEditorView(tags: $model.tags) }
            }
            .navigationTitle(model.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { try? await model.save(); onSaved(); dismiss() }
                    }.disabled(!model.canSave)
                }
            }
        }
    }
}
```

(Use the existing `TagEditorView` in `Shared/TagEditorView.swift`. Keep the visual structure close to the current edit view.)

- [ ] **Step 2:** In `LibraryView.swift`, add create state and a ＋ toolbar item. Add property `@State private var showingCreate = false`. Add to the existing `.toolbar`:

```swift
ToolbarItem(placement: .topBarTrailing) {
    Button { showingCreate = true } label: { Label("Add Card", systemImage: "plus") }
}
```

Update the edit sheet call site to the new init and add a create sheet:

```swift
.sheet(item: $editingCard) { card in
    LibraryCardEditView(mode: .edit(card), store: store) { Task { await load() } }
}
.sheet(isPresented: $showingCreate) {
    LibraryCardEditView(mode: .create, store: store) { Task { await load() } }
}
```

- [ ] **Step 3: Build, verify it compiles**

Run the build command (top of plan). Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual sim check** — launch, Library → ＋ → type Q/A → Save → row appears; tapping a row still edits. (Use `xcrun simctl launch`; Quartz CGEvent taps if driving UI — calibration: `screen_x = 1063 + 1.179*sx`, `screen_y = 145 + 1.18*sy` for iPhone 17 Pro window at (1052,117).)

- [ ] **Step 5: Commit**

```bash
git add Packages/AnghkooeyUI/Sources/AnghkooeyUI/Library/LibraryCardEditView.swift \
        Packages/AnghkooeyUI/Sources/AnghkooeyUI/Library/LibraryView.swift
git commit -m "feat(m9): manual card creation — Library ＋ and dual-mode editor"
```

---

### Task 4: Manual Cloze authoring in the editor

Add a Q&A / Cloze segmented control to the create editor. Cloze mode lets the user type a sentence and mark deletions, then persists via `store.createClozeCards(from:tags:now:)`.

**Files:**
- Modify: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Library/CardEditorViewModel.swift`
- Modify: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Library/LibraryCardEditView.swift`
- Test: `App/AnghkooeyTests/CardEditorViewModelTests.swift` (extend)

- [ ] **Step 1: Write the failing test** (append to the suite)

```swift
@Test func clozeModeBuildsTemplateAndCreatesCards() async throws {
    let store = MockCardStore()
    let vm = CardEditorViewModel(mode: .create, store: store)
    vm.kind = .cloze
    vm.clozeText = "The capital of France is {{Paris}}."
    #expect(vm.canSave == true)
    try await vm.save()
    let all = try await store.allCards()
    #expect(all.contains { $0.question.contains("capital of France") })
}

@Test func clozeWithoutDeletionIsInvalid() {
    let vm = CardEditorViewModel(mode: .create, store: MockCardStore())
    vm.kind = .cloze
    vm.clozeText = "No deletions here."
    #expect(vm.canSave == false)
}
```

- [ ] **Step 2:** Run app test command. Expected: FAIL — `kind`/`clozeText` undefined.

- [ ] **Step 3: Implement.** Add to `CardEditorViewModel`:

```swift
public enum Kind: Equatable { case qa, cloze }
public var kind: Kind = .qa
/// Cloze source using `{{answer}}` markup, parsed by ClozeMarkupParser.
public var clozeText: String = ""

private var parsedCloze: ClozeTemplate? {
    try? ClozeMarkupParser.parse(clozeText)   // match the real parser entry point
}
```

Update `canSave` to branch on `kind`:

```swift
public var canSave: Bool {
    guard !isSaving else { return false }
    switch kind {
    case .qa:
        return !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .cloze:
        guard let t = parsedCloze else { return false }
        return !t.deletions.isEmpty
    }
}
```

Update `save()`'s `.create` branch to honor `kind`:

```swift
case .create:
    switch kind {
    case .qa:
        _ = try await store.create(question: q, answer: a, sourceSpan: nil, tags: tags, now: .now)
    case .cloze:
        guard let template = parsedCloze else { return }
        _ = try await store.createClozeCards(from: template, tags: tags, now: .now)
    }
```

Read `Cloze/ClozeMarkupParser.swift` and `Cloze/ClozeTemplate.swift` to confirm the parse entry point and `ClozeTemplate(markup:deletions:)` shape; adjust `parsedCloze` to the real API (do not change the branching logic). Add `import AnghkooeyCore` already present.

- [ ] **Step 4:** In `LibraryCardEditView`, in `.create` mode only, show a `Picker` ("Q&A"/"Cloze", `.segmented`) bound to `$model.kind`, and when `.cloze` show a `TextField("Sentence with {{answers}}", text: $model.clozeText, axis: .vertical)` plus a live preview line of parsed deletions. Hide Question/Answer sections when `kind == .cloze`.

- [ ] **Step 5:** Run app test command. Expected: PASS (now 6 tests in suite). Build. Commit:

```bash
git add Packages/AnghkooeyUI/Sources/AnghkooeyUI/Library/CardEditorViewModel.swift \
        Packages/AnghkooeyUI/Sources/AnghkooeyUI/Library/LibraryCardEditView.swift \
        App/AnghkooeyTests/CardEditorViewModelTests.swift
git commit -m "feat(m9): manual cloze authoring in card editor"
```

---

## Workstream B — AI capture wired for real + availability-honest

### Task 5: CaptureAvailabilityModel + live Cloze wiring

**Files:**
- Create: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Capture/CaptureAvailabilityModel.swift`
- Test: `App/AnghkooeyTests/CaptureAvailabilityModelTests.swift`
- Modify: `App/Anghkooey/ContentView.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import AnghkooeyUI
import AnghkooeyIntelligence

@Suite struct CaptureAvailabilityModelTests {
    @Test func availableShowsAICapture() {
        let m = CaptureAvailabilityModel(availability: .available)
        #expect(m.shouldOfferAI == true)
        #expect(m.bannerMessage == nil)
    }
    @Test func deviceIneligibleRoutesToManualWithMessage() {
        let m = CaptureAvailabilityModel(availability: .unavailable(reason: .deviceNotEligible))
        #expect(m.shouldOfferAI == false)
        #expect(m.bannerMessage?.isEmpty == false)
    }
    @Test func aiOffMentionsSettings() {
        let m = CaptureAvailabilityModel(availability: .unavailable(reason: .appleIntelligenceNotEnabled))
        #expect(m.bannerMessage?.localizedCaseInsensitiveContains("settings") == true)
    }
}
```

- [ ] **Step 2:** Run app test command. Expected: FAIL — type undefined.
- [ ] **Step 3: Implement**

```swift
import Foundation
import AnghkooeyIntelligence

/// Maps on-device model availability into capture-screen UX decisions.
public struct CaptureAvailabilityModel: Sendable, Equatable {
    public let availability: AuthoringAvailability
    public init(availability: AuthoringAvailability) { self.availability = availability }

    /// Whether to offer AI generation vs. drop straight to manual entry.
    public var shouldOfferAI: Bool {
        if case .available = availability { return true }
        return false
    }

    /// One-line explanation shown when AI is unavailable (nil when available).
    public var bannerMessage: String? {
        switch availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "On-device card generation isn't supported on this device. You can still add cards by hand."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to auto-generate cards. For now, add cards by hand."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading. You can add cards by hand in the meantime."
        }
    }
}
```

- [ ] **Step 4:** Run app test command. Expected: PASS (3 tests).
- [ ] **Step 5:** In `ContentView.swift`, swap the Cloze service to live:

```swift
// was: MockClozeAuthoringService()
ClozeAuthoringView(store: appState.cardStore,
                   authoringService: LiveClozeAuthoringService())
```

Remove the stale `// TODO: Replace with LiveClozeAuthoringService()...` comment. Build (compiles; runtime AI is device-only). Commit:

```bash
git add Packages/AnghkooeyUI/Sources/AnghkooeyUI/Capture/CaptureAvailabilityModel.swift \
        App/AnghkooeyTests/CaptureAvailabilityModelTests.swift App/Anghkooey/ContentView.swift
git commit -m "feat(m9): wire live Cloze service + CaptureAvailabilityModel"
```

---

### Task 6: AppState honest authoring fallback

Replace the opaque `"(edit to add answer)"` stub with the captured text preserved, so the user always sees what was captured and why it wasn't auto-generated.

**Files:**
- Modify: `App/Anghkooey/AppState.swift` (`enqueue(resolvedText:)`, lines ~178-188)
- Test: `App/AnghkooeyTests/AppStateEnqueueTests.swift` (extend; file exists)

- [ ] **Step 1: Write the failing test** (append)

```swift
@MainActor
@Test func enqueueFallbackPreservesCapturedTextAsQuestion() async {
    // A failing author surfaces the captured text, not an opaque stub.
    let state = AppState(cardAuthor: FailingAuthor(), cardStore: MockCardStore())
    await state.enqueue(resolvedText: "Mitochondria is the powerhouse of the cell")
    #expect(state.presentedDraft?.draft.question == "Mitochondria is the powerhouse of the cell")
    #expect(state.presentedDraft?.draft.answer.isEmpty == true)
}
```

Add a tiny failing author near the top of the test file:

```swift
private struct FailingAuthor: CardAuthoringService {
    func author(from text: String) async throws -> CardDraft {
        throw AuthoringError.generationFailed   // use a real case from AuthoringError
    }
}
```

(Check `Authoring/AuthoringError.swift` and `CardAuthoringService.swift` for the exact protocol method + an error case; match them.)

- [ ] **Step 2:** Run app test command. Expected: FAIL — answer is `"(edit to add answer)"`.
- [ ] **Step 3: Implement.** In `enqueue`, change the `catch` block:

```swift
} catch {
    // AI unavailable or failed — never lose the captured text. Surface it
    // for manual completion instead of an opaque stub.
    IntelligenceLog.authoring.notice("Authoring failed; preserving captured text for manual edit")
    let fallback = CardDraft(question: resolvedText, answer: "")
    pendingDrafts.append(IdentifiedDraft(draft: fallback))
    if presentedDraft == nil { advanceQueue() }
}
```

(If `CardDraft` requires a non-empty answer or different init, read `Authoring/CardDraft.swift` and pass `answer: ""`/the closest empty representation. The `CardReviewSheet` should render an empty answer as an editable empty field — verify it does; if it shows a placeholder, that's fine.) Use the logger that already exists (`IntelligenceLog`/`CoreLog`); if neither is importable here, use `Logger`.

- [ ] **Step 4:** Run app test command. Expected: PASS. Build. 
- [ ] **Step 5: Commit**

```bash
git add App/Anghkooey/AppState.swift App/AnghkooeyTests/AppStateEnqueueTests.swift
git commit -m "fix(m9): preserve captured text on authoring failure (no opaque stub)"
```

---

## Workstream C — Permission hygiene

### Task 7: Defer camera + stop empty-clipboard paste prompt

**Files:**
- Modify: `App/Anghkooey/ContentView.swift` (lazy Capture content)
- Modify: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Camera/CameraView.swift` (request only when visible)
- Modify: `App/Anghkooey/Clipboard/ClipboardCaptureCoordinator.swift` + `Clipboard/ClipboardBanner.swift`

- [ ] **Step 1: Camera — make the request visibility-gated.** In `ContentView`, only build `CameraView` when the Capture tab is selected AND mode is `.qa`. Add a `@State private var selectedTab = 0` (or use a `TabView(selection:)`), tag the Capture tab, and guard:

```swift
if selectedTab == captureTabIndex && captureMode == .qa && availabilityModel.shouldOfferAI {
    CameraView(captureSession: CameraCaptureSession(),
               ocrService: LiveOCRServiceDataAdapter(),
               onCapture: { text in Task { await appState.enqueue(resolvedText: text) } })
} else if captureMode == .qa {
    // Not on screen yet, or AI unavailable: show manual-entry CTA instead.
    CaptureManualFallbackView(message: availabilityModel.bannerMessage)
}
```

This guarantees `CameraView.task` (which calls `requestCameraAccess()`) is not instantiated at cold launch. `CaptureManualFallbackView` is a small view with the `bannerMessage` (when present) and an "Add card by hand" button opening the Task 3 editor in `.create` mode.

- [ ] **Step 2: Clipboard — never prompt on empty/launch.** In `ClipboardCaptureCoordinator`, replace any `UIPasteboard.general.string`/content access used for *detection* with non-prompting detection:

```swift
// Detect WITHOUT prompting. Only read contents after the user taps the banner.
func refreshOffer() {
    guard UIPasteboard.general.hasStrings else { pendingOffer = nil; return }
    // Optionally: UIPasteboard.general.detectPatterns(for:) for typed hints.
    pendingOffer = ClipboardOffer()   // a "tap to paste" affordance, not the content
}
```

Move the actual `UIPasteboard.general.string` read into the banner's accept action (user-initiated), which is the only place a prompt is acceptable. Ensure `refreshOffer()` is what runs on Review `.onAppear`, not a content read.

- [ ] **Step 3: Build + manual verification.** Build. Then: clear both clipboards and cold-launch:

```bash
pbcopy < /dev/null; xcrun simctl pbcopy <DEVICE_ID> < /dev/null
xcrun simctl terminate <DEVICE_ID> com.mitsheth.anghkooey 2>/dev/null
xcrun simctl launch <DEVICE_ID> com.mitsheth.anghkooey
```
Screenshot. Expected: Review tab visible with **no** camera prompt and **no** paste prompt. (Device ID for current sim: `F3653C2C-7E19-4C2C-968E-2EA32E0B9A49`, but re-verify with `xcrun simctl list` — IDs drift, memory `feedback_ios26_sim_name`.)

- [ ] **Step 4: Regression** — confirm tapping into Capture (Q&A) still requests camera once and works; tapping the clipboard banner still prompts/pastes on user action.
- [ ] **Step 5: Commit**

```bash
git add App/Anghkooey/ContentView.swift \
        Packages/AnghkooeyUI/Sources/AnghkooeyUI/Camera/CameraView.swift \
        App/Anghkooey/Clipboard/ClipboardCaptureCoordinator.swift \
        App/Anghkooey/Clipboard/ClipboardBanner.swift
git commit -m "fix(m9): defer camera request + stop empty-clipboard paste prompt at launch"
```

---

## Workstream D — Review loop polish

### Task 8: Interval previews + session progress

**Files:**
- Modify: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewView.swift`
- Modify: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewSession.swift`

- [ ] **Step 1:** In `ReviewSession`, expose what the view needs to project intervals and show progress. Add (matching the session's existing scheduler/current-card access):

```swift
/// Seconds-until-next-due per rating for the current card, for button hints.
@MainActor var currentIntervals: [Rating: TimeInterval] {
    guard let card = currentSchedulingCard else { return [:] }
    return IntervalProjection.project(card: card, engine: scheduler, now: .now)
}
/// Cards remaining in this session (including the current one).
@MainActor var remainingCount: Int { /* queue.count, matching existing queue field */ }
```

Read `ReviewSession.swift` to find the current card snapshot and scheduler references and adapt the bodies (`currentSchedulingCard` must map the current `Card.Snapshot` → `SchedulingCard`; reuse whatever mapping the grade path already uses so projection matches real scheduling).

- [ ] **Step 2:** In `ReviewView`, under each grade button add the projected label:

```swift
private func gradeButton(_ rating: Rating, title: String, systemImage: String, tint: Color) -> some View {
    Button { grade(rating) } label: {
        VStack(spacing: 2) {
            Label(title, systemImage: systemImage)
            if let secs = session.currentIntervals[rating] {
                Text(IntervalProjection.label(seconds: secs))
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityLabel("next review in \(IntervalProjection.label(seconds: secs))")
            }
        }
    }
    .tint(tint)
}
```

Add a progress indicator at the top of the review content: `Text("\(session.remainingCount) left").font(.subheadline).foregroundStyle(.secondary)` (only while reviewing, not on the empty state).

- [ ] **Step 3: Build + manual sim check** — seed cards (see Task 11 loader, or the SQL seed used during review at `AppGroup/.../default.store`), reveal answer, confirm four buttons show interval labels and the "N left" counter decrements after grading.
- [ ] **Step 4:** Run full test suite (no logic regressions). Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewView.swift \
        Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewSession.swift
git commit -m "feat(m9): review interval previews + session progress"
```

---

### Task 9: Session-complete summary + card redesign

**Files:**
- Create: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewSummary.swift`
- Modify: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewScreen.swift` + `ReviewView.swift`
- Test: `App/AnghkooeyTests/ReviewSummaryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import AnghkooeyUI
import AnghkooeyCore

@Suite struct ReviewSummaryTests {
    @Test func computesAccuracyFromRatings() {
        var s = ReviewSummary()
        s.record(.good); s.record(.easy); s.record(.again); s.record(.hard)
        #expect(s.reviewed == 4)
        // "remembered" = good+easy = 2 of 4
        #expect(s.accuracyPercent == 50)
    }
    @Test func emptySummaryIsZero() {
        let s = ReviewSummary()
        #expect(s.reviewed == 0)
        #expect(s.accuracyPercent == 0)
    }
}
```

- [ ] **Step 2:** Run app test command. Expected: FAIL — `ReviewSummary` undefined.
- [ ] **Step 3: Implement** the model (view added in Step 4):

```swift
import Foundation
import AnghkooeyCore

/// Accumulates per-session review stats for the completion screen.
public struct ReviewSummary: Equatable, Sendable {
    public private(set) var reviewed = 0
    public private(set) var remembered = 0   // good + easy
    public init() {}

    public mutating func record(_ rating: Rating) {
        reviewed += 1
        if rating == .good || rating == .easy { remembered += 1 }
    }
    public var accuracyPercent: Int {
        guard reviewed > 0 else { return 0 }
        return Int((Double(remembered) / Double(reviewed) * 100).rounded())
    }
}
```

- [ ] **Step 4:** Run app test command (PASS, 2 tests). Then: have `ReviewSession` hold a `ReviewSummary`, call `record(rating)` in its grade path, and when the queue empties, `ReviewScreen` shows a summary card ("You reviewed **N** cards · **X%** remembered · 🔥 streak") above/replacing the bare "All caught up". Redesign the question/answer area in `ReviewView` into a framed card (`.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))`, prominent question font `.title2.weight(.semibold)`, answer `.title3` revealed below a divider) so it reads as a card, not floating text.
- [ ] **Step 5: Commit**

```bash
git add Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewSummary.swift \
        Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewScreen.swift \
        Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewView.swift \
        App/AnghkooeyTests/ReviewSummaryTests.swift
git commit -m "feat(m9): session-complete summary + framed review card"
```

---

## Workstream E — First-run onboarding + starter deck

### Task 10: Onboarding flow + completion flag

**Files:**
- Create: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Onboarding/OnboardingView.swift`
- Modify: `App/Anghkooey/ContentView.swift` (present onboarding when not completed)
- Test: `App/AnghkooeyTests/OnboardingStateTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import AnghkooeyUI

@Suite struct OnboardingStateTests {
    @Test func defaultsToNotCompleted() {
        let d = UserDefaults(suiteName: "test.onboarding.\(UUID())")!
        let s = OnboardingState(defaults: d)
        #expect(s.hasCompleted == false)
    }
    @Test func completePersists() {
        let d = UserDefaults(suiteName: "test.onboarding.\(UUID())")!
        let s = OnboardingState(defaults: d)
        s.complete()
        #expect(s.hasCompleted == true)
        #expect(OnboardingState(defaults: d).hasCompleted == true)
    }
}
```

- [ ] **Step 2:** Run app test command. Expected: FAIL — `OnboardingState` undefined.
- [ ] **Step 3: Implement** state + a 3-page view:

```swift
import SwiftUI

@MainActor @Observable
public final class OnboardingState {
    private let defaults: UserDefaults
    private let key = "hasCompletedOnboarding"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var hasCompleted: Bool { defaults.bool(forKey: key) }
    public func complete() { defaults.set(true, forKey: key) }
}

public struct OnboardingView: View {
    let onLoadSample: () -> Void
    let onFinish: () -> Void
    public init(onLoadSample: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.onLoadSample = onLoadSample; self.onFinish = onFinish
    }
    public var body: some View {
        TabView {
            page("Remember everything", "Snap a photo, paste text, or type — Anghkooey turns it into flashcards.", "camera.viewfinder")
            page("Fall behind, guilt-free", "Miss a few days? Turn on “I’m away” and your deck waits for you — no overdue pile-up.", "calendar.badge.clock")
            VStack(spacing: 20) {
                page("Start in seconds", "Load a sample deck to try a review right now, or add your own card.", "sparkles")
                Button("Load a sample deck") { onLoadSample(); onFinish() }.buttonStyle(.borderedProminent)
                Button("I’ll add my own") { onFinish() }
            }
        }
        .tabViewStyle(.page)
    }
    private func page(_ title: String, _ body: String, _ symbol: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 56)).foregroundStyle(.tint)
            Text(title).font(.title.bold())
            Text(body).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
        }
    }
}
```

- [ ] **Step 4:** Run app test command (PASS, 2 tests). In `ContentView` (or `AnghkooeyApp`), present `OnboardingView` as a `.fullScreenCover` when `!onboardingState.hasCompleted`; `onFinish` calls `onboardingState.complete()`; `onLoadSample` calls the Task 11 loader.
- [ ] **Step 5: Commit**

```bash
git add Packages/AnghkooeyUI/Sources/AnghkooeyUI/Onboarding/OnboardingView.swift \
        App/Anghkooey/ContentView.swift App/AnghkooeyTests/OnboardingStateTests.swift
git commit -m "feat(m9): guided first-run onboarding + completion flag"
```

---

### Task 11: SampleDeckLoader + bundled deck

**Files:**
- Create: `App/Anghkooey/SampleDeck/SampleDeck.json`
- Create: `App/Anghkooey/SampleDeck/SampleDeckLoader.swift`
- Test: `App/AnghkooeyTests/SampleDeckLoaderTests.swift`
- Modify: project resource membership so `SampleDeck.json` is bundled (xcodegen: add to app target `resources`/sources; then `make generate` + `python3 scripts/patch_privacy_info.py` per memory `feedback_xcodegen_xcprivacy_extensions`).

- [ ] **Step 1: Create the bundled deck** `SampleDeck.json` (~12 cards, mixed topics):

```json
[
  {"question": "What does 'spaced repetition' do?", "answer": "Schedules reviews right before you'd forget, so memory lasts with less work.", "tags": ["Anghkooey 101"]},
  {"question": "Capital of Japan?", "answer": "Tokyo", "tags": ["Geography"]},
  {"question": "Capital of Australia?", "answer": "Canberra", "tags": ["Geography"]},
  {"question": "How do you say 'thank you' in Spanish?", "answer": "Gracias", "tags": ["Spanish"]},
  {"question": "How do you say 'tomorrow' in Spanish?", "answer": "Mañana", "tags": ["Spanish"]},
  {"question": "The mitochondria is the ___ of the cell.", "answer": "powerhouse", "tags": ["Biology"]},
  {"question": "What molecule stores genetic information?", "answer": "DNA", "tags": ["Biology"]},
  {"question": "What is 7 × 8?", "answer": "56", "tags": ["Math"]},
  {"question": "Who wrote 'Romeo and Juliet'?", "answer": "William Shakespeare", "tags": ["Literature"]},
  {"question": "What year did the first iPhone launch?", "answer": "2007", "tags": ["Trivia"]},
  {"question": "What gas do plants absorb for photosynthesis?", "answer": "Carbon dioxide (CO₂)", "tags": ["Biology"]},
  {"question": "What does 'FSRS' schedule based on?", "answer": "Your memory's stability and difficulty for each card.", "tags": ["Anghkooey 101"]}
]
```

- [ ] **Step 2: Write the failing test**

```swift
import Testing
import Foundation
@testable import Anghkooey
import AnghkooeyCore

@MainActor @Suite struct SampleDeckLoaderTests {
    @Test func loadsBundledDeckIntoStore() async throws {
        let store = MockCardStore()
        let loader = SampleDeckLoader(store: store)
        let count = try await loader.load(now: .now)
        #expect(count >= 10)
        let all = try await store.allCards()
        #expect(all.count == count)
        #expect(all.contains { $0.tags.contains("Spanish") })
    }
}
```

- [ ] **Step 3: Implement**

```swift
import Foundation
import AnghkooeyCore

/// Loads the bundled starter deck so first-run users have something to review.
struct SampleDeckLoader {
    struct Entry: Decodable { let question: String; let answer: String; let tags: [String] }
    let store: any CardStoreProtocol
    var bundle: Bundle = .main

    @discardableResult
    func load(now: Date) async throws -> Int {
        guard let url = bundle.url(forResource: "SampleDeck", withExtension: "json") else { return 0 }
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
        for e in entries {
            _ = try await store.create(question: e.question, answer: e.answer,
                                       sourceSpan: "sample", tags: e.tags, now: now)
        }
        return entries.count
    }
}
```

(If `SampleDeckLoaderTests` can't find `SampleDeck.json` via `.main` in the test bundle, inject `bundle: Bundle(for:)`/`.module` in the test, or decode an inline fixture string — keep the production `load` reading `.main`.)

- [ ] **Step 4:** `make generate && python3 scripts/patch_privacy_info.py`, build, run app test command. Expected: PASS. Verify the app test target still has `GENERATE_INFOPLIST_FILE=YES` + scheme Testables entry (memory `feedback_app_test_target_wiring`).
- [ ] **Step 5: Commit**

```bash
git add App/Anghkooey/SampleDeck/ App/AnghkooeyTests/SampleDeckLoaderTests.swift App/Anghkooey.xcodeproj
git commit -m "feat(m9): bundled sample deck + loader for first-run"
```

---

### Task 12: Empty-state CTAs (Review + Library)

**Files:**
- Modify: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewScreen.swift`
- Modify: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Library/LibraryView.swift`

- [ ] **Step 1:** Replace the Review "All caught up" empty state (when the deck is genuinely empty, i.e. zero cards total) with an actionable `ContentUnavailableView` carrying buttons: **Add a card**, **Import from Anki**, **Load sample deck**. When the deck is non-empty but nothing is due, keep the existing/Task-9 "caught up + summary" state. Library's existing `ContentUnavailableView("No Cards Yet", ...)` gets the same three CTAs in its `actions:` slot.

```swift
ContentUnavailableView {
    Label("No cards yet", systemImage: "rectangle.stack")
} description: {
    Text("Add a card, import your Anki deck, or try a sample.")
} actions: {
    Button("Add a card") { showingCreate = true }.buttonStyle(.borderedProminent)
    Button("Import from Anki") { showingImport = true }
    Button("Load sample deck") { Task { try? await sampleLoader.load(now: .now); await load() } }
}
```

(Thread the `SampleDeckLoader` and create/import bindings into the views via init or environment, matching how `store` is already passed.)

- [ ] **Step 2:** Build + manual sim check — fresh install (erase app data) shows the actionable empty states; each button works.
- [ ] **Step 3: Commit**

```bash
git add Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewScreen.swift \
        Packages/AnghkooeyUI/Sources/AnghkooeyUI/Library/LibraryView.swift
git commit -m "feat(m9): actionable empty states (add / import / sample)"
```

---

## Workstream F — Cross-cutting trust

### Task 13: Silent-failure audit

**Files:** (review-and-fix; no new types)
- `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Library/LibraryView.swift` (`load()` swallows errors into `cards = []`)
- Any `try?` that hides user-visible failures touched in Tasks 3–12.

- [ ] **Step 1:** In `LibraryView.load()`, distinguish "no cards" from "load failed": on error, set an error flag and show a small inline "Couldn't load your cards. Pull to retry." instead of an empty list that looks like an empty deck.

```swift
@State private var loadFailed = false
private func load() async {
    isLoading = true; defer { isLoading = false }
    do { cards = try await store.allCards(); loadFailed = false }
    catch { loadFailed = true; UILog.library.error("Library load failed: \(error)") }
}
```

Render `loadFailed` as an error state distinct from the empty state.

- [ ] **Step 2:** Grep the touched files for `try?` and `catch {}` that drop user-visible errors; add logging (`UILog`/`CoreLog`) and, where the user is waiting on a result, a visible message. Leave fire-and-forget telemetry as-is.

```bash
grep -rn "try?\|catch {" Packages/AnghkooeyUI/Sources App/Anghkooey | grep -vi test
```

- [ ] **Step 3:** Build + full test suite. Commit:

```bash
git add -A && git commit -m "fix(m9): surface load/save failures instead of swallowing them"
```

---

### Task 14: Accessibility pass

**Files:** all new/changed views (editor, onboarding, review buttons, empty states).

- [ ] **Step 1:** Add VoiceOver labels/traits and verify Dynamic Type on each new surface:
  - Review grade buttons: `.accessibilityLabel("\(title), next review in \(interval)")` (interval already added in Task 8).
  - Editor: label the segmented control, fields, and tag chips; ensure Save state is announced (`.accessibilityHint`).
  - Onboarding: each page is an accessibility element with title+body combined; the two final buttons are clearly labeled.
  - Empty-state CTAs: buttons have descriptive labels.
- [ ] **Step 2:** Manual check at XXL Dynamic Type (Settings → Accessibility on sim) — no clipped/overlapping text on editor, onboarding, review. Fix with `ViewThatFits`/wrapping where needed.
- [ ] **Step 3:** Build + full suite. Commit:

```bash
git add -A && git commit -m "feat(m9): accessibility pass on new surfaces (VoiceOver + Dynamic Type)"
```

---

## Milestone exit (Opus)

- [ ] Run the **full Swift Testing suite** (Core + app). Expected: all green. Record counts.
- [ ] **Re-read `foundation.md` §4 bullet-by-bullet** against the build (memory `feedback_foundation_recheck_at_milestone_close`).
- [ ] **On-device QA** on a real Apple-Intelligence iPhone (cannot run on sim):
  - Q&A capture: camera → OCR → AI draft → accept → card created.
  - Cloze capture: live `LiveClozeAuthoringService` produces non-empty drafts.
  - AI-unavailable path (toggle Apple Intelligence off): capture/cloze shows the availability banner and routes to manual entry with any captured text preserved.
  - Re-validate torch/camera capture still works (deferred from M8 — memory `project_m8_complete`).
- [ ] Cold-launch check: **no** camera or paste prompt on first launch / Review tab.
- [ ] First-run: onboarding shows once; "Load a sample deck" populates Review + Library; empty states actionable.
- [ ] Append an **M9 section to `ARCHITECTURE.md`** (memory `reference_architecture_md.md`) and update `PERFORMANCE.md` only if review-render changed materially.
- [ ] Open PR; PR body itemizes gate states honestly, marking device-only items as "device-QA verified" vs "code-complete, device QA pending" (memory `feedback_code_complete_vs_pass`).

---

## Self-review notes (author)

- **Spec coverage:** A→Tasks 2-4; B→Tasks 5-6; C→Task 7; D→Tasks 8-9; E→Tasks 10-12; F→Tasks 13-14; on-device QA + a11y in exit gates. All six workstreams + exit gates covered.
- **Known adaptation points (call out, not placeholders):** exact signatures of `SchedulingCard.init`, `ClozeMarkupParser.parse`, `CardDraft.init`, `AuthoringError` cases, and the store's existing `update(...)` method must be matched against the real files when each task runs — each task says which file to read and instructs matching the existing API without changing the surrounding logic. These are existing symbols in the repo, not undefined types.
- **Type consistency:** `IntervalProjection.project/label`, `CardEditorViewModel.{mode,kind,canSave,save}`, `CaptureAvailabilityModel.{shouldOfferAI,bannerMessage}`, `ReviewSummary.{record,reviewed,accuracyPercent}`, `OnboardingState.{hasCompleted,complete}`, `SampleDeckLoader.load(now:)` are used consistently across tasks and tests.
