# M2 Design Spec — AnghkooeyIntelligence: On-Device Card Authoring

> Status: approved for implementation planning
> Branch target: `m2/foundation-models`
> Depends on: M1 (`AnghkooeyCore` — `Card`, `CardState`, `Rating`, schema v1)

---

## 1. Goal

Add `AnghkooeyIntelligence` — a pure-logic Swift package that takes a text passage and returns a stream of AI-authored `CardDraft` values using Apple's FoundationModels framework (`LanguageModelSession` + `@Generable`). No SwiftData import anywhere in the package. No UI. No Tool use.

Closes iOS skill-map gap #1 (FoundationModels, `@Generable`, structured streaming). Ships an eval harness with rubric-scored fixtures so CI can gate on golden-set quality without a live model call.

---

## 2. Locked Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Snapshot streaming via `ResponseStream<AuthorResponse>.Snapshot` | Correct FoundationModels API; better UX than full-response (progressive card population); confirmed from SDK `.swiftinterface` |
| D2 | `CardDraft` lives in Intelligence; `Card(from: CardDraft)` lives in `AnghkooeyUI` ViewModel | Intelligence stays import-clean from SwiftData; conversion is co-located with the user-confirmation business logic |
| D3 | Fixture-based offline eval; CI scores golden set against rubric only; live model run is developer-side `make eval` | FoundationModels requires iOS 26 sim with model present — not available on standard CI runners; mirrors M1 parity harness pattern |
| D4 | Custom `Tool` deferred | No concrete use case for v1 authoring flow; a toy Tool is worse portfolio signal than no Tool |

---

## 3. Package Constraints

- `AnghkooeyIntelligence` already depends on `AnghkooeyCore` (per `Package.swift`)
- Swift 6 strict concurrency (`swiftLanguageModes: [.v6]`)
- Platform floor: iOS 26 / macOS 15 (existing `Package.swift`)
- **Forbidden imports in `AnghkooeyIntelligence` sources:** `SwiftData`, `SwiftUI`, `UIKit` — enforced by extending `scripts/m1-forbidden-patterns.sh`
- FoundationModels is iOS 26 only; the `macOS(.v15)` platform entry in `Package.swift` must be gated with `#if canImport(FoundationModels)` or the macOS target removed for M2

---

## 4. Type Surface

### 4.1 DTOs (Authoring/)

```swift
@Generable
public struct CardDraft: Sendable, Codable, Equatable {
    public var question: String
    public var answer: String
    public var proposedTags: [String]
    public init(question: String, answer: String, proposedTags: [String] = []) {
        self.question = question
        self.answer = answer
        self.proposedTags = proposedTags
    }
}

@Generable
public struct AuthorResponse: Sendable {
    public var drafts: [CardDraft]
}
```

`Sendable` — required for Swift 6 strict concurrency across actor boundaries.
`Codable` — required for eval fixture serialisation.
`Equatable` — required for mock comparisons and rubric scorer.
Explicit `public init` — memberwise init is internal by default; other modules (tests, UI) need to construct `CardDraft` directly.

### 4.2 Error (Authoring/)

```swift
public enum AuthoringError: Error, Sendable {
    case modelUnavailable
    case emptyInput
    case generationFailed(underlying: Error)
}
```

`generationFailed` wraps the underlying FoundationModels error (e.g. `assetsUnavailable`, `guardrailViolation`, `rateLimited`, `refusal`) without discarding it. Callers can inspect `underlying` for retry decisions.

### 4.3 Protocol (Authoring/)

```swift
public protocol CardAuthoringService: Sendable {
    func generateDrafts(from text: String) async throws -> AsyncThrowingStream<CardDraft, Error>
}
```

`async throws` on the method (not just on the stream elements) lets the implementation:
- Validate input and throw `AuthoringError.emptyInput` before opening the stream
- Handle model availability synchronously before opening the stream
- Be implemented by an actor without violating Swift 6 protocol witness rules

The stream itself carries `CardDraft` values only — no FoundationModels types leak through the protocol boundary.

### 4.4 Implementations (Authoring/)

**`LiveCardAuthoringService`** — production, wraps FoundationModels:
- Owns prompt template as `static let instructions: String`
- Validates input, creates `LanguageModelSession(instructions:)`
- Calls `session.streamResponse(generating: AuthorResponse.self)`
- Iterates `ResponseStream<AuthorResponse>.Snapshot` values
- Tracks `lastEmittedIndex: Int`; emits `CardDraft` at index `i` the first time `drafts[i].question` and `drafts[i].answer` are both non-empty
- Wraps in `AsyncThrowingStream`; `onTermination` cancels the underlying `Task`
- Maps FoundationModels errors to `AuthoringError.generationFailed(underlying:)`

