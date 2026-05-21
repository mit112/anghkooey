# M2 Design Spec — AnghkooeyIntelligence: Card Authoring Subsystem

> Status: approved for implementation planning
> Branch target: `m2/foundation-models`
> Depends on: M1 (`AnghkooeyCore` — `Card`, `CardState`, `Rating`, schema v1)
> Scope note: this spec covers the FoundationModels card-authoring service.
> OCR (`OCRService`) and the availability composition root are M2 tasks
> covered mechanically in the M2 implementation plan, not in this spec.

---

## 1. Goal

Add the card-authoring service to `AnghkooeyIntelligence` — a pure-logic Swift
package that takes a text passage and returns a stream of AI-authored
`CardDraft` values using Apple's FoundationModels framework
(`LanguageModelSession` + `@Generable`). No SwiftData import anywhere in the
package. No UI.

Closes iOS skill-map gap #1 (FoundationModels, `@Generable`, structured
streaming). Ships an eval harness with rubric-scored fixtures so CI can gate on
golden-set quality without a live model call.

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
- **Platform:** FoundationModels is available on iOS 26, macOS 26, and visionOS 26 —
  not macOS 15. The current `Package.swift` declares `.macOS(.v15)`. All
  FoundationModels imports must be wrapped in `#if canImport(FoundationModels)`
  guards, or the macOS minimum must be bumped to `.macOS(.v26)`. Resolve at M2
  task T1 before any authoring code lands.
- **Forbidden imports in `AnghkooeyIntelligence` sources:** `SwiftData`,
  `SwiftUI`, `UIKit` — enforced by extending `scripts/m1-forbidden-patterns.sh`

---

## 4. Type Surface

### 4.1 DTOs (Authoring/)

```swift
@Generable
public struct CardDraft: Sendable, Codable, Equatable {
    public var question: String
    public var answer: String
    public var proposedTags: [String]
    public var sourceSpan: String?        // excerpt from passage; nil if not isolatable
    public init(question: String, answer: String,
                proposedTags: [String] = [], sourceSpan: String? = nil) { ... }
}

@Generable
public struct AuthorResponse: Sendable {
    public var drafts: [CardDraft]
}
```

`Sendable` — required for Swift 6 strict concurrency across actor boundaries.
`Codable` — required for eval fixture serialisation.
`Equatable` — required for mock comparisons and rubric scorer.
Explicit `public init` — memberwise init is internal by default.
`sourceSpan` — field is in `Card` schema v1 (`Card.sourceSpan: String?`); populate
it from the passage so the UI can show "from" context without another model call.

### 4.2 Availability (Authoring/)

```swift
public enum AuthoringAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: UnavailableReason)

    public enum UnavailableReason: Sendable, Equatable {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
    }
}
```

Backed by `SystemLanguageModel.availability` at call time. The three reasons
map directly to the FoundationModels SDK enum; they drive the capture-screen
UI decision in M3 (hide AI path, show manual path, show "enable in Settings"
prompt — each reason needs a different string).

### 4.3 Error (Authoring/)

```swift
public enum AuthoringError: Error, Sendable {
    case emptyInput
    case unavailable(reason: AuthoringAvailability.UnavailableReason)
    case generationFailed(underlying: Error)
}
```

`modelUnavailable` replaced by `unavailable(reason:)` — callers get the reason
to drive UX decisions. `generationFailed` wraps the underlying FoundationModels
error (`assetsUnavailable`, `guardrailViolation`, `rateLimited`, `refusal`,
etc.) without discarding it.

### 4.4 Protocol (Authoring/)

```swift
public protocol CardAuthoringService: Sendable {
    var availability: AuthoringAvailability { get async }
    func generateDrafts(from text: String) async throws -> AsyncThrowingStream<CardDraft, Error>
}
```

`availability` — async probe backed by `SystemLanguageModel.availability`. The
UI layer calls this before presenting the AI capture path; `MockCardAuthoringService`
covers all three unavailability reasons in tests.

`async throws` on `generateDrafts` — lets the implementation validate input and
check availability before opening the stream, and lets an actor implementation
satisfy the requirement under Swift 6 strict concurrency.

No FoundationModels types leak through the protocol boundary.

### 4.5 Implementations (Authoring/)

**`LiveCardAuthoringService`** — production, wraps FoundationModels:
- `var availability: AuthoringAvailability` — queries `SystemLanguageModel.availability`
- Validates input (throws `AuthoringError.emptyInput`)
- Checks availability (throws `AuthoringError.unavailable(reason:)`)
- Creates `LanguageModelSession(instructions: Self.instructions)`
- Calls `session.streamResponse(to: text, generating: AuthorResponse.self)`
- Passes snapshots to `SnapshotAccumulator`; yields completed `CardDraft` values
- Wraps in `AsyncThrowingStream`; `onTermination` cancels the underlying `Task`
- Maps FoundationModels errors to `AuthoringError.generationFailed(underlying:)`

**`MockCardAuthoringService`** — test/eval, fixture-replay:
- Init takes `[CardDraft]`, optional `availability: AuthoringAvailability = .available`,
  and optional `shouldThrow: Error?`
- `var availability` returns the configured value
- Emits drafts one by one via `AsyncThrowingStream`
- Used by all unit tests and the CI eval harness

---

## 5. SnapshotAccumulator

Extracted pure reducer so the emit-once invariant is unit-testable without a
live model or `AsyncThrowingStream`.

```swift
// Internal type — not public API
struct SnapshotAccumulator {
    private var lastEmittedIndex: Int = -1

    /// Feed a new partial drafts array; returns any newly-completedCardDrafts.
    mutating func update(_ partialDrafts: [CardDraft.PartiallyGenerated]) -> [CardDraft]
}
```

`update(_:)` iterates indices `(lastEmittedIndex+1)..<partialDrafts.count`.
For each index `i`, if `partialDrafts[i].question` and `partialDrafts[i].answer`
are both non-empty, it constructs a `CardDraft` and advances `lastEmittedIndex`.
Returns all newly-completed drafts from this snapshot (may be empty, may be >1
if the model jumped ahead).

**Emit-once invariant:** each array index is emitted at most once. Later snapshot
refinements to the same slot are discarded. First-complete is final.

`LiveCardAuthoringService` holds a `SnapshotAccumulator` per call and pipes
snapshot content through it. The streaming loop becomes:

```swift
var accumulator = SnapshotAccumulator()
for try await snapshot in stream {
    for draft in accumulator.update(snapshot.content.drafts) {
        continuation.yield(draft)
    }
}
```

**UNVERIFIED:** `snapshot.content.drafts` element type is
`CardDraft.PartiallyGenerated` (macro-synthesised). The `.question` and
`.answer` fields are expected to be `String` (non-optional) that start empty
and fill in progressively. Confirm against a real simulator build at T1 —
adjust `SnapshotAccumulator.update` if the partial type uses optionals instead.

---

## 6. Data Flow

```
caller: generateDrafts(from: text) async throws
  │
  ├─ guard non-empty → else throw AuthoringError.emptyInput
  ├─ guard availability == .available → else throw AuthoringError.unavailable(reason:)
  │
  └─ return AsyncThrowingStream<CardDraft, Error> { continuation in
         let task = Task {
             do {
                 let session = LanguageModelSession(instructions: Self.instructions)
                 let stream = session.streamResponse(
                     to: text,
                     generating: AuthorResponse.self)
                 var accumulator = SnapshotAccumulator()
                 for try await snapshot in stream {
                     for draft in accumulator.update(snapshot.content.drafts) {
                         continuation.yield(draft)
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

---

## 7. Prompt Template

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
- The question must not contain or restate the answer.
- Propose 1–3 relevant topic tags per card (lowercase, no spaces).
Return only cards derivable from the passage. If the passage contains no
memorable facts, return an empty list.
```

The template is versioned via `templateVersion` in `EvalFixture`. Any prompt
change must produce a new `templateVersion` string and a new `make eval` run
committed alongside the diff (per strategic plan §4.2).

---

## 8. Eval Harness

### 8.1 Rubric (from strategic plan §4.2 — locked, do not drift)

Binary per card; all four required to pass:

| Criterion | Heuristic implementation |
|---|---|
| **Atomic** — one fact per card | Question contains no conjunction joining two independent clauses; length ≤ 120 chars |
| **Specific** — no vague reference | Answer ≥ 4 words; does not contain "above", "following", "described", "mentioned" |
| **Hallucination-free** — every fact traceable to input | Every non-stopword token in answer appears (case-insensitive) in source passage |
| **Q ≠ A** — question doesn't leak the answer | No contiguous 4-gram from the answer appears verbatim in the question |

**Scoring rules (locked):**
- A *card* passes iff all 4 criteria pass.
- An *input* passes iff **every** generated card from that input passes. One bad card fails the input.
- Pass-rate = passing inputs / total inputs. Target ≥ 80%.
- Eval runs at `temperature = 0`, fixed random seed. No retries.

### 8.2 Fixture Format (Eval/)

```swift
public struct EvalFixture: Codable, Sendable {
    public var id: String                  // e.g. "biology-001"
    public var passage: String             // input text
    public var templateVersion: String     // prompt version that produced goldens
    public var goldenDrafts: [CardDraft]   // expected output, checked in
}
```

Per-card and per-input rubric scores are computed at eval time, not stored in
the fixture — storing them would allow them to drift silently from the scorer
implementation. CI always re-derives scores from the golden drafts.

Fixtures at:
`Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Fixtures/eval-fixtures.json`
Loaded via `Bundle.module`. Initial count: ≥ 20 passages at milestone close;
grows to 100 before App Store submission per strategic plan §4.2.

### 8.3 Two Harness Modes

**CI mode** (runs in `AnghkooeyIntelligenceTests` on every PR):
- Loads fixtures via `Bundle.module`
- Scores each `goldenDraft` per the 4-criterion rubric
- Asserts every input passes (all cards pass, per scoring rules)
- Zero model calls — validates golden-set integrity, not live model quality

**Live mode** (`make eval`, developer-side, never on CI):
- Swift executable target `EvalRunner` in `Packages/AnghkooeyIntelligence`
  (not a test target; no XCTest/Swift Testing dependency)
- Runs on macOS host via `swift run EvalRunner` — no simulator plumbing needed
  because `LanguageModelSession` on macOS 26 is sufficient for eval
- Accepts `--fixtures <path>` (default: repo fixtures file) and
  `--update-goldens` flag (overwrites the fixtures file in place with new
  golden output)
- Prints per-input verdict and aggregate pass-rate to stdout
- With `--update-goldens`: writes updated JSON, prints diff summary, exits
  non-zero if pass-rate < 80% so `make eval` fails loudly

`Makefile` target:
```makefile
eval:
	swift run --package-path Packages/AnghkooeyIntelligence EvalRunner

eval-update:
	swift run --package-path Packages/AnghkooeyIntelligence EvalRunner --update-goldens
```

### 8.4 CI Gate

`scripts/ci.sh` gains an `AnghkooeyIntelligence` test step:
```bash
xcodebuild test \
  -scheme AnghkooeyIntelligence \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' \
  -resultBundlePath /tmp/anghkooey-m2.xcresult
```

`scripts/m1-forbidden-patterns.sh` extended:
- No `import SwiftData` in `AnghkooeyIntelligence/Sources/`
- No `import SwiftUI` or `import UIKit` in `AnghkooeyIntelligence/Sources/`

---

## 9. File Structure

```
Packages/AnghkooeyIntelligence/
  Sources/AnghkooeyIntelligence/
    Authoring/
      CardDraft.swift               @Generable + Sendable + Codable + Equatable
      AuthorResponse.swift          @Generable + Sendable
      AuthoringAvailability.swift   enum + UnavailableReason
      AuthoringError.swift          enum (emptyInput, unavailable, generationFailed)
      CardAuthoringService.swift    protocol
      LiveCardAuthoringService.swift
      MockCardAuthoringService.swift
      SnapshotAccumulator.swift     internal reducer
    Logging/
      IntelligenceLog.swift         (already exists)
  Sources/EvalRunner/               Swift executable target (live eval only)
    main.swift
  Tests/AnghkooeyIntelligenceTests/
    Authoring/
      SnapshotAccumulatorTests.swift
      MockCardAuthoringServiceTests.swift
      AuthoringErrorTests.swift
    Eval/
      RubricScorerTests.swift
      EvalFixtureGateTests.swift    @Test(arguments:) over fixtures — CI gate
    Fixtures/
      eval-fixtures.json
```