**`MockCardAuthoringService`** — test/eval, fixture-replay:
- Init takes `[CardDraft]` (the drafts to emit) and optional `shouldThrow: Error?`
- Emits drafts one by one via `AsyncThrowingStream`
- Used by all unit tests and the CI eval harness (no FoundationModels dependency)

---

## 5. Data Flow

```
caller: generateDrafts(from: text) async throws
  │
  ├─ guard non-empty input → else throw AuthoringError.emptyInput
  │
  ├─ (model availability check — wrap session init in do/catch;
  │   map assetsUnavailable → AuthoringError.modelUnavailable)
  │
  └─ return AsyncThrowingStream<CardDraft, Error> { continuation in
         let task = Task {
             do {
                 let session = LanguageModelSession(instructions: Self.instructions)
                 let stream = session.streamResponse(generating: AuthorResponse.self)
                 var lastEmittedIndex = -1
                 for try await snapshot in stream {
                     let drafts = snapshot.content.drafts   // AuthorResponse.PartiallyGenerated
                     for i in (lastEmittedIndex + 1)..<drafts.count {
                         let d = drafts[i]
                         if !d.question.isEmpty && !d.answer.isEmpty {
                             continuation.yield(
                                 CardDraft(question: d.question,
                                           answer: d.answer,
                                           proposedTags: d.proposedTags))
                             lastEmittedIndex = i
                         }
                     }
                 }
                 continuation.finish()
             } catch {
                 continuation.finish(
                     throwing: AuthoringError.generationFailed(underlying: error))
             }
         }
         continuation.onTermination = { _ in task.cancel() }
     }
```

**Emit-once invariant:** each array index is emitted at most once, the first time both fields are non-empty. Later snapshot refinements to the same slot are discarded. This is intentional — the protocol surface has no update event; first-complete is final.

**UNVERIFIED:** `snapshot.content` field name and `AuthorResponse.PartiallyGenerated` member layout are inferred from SDK `.swiftinterface` plus Codex SDK inspection. The macro-synthesised partial type is not fully represented in the interface file. Implement defensively; test with a real simulator early.

---

## 6. Prompt Template

`LiveCardAuthoringService.instructions` (static constant, not inline):

```
You are a spaced-repetition card author. Given a passage of text, generate
atomic question-and-answer flashcard pairs that test recall of specific facts
in the passage. Rules:
- Each card tests exactly one fact.
- Do not invent or infer facts not present in the passage.
- Questions must be specific enough that only someone who read the passage
  can answer them.
- Answers must be concise (1–2 sentences maximum).
- Propose 1–3 relevant topic tags per card (lowercase, no spaces).
Return only cards derivable from the passage. If the passage contains no
memorable facts, return an empty list.
```

The template is the primary quality lever. It is versioned via `templateVersion` in `EvalFixture` so fixture runs are traceable to the template that generated them.

---

## 7. Eval Harness

### 7.1 Fixture Format (Eval/)

```swift
public struct EvalFixture: Codable, Sendable {
    public var id: String               // e.g. "biology-001"
    public var passage: String          // input text fed to the service
    public var templateVersion: String  // prompt template version that produced goldens
    public var goldenDrafts: [CardDraft]
    public var rubricScores: RubricScore  // pre-computed scores for the golden set
}

public struct RubricScore: Codable, Sendable {
    public var atomicity: Double      // 0.0–1.0
    public var specificity: Double    // 0.0–1.0
    public var groundedness: Double   // 0.0–1.0
    public var overall: Double        // mean of above three
}
```

Fixtures at: `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Fixtures/eval-fixtures.json`
Loaded via `Bundle.module` (same pattern as M1 FSRS parity fixtures).
Initial fixture count: ≥ 20 passages at milestone close; grows toward 100 before App Store submission per `foundation.md §7`.

### 7.2 RubricScorer — Pure String Logic (Eval/)

| Dimension | Heuristic | Rationale |
|---|---|---|
| Atomicity | Question contains no "and"/"or" joining two independent clauses; length ≤ 120 chars | Detects compound questions mechanically |
| Specificity | Answer ≥ 4 words; not composed entirely of stopwords | Guards against vague one-word answers |
| Groundedness | Every non-stopword token in answer appears (case-insensitive) in source passage | Mechanically catches hallucinations |