---

## 10. Module Seam

`AnghkooeyIntelligence` outputs `[CardDraft]`. It does not know about `Card`.

The conversion `Card(from: CardDraft)` is a `Card` extension or
`CardDraftReviewViewModel` responsibility in `AnghkooeyUI` (M3). When the user
taps "Add" on a reviewed draft, the ViewModel:
1. Maps `CardDraft` → `Card` (question, answer, proposedTags → Tag lookup/create,
   sourceSpan forwarded as-is)
2. Writes `Card` to the `ModelContext` from `AnghkooeyCore`
3. Tags resolved case-insensitively via `Tag.normalize(_:)` from M1

This conversion does not exist in M2 — documented here so M3 knows where to put it.

---

## 11. Test Plan

All tests use Swift Testing. `@Test(arguments:)` over fixture array for the CI gate.

| Test | File | What it covers |
|---|---|---|
| `emptyInputThrows` | `MockCardAuthoringServiceTests` | `generateDrafts(from: "")` throws `AuthoringError.emptyInput` |
| `unavailableThrows` × 3 reasons | `MockCardAuthoringServiceTests` | Each `UnavailableReason` surfaces via `AuthoringError.unavailable(reason:)` |
| `availabilityProbe` | `MockCardAuthoringServiceTests` | `availability` returns configured value |
| `mockEmitsDraftsInOrder` | `MockCardAuthoringServiceTests` | Stream yields drafts in order, then finishes |
| `accumulator_emitsOnFirstComplete` | `SnapshotAccumulatorTests` | Partial snapshot with only `question` → no emission |
| `accumulator_emitsOncePerIndex` | `SnapshotAccumulatorTests` | Second snapshot refining same index → no duplicate |
| `accumulator_multipleCompletionsOneSnapshot` | `SnapshotAccumulatorTests` | Model jumps two indices → two emissions in one `update` call |
| `cancellationStopsStream` | `MockCardAuthoringServiceTests` | Task cancel → `onTermination` fires, stream ends |
| `generationFailedWrapsError` | `AuthoringErrorTests` | `generationFailed` preserves `underlying` without data loss |
| `rubricScorer_atomicFail` | `RubricScorerTests` | Compound question fails atomicity |
| `rubricScorer_qEqualsAFail` | `RubricScorerTests` | Answer 4-gram in question fails Q≠A |
| `rubricScorer_hallucinationFail` | `RubricScorerTests` | Token not in passage fails groundedness |
| `goldenFixturesPassGate` | `EvalFixtureGateTests` | `@Test(arguments:)` — every fixture: every card passes all 4 criteria |

---

## 12. M1 Carry-Overs Addressed in M2

| Item | Resolution |
|---|---|
| `CoreLog.subsystem` is `nonisolated(unsafe) static var` | M2 wires real bundle ID via `CoreLog.configure(subsystem:)` in app init |
| First additive schema change needs explicit no-op `MigrationStage` | If M2 populates `Card.sourceSpan`, a no-op stage is added to `AnghkooeyMigrationPlan` |
| Long-term FSRS scheduler unspecialised | Not addressed in M2; remains documented caveat |

---

## 13. Exit Gate (M2 — card authoring subsystem)

- `LiveCardAuthoringService` compiles under `#if canImport(FoundationModels)`;
  streams `CardDraft` values from a real `LanguageModelSession` on iOS 26 Simulator
- All tests in §11 pass
- CI rubric gate: all golden fixtures pass (every card, every input)
- Forbidden-pattern check green (no SwiftData/SwiftUI/UIKit in Intelligence sources)
- `ARCHITECTURE.md` updated with M2 section
- DocC on all public APIs
- `make eval` runs end-to-end; aggregate pass-rate ≥ 80% on ≥ 20 fixture passages;
  result logged in commit message alongside any prompt change
- UNVERIFIED items in §5 resolved against real simulator build