Groundedness has the most real signal. Atomicity and specificity are weak heuristics, cheap enough to run on CI.

### 7.3 Two Harness Modes

**CI mode** (runs as part of `AnghkooeyIntelligenceTests` on every PR):
- Loads fixtures from `Bundle.module`
- Scores each `goldenDraft` in each fixture with `RubricScorer`
- Asserts `rubricScore.overall ≥ 0.80` for every fixture
- Zero model calls — validates golden set integrity, not live model quality
- Fail = rubric regression or corrupted fixture

**Live mode** (`make eval`, developer-side only, never on CI):
- Instantiates `LiveCardAuthoringService` with real `LanguageModelSession`
- Runs each fixture's `passage` through the live model
- Scores returned drafts, prints per-fixture and aggregate report
- Pass `--update-goldens` to overwrite `eval-fixtures.json` with new golden output
- Requires: iOS 26 simulator with on-device model downloaded

### 7.4 CI Gate

`scripts/ci.sh` gains an `AnghkooeyIntelligence` test step:
```bash
xcodebuild test \
  -scheme AnghkooeyIntelligence \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' \
  -resultBundlePath /tmp/anghkooey-m2.xcresult
```

`scripts/m1-forbidden-patterns.sh` extended with Intelligence-specific checks:
- No `import SwiftData` in `AnghkooeyIntelligence/Sources/`
- No `import SwiftUI` or `import UIKit` in `AnghkooeyIntelligence/Sources/`

---

## 8. Module Seam

`AnghkooeyIntelligence` outputs `[CardDraft]`. It does not know about `Card`.

The conversion `Card(from: CardDraft)` is a `Card` extension or `CardDraftReviewViewModel` responsibility in `AnghkooeyUI` (M3). When the user taps "Add" on a reviewed draft, the ViewModel:
1. Maps `CardDraft` → `Card` (question, answer, proposedTags → Tag lookup/create)
2. Writes `Card` to the `ModelContext` from `AnghkooeyCore`
3. Tags resolved case-insensitively via `Tag.normalize(_:)` from M1

This conversion does not exist in M2 — it is documented here so M3 knows where to put it.

---

## 9. Test Plan

All tests use Swift Testing (`@Test`, `@Suite`). `@Test(arguments:)` over fixture array for the rubric gate.

| Test | Framework | What it covers |
|---|---|---|
| `emptyInputThrows` | Swift Testing | `generateDrafts(from: "")` throws `AuthoringError.emptyInput` |
| `mockEmitsDraftsInOrder` | Swift Testing | `MockCardAuthoringService` yields expected drafts in sequence |
| `partialSnapshotNotEmitted` | Swift Testing | Draft with only `question` set does not appear in stream |
| `cancellationStopsStream` | Swift Testing | `Task.cancel()` on consumer terminates stream without error |
| `generationFailedWrapsError` | Swift Testing | `AuthoringError.generationFailed` preserves `underlying` |
| `goldenFixturesPassRubric` | Swift Testing, `@Test(arguments:)` | All golden drafts score ≥ 0.80 overall (CI gate) |

---

## 10. M1 Carry-Overs Addressed in M2

| Item | Resolution |
|---|---|
| `CoreLog.subsystem` is `nonisolated(unsafe) static var` | M2 wires real bundle ID (`com.<author>.anghkooey`) via a `CoreLog.configure(subsystem:)` call in app init |
| First additive schema change needs explicit no-op `MigrationStage` | If M2 adds any field to `Card` (e.g. `sourceSpan` population), a no-op `MigrationStage` is added to `AnghkooeyMigrationPlan` to lock in the habit |
| Long-term FSRS scheduler unspecialised | Not addressed in M2; remains documented caveat |

---

## 11. Exit Gate (M2)

- `LiveCardAuthoringService` compiles and streams `CardDraft` values from a real `LanguageModelSession` on iOS 26 Simulator
- All 6 unit tests pass
- CI rubric gate: all golden fixtures score ≥ 0.80 overall
- Forbidden-pattern check green (no SwiftData/SwiftUI/UIKit in Intelligence sources)
- `ARCHITECTURE.md` updated with M2 section
- DocC on all public APIs
- `make eval` runs end-to-end on developer machine with ≥ 20 fixture passages; aggregate score logged
- `UNVERIFIED` items in §5 resolved against real simulator build (snapshot field names confirmed or corrected)
