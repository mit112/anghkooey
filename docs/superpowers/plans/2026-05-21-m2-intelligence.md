# M2 AnghkooeyIntelligence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the `AnghkooeyIntelligence` package — streaming card authoring via FoundationModels, an OCR service, availability probing, a rubric-scored eval harness, and an `EvalRunner` CLI — all behind `CardAuthoringService` / `OCRService` protocols with Live + Mock implementations.

**Architecture:** Pure-logic SPM package; no SwiftData, SwiftUI, or UIKit imports in `Sources/`. `LiveCardAuthoringService` streams `CardDraft` values via `LanguageModelSession.streamResponse(to:generating:)`; a `SnapshotAccumulator` reducer extracts completed drafts from `PartiallyGenerated` snapshots. Eval harness splits into a CI fixture-rubric gate (no model calls) and a developer-side `EvalRunner` executable that hits the live model and can update golden fixtures.

**Tech Stack:** Swift 6, iOS 26 / macOS 26, FoundationModels (`@Generable`, `LanguageModelSession`), Vision (`VNRecognizeTextRequest`), Swift Testing (`@Test`, `@Suite`, `@Test(arguments:)`), Swift Argument Parser (for EvalRunner CLI), CoreGraphics.

---

## File Map

```
Packages/AnghkooeyIntelligence/
  Package.swift                                         MODIFY — bump macOS, add EvalRunner target, add ArgumentParser dep
  Sources/AnghkooeyIntelligence/
    Authoring/
      CardDraft.swift                                   CREATE
      AuthorResponse.swift                              CREATE
      AuthoringAvailability.swift                       CREATE
      AuthoringError.swift                              CREATE
      CardAuthoringService.swift                        CREATE
      SnapshotAccumulator.swift                         CREATE (internal)
      LiveCardAuthoringService.swift                    CREATE
      MockCardAuthoringService.swift                    CREATE
    OCR/
      OCRService.swift                                  CREATE
      LiveOCRService.swift                              CREATE
      MockOCRService.swift                              CREATE
    Eval/
      EvalFixture.swift                                 CREATE
      RubricScorer.swift                                CREATE
    Logging/
      IntelligenceLog.swift                             EXISTS (no change)
  Sources/EvalRunner/
    main.swift                                          CREATE
  Tests/AnghkooeyIntelligenceTests/
    Authoring/
      CardDraftTests.swift                              CREATE
      SnapshotAccumulatorTests.swift                    CREATE
      MockCardAuthoringServiceTests.swift               CREATE
    OCR/
      MockOCRServiceTests.swift                         CREATE
    Eval/
      RubricScorerTests.swift                           CREATE
      EvalFixtureGateTests.swift                        CREATE (CI rubric gate)
    Fixtures/
      eval-fixtures.json                                CREATE
  Makefile                                              CREATE (at package root)
Packages/AnghkooeyCore/
  Sources/AnghkooeyCore/Logging/CoreLog.swift           MODIFY — add configure(subsystem:)
scripts/
  m1-forbidden-patterns.sh                              MODIFY — add Intelligence checks
  ci.sh                                                 MODIFY — update Intelligence test step
ARCHITECTURE.md                                         MODIFY — append M2 section
```

---

## Task 1: Package.swift — platform, EvalRunner target, ArgumentParser

**Files:**
- Modify: `Packages/AnghkooeyIntelligence/Package.swift`

- [ ] **Step 1: Update Package.swift**

Replace the entire file with:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AnghkooeyIntelligence",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "AnghkooeyIntelligence", targets: ["AnghkooeyIntelligence"]),
        .executable(name: "EvalRunner", targets: ["EvalRunner"])
    ],
    dependencies: [
        .package(path: "../AnghkooeyCore"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "AnghkooeyIntelligence",
            dependencies: ["AnghkooeyCore"]
        ),
        .executableTarget(
            name: "EvalRunner",
            dependencies: [
                "AnghkooeyIntelligence",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/EvalRunner"
        ),
        .testTarget(
            name: "AnghkooeyIntelligenceTests",
            dependencies: ["AnghkooeyIntelligence"],
            resources: [.process("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 2: Resolve packages**

```bash
cd Packages/AnghkooeyIntelligence && swift package resolve
```

Expected: Resolves `swift-argument-parser`. No errors.

- [ ] **Step 3: Extend forbidden-pattern check for Intelligence**

In `scripts/m1-forbidden-patterns.sh`, after the existing `PATTERNS=(...)` block and before the `EXIT=0` line, add:

```bash
# M2 — AnghkooeyIntelligence source checks
INT_SRC="${ROOT}/Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence"
INT_PATTERNS=(
  'import SwiftData'
  'import SwiftUI'
  'import UIKit'
)

for pattern in "${INT_PATTERNS[@]}"; do
  if rg --no-heading --line-number --color=never \
        -e "${pattern}" "${INT_SRC}" 2>/dev/null; then
    echo "  ↑ forbidden pattern in AnghkooeyIntelligence: ${pattern}" >&2
    EXIT=1
  fi
done
```

- [ ] **Step 4: Run forbidden-pattern check to confirm it passes on the empty package**

```bash
bash scripts/m1-forbidden-patterns.sh
```

Expected: `M1 forbidden-pattern check: OK`

- [ ] **Step 5: Commit**

```bash
git add Packages/AnghkooeyIntelligence/Package.swift scripts/m1-forbidden-patterns.sh
git commit -m "chore(m2): bump Intelligence macOS platform, add EvalRunner target, extend forbidden-pattern check"
```

---

## Task 2: CardDraft + AuthorResponse DTOs

**Files:**
- Create: `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/CardDraft.swift`
- Create: `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/AuthorResponse.swift`
- Create: `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Authoring/CardDraftTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Authoring/CardDraftTests.swift`:

```swift
import Testing
@testable import AnghkooeyIntelligence

@Suite("CardDraft")
struct CardDraftTests {

    @Test("default init sets empty proposedTags and nil sourceSpan")
    func defaultInit() {
        let draft = CardDraft(question: "Q", answer: "A")
        #expect(draft.proposedTags == [])
        #expect(draft.sourceSpan == nil)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let draft = CardDraft(question: "Q", answer: "A",
                              proposedTags: ["tag1"], sourceSpan: "span")
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(CardDraft.self, from: data)
        #expect(decoded == draft)
    }

    @Test("Equatable: different question → not equal")
    func equatable() {
        let a = CardDraft(question: "Q1", answer: "A")
        let b = CardDraft(question: "Q2", answer: "A")
        #expect(a != b)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd Packages/AnghkooeyIntelligence && swift test --filter CardDraftTests 2>&1 | tail -5
```

Expected: compile error — `CardDraft` not found.

- [ ] **Step 3: Create CardDraft.swift**

Create `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/CardDraft.swift`:

```swift
import FoundationModels

/// A candidate Q&A flashcard produced by the AI authoring pipeline.
///
/// `CardDraft` is the output unit of `CardAuthoringService`. It does not
/// map to `Card` directly — conversion happens in `AnghkooeyUI` after the
/// user reviews and accepts the draft.
@Generable
public struct CardDraft: Sendable, Codable, Equatable {
    /// The recall prompt shown to the user during review.
    public var question: String
    /// The expected answer.
    public var answer: String
    /// AI-proposed tag names (lowercase, no spaces). User edits before persistence.
    public var proposedTags: [String]
    /// The verbatim excerpt from the source passage this card was derived from.
    /// `nil` when the model cannot isolate a single span.
    public var sourceSpan: String?

    public init(question: String,
                answer: String,
                proposedTags: [String] = [],
                sourceSpan: String? = nil) {
        self.question = question
        self.answer = answer
        self.proposedTags = proposedTags
        self.sourceSpan = sourceSpan
    }
}
```

- [ ] **Step 4: Create AuthorResponse.swift**

Create `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/AuthorResponse.swift`:

```swift
import FoundationModels

/// The top-level structured output requested from `LanguageModelSession`.
///
/// Wraps the array so `@Generable` can generate the full set atomically.
@Generable
public struct AuthorResponse: Sendable {
    /// All candidate cards for the submitted passage.
    public var drafts: [CardDraft]
}
```

- [ ] **Step 5: Run tests**

```bash
cd Packages/AnghkooeyIntelligence && swift test --filter CardDraftTests 2>&1 | tail -5
```

Expected: `Test run with 3 tests passed.`

- [ ] **Step 6: Commit**

```bash
git add Packages/AnghkooeyIntelligence/Sources Packages/AnghkooeyIntelligence/Tests
git commit -m "feat(m2): CardDraft + AuthorResponse @Generable DTOs"
```

---

## Task 3: AuthoringAvailability + AuthoringError

**Files:**
- Create: `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/AuthoringAvailability.swift`
- Create: `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/AuthoringError.swift`

- [ ] **Step 1: Create AuthoringAvailability.swift**

```swift
/// Runtime availability of the on-device AI authoring model.
///
/// Maps `SystemLanguageModel.availability` into a stable product-level enum
/// so the UI layer can make UX decisions without importing FoundationModels.
public enum AuthoringAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: UnavailableReason)

    /// The reason the model is not available.
    ///
    /// - `deviceNotEligible`: hardware does not support Apple Intelligence.
    /// - `appleIntelligenceNotEnabled`: user has not enabled it in Settings.
    /// - `modelNotReady`: eligible device but model not yet downloaded.
    public enum UnavailableReason: Sendable, Equatable {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
    }
}
```

- [ ] **Step 2: Create AuthoringError.swift**

```swift
/// Errors thrown by `CardAuthoringService.generateDrafts(from:)`.
public enum AuthoringError: Error, Sendable {
    /// The input text was empty or whitespace-only.
    case emptyInput
    /// The on-device model is not available. Inspect `reason` to drive UX.
    case unavailable(reason: AuthoringAvailability.UnavailableReason)
    /// FoundationModels threw an error during generation.
    /// Inspect `underlying` for retry decisions (e.g. `.rateLimited`).
    case generationFailed(underlying: Error)
}
```

- [ ] **Step 3: Build to confirm no errors**

```bash
cd Packages/AnghkooeyIntelligence && swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/AuthoringAvailability.swift \
        Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/AuthoringError.swift
git commit -m "feat(m2): AuthoringAvailability + AuthoringError"
```

---

## Task 4: SnapshotAccumulator

The accumulator is an internal pure reducer — no FoundationModels dependency, fully unit-testable.

**Files:**
- Create: `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/SnapshotAccumulator.swift`
- Create: `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Authoring/SnapshotAccumulatorTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Authoring/SnapshotAccumulatorTests.swift`:

```swift
import Testing
@testable import AnghkooeyIntelligence

@Suite("SnapshotAccumulator")
struct SnapshotAccumulatorTests {

    @Test("partial draft with only question does not emit")
    func partialQuestionOnly() {
        var acc = SnapshotAccumulator()
        let result = acc.update([.init(question: "Q", answer: "", proposedTags: [], sourceSpan: nil)])
        #expect(result.isEmpty)
    }

    @Test("partial draft with only answer does not emit")
    func partialAnswerOnly() {
        var acc = SnapshotAccumulator()
        let result = acc.update([.init(question: "", answer: "A", proposedTags: [], sourceSpan: nil)])
        #expect(result.isEmpty)
    }

    @Test("completed draft emits exactly once")
    func emitsOnce() {
        var acc = SnapshotAccumulator()
        let partial = SnapshotAccumulator.PartialDraft(
            question: "Q", answer: "A", proposedTags: ["t"], sourceSpan: "span")
        let first = acc.update([partial])
        let second = acc.update([partial])   // same snapshot again
        #expect(first.count == 1)
        #expect(first[0] == CardDraft(question: "Q", answer: "A",
                                      proposedTags: ["t"], sourceSpan: "span"))
        #expect(second.isEmpty)
    }

    @Test("second draft becomes available in later snapshot")
    func secondDraftLater() {
        var acc = SnapshotAccumulator()
        let d1 = SnapshotAccumulator.PartialDraft(question: "Q1", answer: "A1",
                                                   proposedTags: [], sourceSpan: nil)
        let d2 = SnapshotAccumulator.PartialDraft(question: "Q2", answer: "A2",
                                                   proposedTags: [], sourceSpan: nil)
        let first = acc.update([d1, .init(question: "Q2", answer: "", proposedTags: [], sourceSpan: nil)])
        let second = acc.update([d1, d2])
        #expect(first.count == 1)
        #expect(first[0].question == "Q1")
        #expect(second.count == 1)
        #expect(second[0].question == "Q2")
    }

    @Test("two drafts complete in one snapshot both emitted")
    func twoCompletionsOneUpdate() {
        var acc = SnapshotAccumulator()
        let partials = [
            SnapshotAccumulator.PartialDraft(question: "Q1", answer: "A1", proposedTags: [], sourceSpan: nil),
            SnapshotAccumulator.PartialDraft(question: "Q2", answer: "A2", proposedTags: [], sourceSpan: nil)
        ]
        let result = acc.update(partials)
        #expect(result.count == 2)
        #expect(result[0].question == "Q1")
        #expect(result[1].question == "Q2")
    }

    @Test("empty snapshot produces no output")
    func emptySnapshot() {
        var acc = SnapshotAccumulator()
        #expect(acc.update([]).isEmpty)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd Packages/AnghkooeyIntelligence && swift test --filter SnapshotAccumulatorTests 2>&1 | tail -5
```

Expected: compile error — `SnapshotAccumulator` not found.

- [ ] **Step 3: Create SnapshotAccumulator.swift**

Create `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/SnapshotAccumulator.swift`:

```swift
/// Internal reducer that converts a sequence of `PartiallyGenerated` snapshot
/// arrays into a stream of completed `CardDraft` values.
///
/// `LiveCardAuthoringService` maps `snapshot.content.drafts` to
/// `[PartialDraft]` before calling `update(_:)`, keeping FoundationModels
/// types out of this file and making it fully unit-testable.
struct SnapshotAccumulator {

    /// A plain-value mirror of one `CardDraft.PartiallyGenerated` element.
    struct PartialDraft {
        var question: String
        var answer: String
        var proposedTags: [String]
        var sourceSpan: String?
    }

    private var lastEmittedIndex: Int = -1

    /// Feed the latest partial drafts array; returns newly-completed `CardDraft` values.
    ///
    /// Each array index is emitted at most once — the first time both
    /// `question` and `answer` are non-empty. Later refinements to an already-
    /// emitted index are ignored.
    mutating func update(_ partials: [PartialDraft]) -> [CardDraft] {
        var result: [CardDraft] = []
        let start = lastEmittedIndex + 1
        guard start < partials.count else { return result }
        for i in start..<partials.count {
            let p = partials[i]
            guard !p.question.isEmpty, !p.answer.isEmpty else { continue }
            result.append(CardDraft(
                question: p.question,
                answer: p.answer,
                proposedTags: p.proposedTags,
                sourceSpan: p.sourceSpan
            ))
            lastEmittedIndex = i
        }
        return result
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd Packages/AnghkooeyIntelligence && swift test --filter SnapshotAccumulatorTests 2>&1 | tail -5
```

Expected: `Test run with 6 tests passed.`

- [ ] **Step 5: Commit**

```bash
git add Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/SnapshotAccumulator.swift \
        Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Authoring/SnapshotAccumulatorTests.swift
git commit -m "feat(m2): SnapshotAccumulator — emit-once reducer for PartiallyGenerated snapshots"
```

---

## Task 5: CardAuthoringService protocol + MockCardAuthoringService

**Files:**
- Create: `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/CardAuthoringService.swift`
- Create: `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/MockCardAuthoringService.swift`
- Create: `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Authoring/MockCardAuthoringServiceTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Authoring/MockCardAuthoringServiceTests.swift`:

```swift
import Testing
@testable import AnghkooeyIntelligence

@Suite("MockCardAuthoringService")
struct MockCardAuthoringServiceTests {

    @Test("empty input throws AuthoringError.emptyInput")
    func emptyInput() async throws {
        let svc = MockCardAuthoringService()
        await #expect(throws: AuthoringError.emptyInput) {
            _ = try await svc.generateDrafts(from: "   ")
        }
    }

    @Test("availability: available returns .available")
    func availabilityAvailable() async {
        let svc = MockCardAuthoringService()
        let avail = await svc.availability
        #expect(avail == .available)
    }

    @Test("availability: unavailable(deviceNotEligible) surfaces correctly")
    func availabilityDeviceNotEligible() async throws {
        let svc = MockCardAuthoringService(
            availability: .unavailable(reason: .deviceNotEligible))
        await #expect(throws: AuthoringError.unavailable(reason: .deviceNotEligible)) {
            _ = try await svc.generateDrafts(from: "some text")
        }
    }

    @Test("availability: unavailable(appleIntelligenceNotEnabled) surfaces correctly")
    func availabilityNotEnabled() async throws {
        let svc = MockCardAuthoringService(
            availability: .unavailable(reason: .appleIntelligenceNotEnabled))
        await #expect(throws: AuthoringError.unavailable(reason: .appleIntelligenceNotEnabled)) {
            _ = try await svc.generateDrafts(from: "some text")
        }
    }

    @Test("availability: unavailable(modelNotReady) surfaces correctly")
    func availabilityModelNotReady() async throws {
        let svc = MockCardAuthoringService(
            availability: .unavailable(reason: .modelNotReady))
        await #expect(throws: AuthoringError.unavailable(reason: .modelNotReady)) {
            _ = try await svc.generateDrafts(from: "some text")
        }
    }

    @Test("emits configured drafts in order then finishes")
    func emitsDraftsInOrder() async throws {
        let expected = [
            CardDraft(question: "Q1", answer: "A1"),
            CardDraft(question: "Q2", answer: "A2")
        ]
        let svc = MockCardAuthoringService(drafts: expected)
        let stream = try await svc.generateDrafts(from: "passage")
        var collected: [CardDraft] = []
        for try await draft in stream { collected.append(draft) }
        #expect(collected == expected)
    }

    @Test("generationFailed wraps the underlying error")
    func generationFailedWraps() async throws {
        struct TestError: Error, Equatable {}
        let svc = MockCardAuthoringService(error: TestError())
        do {
            _ = try await svc.generateDrafts(from: "passage")
            Issue.record("Expected throw")
        } catch AuthoringError.generationFailed(let underlying) {
            #expect(underlying is TestError)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("cancellation terminates stream without error")
    func cancellationTerminates() async throws {
        let drafts = (1...10).map { CardDraft(question: "Q\($0)", answer: "A\($0)") }
        let svc = MockCardAuthoringService(drafts: drafts)
        let stream = try await svc.generateDrafts(from: "passage")
        var count = 0
        let task = Task {
            for try await _ in stream { count += 1; if count == 2 { break } }
        }
        await task.value
        #expect(count == 2)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd Packages/AnghkooeyIntelligence && swift test --filter MockCardAuthoringServiceTests 2>&1 | tail -5
```

Expected: compile error.

- [ ] **Step 3: Create CardAuthoringService.swift**

Create `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/CardAuthoringService.swift`:

```swift
/// Contract for on-device AI card authoring.
///
/// Both `LiveCardAuthoringService` (FoundationModels) and
/// `MockCardAuthoringService` (fixture-replay) conform to this protocol.
/// Callers depend only on this protocol — no FoundationModels types leak
/// through the boundary.
public protocol CardAuthoringService: Sendable {

    /// Runtime availability of the underlying model.
    ///
    /// Check this before presenting the AI capture path in the UI.
    /// When `.unavailable`, the reason drives the explanation shown to the user.
    var availability: AuthoringAvailability { get async }

    /// Begin streaming AI-authored `CardDraft` values for the given passage.
    ///
    /// - Throws: `AuthoringError.emptyInput` if `text` is blank.
    /// - Throws: `AuthoringError.unavailable(reason:)` if the model is not available.
    /// - Throws: `AuthoringError.generationFailed(underlying:)` on model errors.
    /// - Returns: An `AsyncThrowingStream` that yields one `CardDraft` per
    ///   completed Q&A pair as generation progresses.
    func generateDrafts(from text: String) async throws -> AsyncThrowingStream<CardDraft, Error>
}
```

- [ ] **Step 4: Create MockCardAuthoringService.swift**

Create `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/MockCardAuthoringService.swift`:

```swift
/// Deterministic fixture-replay implementation of `CardAuthoringService`.
///
/// Used by unit tests and the CI eval harness. Returns the configured
/// `drafts` one by one, or throws `generationFailed` when `error` is set.
public struct MockCardAuthoringService: CardAuthoringService {

    private let configuredAvailability: AuthoringAvailability
    private let drafts: [CardDraft]
    private let error: Error?

    public init(availability: AuthoringAvailability = .available,
                drafts: [CardDraft] = [],
                error: Error? = nil) {
        self.configuredAvailability = availability
        self.drafts = drafts
        self.error = error
    }

    public var availability: AuthoringAvailability {
        get async { configuredAvailability }
    }

    public func generateDrafts(from text: String) async throws -> AsyncThrowingStream<CardDraft, Error> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthoringError.emptyInput
        }
        if case .unavailable(let reason) = configuredAvailability {
            throw AuthoringError.unavailable(reason: reason)
        }
        if let error {
            throw AuthoringError.generationFailed(underlying: error)
        }
        let drafts = self.drafts
        return AsyncThrowingStream { continuation in
            let task = Task {
                for draft in drafts {
                    continuation.yield(draft)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 5: Run tests**

```bash
cd Packages/AnghkooeyIntelligence && swift test --filter MockCardAuthoringServiceTests 2>&1 | tail -5
```

Expected: `Test run with 7 tests passed.`

- [ ] **Step 6: Commit**

```bash
git add Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/ \
        Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Authoring/MockCardAuthoringServiceTests.swift
git commit -m "feat(m2): CardAuthoringService protocol + MockCardAuthoringService"
```

---

## Task 6: RubricScorer + EvalFixture

**Files:**
- Create: `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Eval/EvalFixture.swift`
- Create: `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Eval/RubricScorer.swift`
- Create: `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Eval/RubricScorerTests.swift`

- [ ] **Step 1: Write failing rubric tests**

Create `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Eval/RubricScorerTests.swift`:

```swift
import Testing
@testable import AnghkooeyIntelligence

@Suite("RubricScorer")
struct RubricScorerTests {

    let passage = "Mitosis is the process by which a cell divides into two identical daughter cells."

    @Test("atomic: compound question with 'and' fails")
    func atomicFailConjunction() {
        let draft = CardDraft(question: "What is mitosis and how many daughter cells does it produce?",
                              answer: "Cell division producing two identical daughters.")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(!result.atomic)
    }

    @Test("atomic: question >120 chars fails")
    func atomicFailLength() {
        let long = String(repeating: "word ", count: 25)  // >120 chars
        let draft = CardDraft(question: long, answer: "A")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(!result.atomic)
    }

    @Test("atomic: short single-fact question passes")
    func atomicPass() {
        let draft = CardDraft(question: "What process produces two identical daughter cells?",
                              answer: "Mitosis")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(result.atomic)
    }

    @Test("specific: answer shorter than 4 words fails")
    func specificFailShort() {
        let draft = CardDraft(question: "Q?", answer: "Yes")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(!result.specific)
    }

    @Test("specific: answer containing vague reference fails")
    func specificFailVague() {
        let draft = CardDraft(question: "Q?",
                              answer: "The process described above produces daughter cells.")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(!result.specific)
    }

    @Test("specific: concrete answer passes")
    func specificPass() {
        let draft = CardDraft(question: "Q?",
                              answer: "Mitosis produces two identical daughter cells.")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(result.specific)
    }

    @Test("groundedness: token not in passage fails")
    func groundednessFailHallucination() {
        let draft = CardDraft(question: "Q?",
                              answer: "Mitosis occurs during interphase of the cell cycle.")
        // "interphase" not in passage
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(!result.groundednessPass)
    }

    @Test("groundedness: all tokens in passage passes")
    func groundednessPass() {
        let draft = CardDraft(question: "Q?",
                              answer: "Mitosis divides a cell into two identical daughter cells.")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(result.groundednessPass)
    }

    @Test("qNotA: 4-gram from answer in question fails")
    func qNotAFail() {
        let draft = CardDraft(
            question: "What is the process that produces two identical daughter cells?",
            answer: "The process that produces two identical daughter cells is mitosis.")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(!result.qNotA)
    }

    @Test("qNotA: distinct question and answer passes")
    func qNotAPass() {
        let draft = CardDraft(question: "What process divides a cell in two?",
                              answer: "Mitosis produces two identical daughter cells.")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(result.qNotA)
    }

    @Test("cardPasses iff all four criteria pass")
    func cardPassesAllFour() {
        let draft = CardDraft(question: "What process produces two identical daughter cells?",
                              answer: "Mitosis divides a cell into two identical daughters.")
        let result = RubricScorer.score(draft: draft, passage: passage)
        #expect(result.cardPasses == (result.atomic && result.specific &&
                                      result.groundednessPass && result.qNotA))
    }
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd Packages/AnghkooeyIntelligence && swift test --filter RubricScorerTests 2>&1 | tail -5
```

Expected: compile error.

- [ ] **Step 3: Create EvalFixture.swift**

Create `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Eval/EvalFixture.swift`:

```swift
/// A single eval fixture: one input passage and its expected golden cards.
///
/// Loaded from `eval-fixtures.json` via `Bundle.module` in test targets,
/// and from a file path in `EvalRunner`.
public struct EvalFixture: Codable, Sendable {
    /// Unique identifier, e.g. `"biology-001"`.
    public var id: String
    /// The input passage fed to the authoring service.
    public var passage: String
    /// The prompt template version that produced `goldenDrafts`.
    /// Commit a new `make eval` run alongside any template change.
    public var templateVersion: String
    /// Expected card output from the live model. Used as the oracle for CI rubric scoring.
    public var goldenDrafts: [CardDraft]

    public init(id: String, passage: String,
                templateVersion: String, goldenDrafts: [CardDraft]) {
        self.id = id
        self.passage = passage
        self.templateVersion = templateVersion
        self.goldenDrafts = goldenDrafts
    }
}
```

- [ ] **Step 4: Create RubricScorer.swift**

Create `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Eval/RubricScorer.swift`:

```swift
import Foundation

/// Pure-string rubric scorer for `CardDraft` quality.
///
/// All four criteria must pass for a card to pass (binary, no averaging).
/// See strategic plan §4.2 for the locked scoring contract.
public enum RubricScorer {

    public struct CardResult: Sendable {
        public var atomic: Bool
        public var specific: Bool
        public var groundednessPass: Bool
        public var qNotA: Bool
        public var cardPasses: Bool { atomic && specific && groundednessPass && qNotA }
    }

    private static let stopwords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
        "in", "on", "at", "to", "for", "of", "and", "or", "but", "it", "its",
        "this", "that", "with", "by", "from", "as", "into", "through", "during",
        "not", "no", "nor", "so", "yet", "both", "either", "whether", "which",
        "who", "whom", "what", "how", "when", "where", "why", "each", "every",
        "do", "does", "did", "will", "would", "could", "should", "may", "might",
        "has", "have", "had", "can"
    ]

    private static let vagueRefs = ["above", "following", "described", "mentioned"]

    /// Score a single `CardDraft` against its source passage.
    public static func score(draft: CardDraft, passage: String) -> CardResult {
        CardResult(
            atomic: isAtomic(draft.question),
            specific: isSpecific(draft.answer),
            groundednessPass: isGrounded(answer: draft.answer, passage: passage),
            qNotA: questionDoesNotLeakAnswer(question: draft.question, answer: draft.answer)
        )
    }

    /// An input passes iff every card from that input passes.
    public static func inputPasses(drafts: [CardDraft], passage: String) -> Bool {
        drafts.allSatisfy { score(draft: $0, passage: passage).cardPasses }
    }

    // MARK: — Criteria

    private static func isAtomic(_ question: String) -> Bool {
        guard question.count <= 120 else { return false }
        let lower = question.lowercased()
        // Detect "X and Y" or "X or Y" where both sides look like independent clauses.
        // Heuristic: conjunction present and question is long enough to be compound.
        let conjunctions = [" and ", " or "]
        return !conjunctions.contains { lower.contains($0) && question.count > 60 }
    }

    private static func isSpecific(_ answer: String) -> Bool {
        let words = answer.split(separator: " ")
        guard words.count >= 4 else { return false }
        let lower = answer.lowercased()
        return !vagueRefs.contains { lower.contains($0) }
    }

    private static func isGrounded(answer: String, passage: String) -> Bool {
        let passageLower = passage.lowercased()
        let answerTokens = answer.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && !stopwords.contains($0) }
        return answerTokens.allSatisfy { passageLower.contains($0) }
    }

    private static func questionDoesNotLeakAnswer(question: String, answer: String) -> Bool {
        let qWords = question.lowercased().split(separator: " ").map(String.init)
        let aWords = answer.lowercased().split(separator: " ").map(String.init)
        guard aWords.count >= 4 else { return true }
        // Check if any contiguous 4-gram from the answer appears in the question.
        for i in 0...(aWords.count - 4) {
            let gram = aWords[i..<(i + 4)].joined(separator: " ")
            if qWords.joined(separator: " ").contains(gram) { return false }
        }
        return true
    }
}
```

- [ ] **Step 5: Run tests**

```bash
cd Packages/AnghkooeyIntelligence && swift test --filter RubricScorerTests 2>&1 | tail -5
```

Expected: `Test run with 10 tests passed.`

- [ ] **Step 6: Commit**

```bash
git add Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Eval/ \
        Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Eval/RubricScorerTests.swift
git commit -m "feat(m2): RubricScorer (4 binary criteria) + EvalFixture type"
```

---

## Task 7: Initial eval fixtures + CI rubric gate

**Files:**
- Create: `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Fixtures/eval-fixtures.json`
- Create: `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Eval/EvalFixtureGateTests.swift`

- [ ] **Step 1: Create initial fixtures file**

Create `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Fixtures/eval-fixtures.json`:

```json
[
  {
    "id": "biology-001",
    "passage": "Mitosis is the process by which a single cell divides into two genetically identical daughter cells. It consists of four phases: prophase, metaphase, anaphase, and telophase.",
    "templateVersion": "v1.0",
    "goldenDrafts": [
      {
        "question": "What process produces two genetically identical daughter cells?",
        "answer": "Mitosis divides a single cell into two genetically identical daughters.",
        "proposedTags": ["biology", "cell-division"],
        "sourceSpan": "Mitosis is the process by which a single cell divides into two genetically identical daughter cells."
      },
      {
        "question": "What are the four phases of mitosis in order?",
        "answer": "Mitosis consists of prophase, metaphase, anaphase, and telophase.",
        "proposedTags": ["biology", "mitosis", "cell-division"],
        "sourceSpan": "It consists of four phases: prophase, metaphase, anaphase, and telophase."
      }
    ]
  },
  {
    "id": "vocab-001",
    "passage": "Ephemeral means lasting for a very short time. The ephemeral nature of cherry blossoms makes them a symbol of impermanence in Japanese culture.",
    "templateVersion": "v1.0",
    "goldenDrafts": [
      {
        "question": "What does ephemeral mean?",
        "answer": "Ephemeral means lasting for a very short time.",
        "proposedTags": ["vocabulary", "english"],
        "sourceSpan": "Ephemeral means lasting for a very short time."
      },
      {
        "question": "What do cherry blossoms symbolize in Japanese culture?",
        "answer": "Cherry blossoms symbolize impermanence in Japanese culture.",
        "proposedTags": ["culture", "japan", "symbolism"],
        "sourceSpan": "The ephemeral nature of cherry blossoms makes them a symbol of impermanence in Japanese culture."
      }
    ]
  },
  {
    "id": "history-001",
    "passage": "The Treaty of Versailles was signed in 1919, officially ending World War I. It imposed heavy reparations on Germany and is widely considered a contributing factor to the rise of World War II.",
    "templateVersion": "v1.0",
    "goldenDrafts": [
      {
        "question": "In what year was the Treaty of Versailles signed?",
        "answer": "The Treaty of Versailles was signed in 1919.",
        "proposedTags": ["history", "world-war-1"],
        "sourceSpan": "The Treaty of Versailles was signed in 1919, officially ending World War I."
      },
      {
        "question": "What did the Treaty of Versailles impose on Germany?",
        "answer": "The Treaty of Versailles imposed heavy reparations on Germany.",
        "proposedTags": ["history", "germany", "versailles"],
        "sourceSpan": "It imposed heavy reparations on Germany."
      }
    ]
  }
]
```

- [ ] **Step 2: Write the CI gate test**

Create `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Eval/EvalFixtureGateTests.swift`:

```swift
import Testing
import Foundation
@testable import AnghkooeyIntelligence

@Suite("EvalFixtureGate — CI rubric gate (no model calls)")
struct EvalFixtureGateTests {

    static var fixtures: [EvalFixture] = {
        guard let url = Bundle.module.url(forResource: "eval-fixtures", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([EvalFixture].self, from: data)
        else { return [] }
        return loaded
    }()

    @Test("fixtures file loads and is non-empty")
    func fixturesLoad() {
        #expect(!EvalFixtureGateTests.fixtures.isEmpty)
    }

    @Test("every golden card in every fixture passes all four rubric criteria",
          arguments: EvalFixtureGateTests.fixtures)
    func goldenPassesRubric(fixture: EvalFixture) {
        for draft in fixture.goldenDrafts {
            let result = RubricScorer.score(draft: draft, passage: fixture.passage)
            #expect(result.atomic,
                    "[\(fixture.id)] atomicity failed for: \(draft.question)")
            #expect(result.specific,
                    "[\(fixture.id)] specificity failed for answer: \(draft.answer)")
            #expect(result.groundednessPass,
                    "[\(fixture.id)] groundedness failed for answer: \(draft.answer)")
            #expect(result.qNotA,
                    "[\(fixture.id)] Q≠A failed for: \(draft.question)")
        }
    }
}
```

- [ ] **Step 3: Run tests**

```bash
cd Packages/AnghkooeyIntelligence && swift test --filter EvalFixtureGateTests 2>&1 | tail -10
```

Expected: All fixtures pass. If a golden draft fails a rubric check, the fixture or rubric needs adjustment — fix whichever is wrong before continuing.

- [ ] **Step 4: Commit**

```bash
git add Packages/AnghkooeyIntelligence/Tests/
git commit -m "feat(m2): initial eval fixtures + CI rubric gate (@Test(arguments:) over fixtures)"
```

---

## Task 8: LiveCardAuthoringService

**Files:**
- Create: `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/LiveCardAuthoringService.swift`

Note: This task requires a real `LanguageModelSession` on-device. Compilation is verified via `swift build`; smoke-testing requires an iOS 26 Simulator with the Apple Intelligence model downloaded.

- [ ] **Step 1: Create LiveCardAuthoringService.swift**

Create `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/LiveCardAuthoringService.swift`:

```swift
import FoundationModels
import OSLog

/// Production card authoring service backed by `LanguageModelSession`.
///
/// Uses `streamResponse(to:generating:)` and pipes snapshots through
/// `SnapshotAccumulator` so callers receive completed `CardDraft` values
/// progressively rather than waiting for the full response.
public struct LiveCardAuthoringService: CardAuthoringService {

    private static let instructions = """
        You are a spaced-repetition card author. Given a passage of text, generate \
        atomic question-and-answer flashcard pairs that test recall of specific facts \
        in the passage. Rules:
        - Each card tests exactly one fact.
        - Do not invent or infer facts not present in the passage.
        - Questions must be specific enough that only someone who read the passage \
          can answer them.
        - Answers must be concise (1–2 sentences maximum).
        - The question must not contain or restate the answer.
        - Propose 1–3 relevant topic tags per card (lowercase, no spaces).
        Return only cards derivable from the passage. If the passage contains no \
        memorable facts, return an empty list.
        """

    private let log = IntelligenceLog.authoring

    public init() {}

    public var availability: AuthoringAvailability {
        get async {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable(reason: .deviceNotEligible)
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable(reason: .appleIntelligenceNotEnabled)
            case .unavailable(.modelNotReady):
                return .unavailable(reason: .modelNotReady)
            @unknown default:
                return .unavailable(reason: .modelNotReady)
            }
        }
    }

    public func generateDrafts(from text: String) async throws -> AsyncThrowingStream<CardDraft, Error> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthoringError.emptyInput
        }
        let avail = await availability
        if case .unavailable(let reason) = avail {
            throw AuthoringError.unavailable(reason: reason)
        }
        log.debug("Starting generation for passage of \(text.count) chars")

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: Self.instructions)
                    let stream = session.streamResponse(to: text, generating: AuthorResponse.self)
                    var accumulator = SnapshotAccumulator()
                    for try await snapshot in stream {
                        let partials = snapshot.content.drafts.map {
                            SnapshotAccumulator.PartialDraft(
                                question: $0.question,
                                answer: $0.answer,
                                proposedTags: $0.proposedTags,
                                sourceSpan: $0.sourceSpan
                            )
                        }
                        for draft in accumulator.update(partials) {
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
    }
}
```

- [ ] **Step 2: Add `authoring` logger to IntelligenceLog**

Edit `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Logging/IntelligenceLog.swift` to add:

```swift
/// Logger for the FoundationModels card authoring subsystem.
public static var authoring: Logger { Logger(subsystem: subsystem, category: "Authoring") }
```

(Follow the existing pattern in the file — check its current content first.)

- [ ] **Step 3: Build to confirm compilation**

```bash
cd Packages/AnghkooeyIntelligence && swift build 2>&1 | tail -5
```

Expected: `Build complete!`

If `snapshot.content.drafts` field name or `PartiallyGenerated` field access fails to compile, inspect the SDK interface:
```bash
xcrun --sdk iphonesimulator swift -print-target-info 2>/dev/null
find /Applications/Xcode.app -name "FoundationModels.swiftinterface" 2>/dev/null | head -3
```
Then read the interface to confirm the correct field names and adjust accordingly.

- [ ] **Step 4: Smoke test on iOS 26 Simulator** (requires model downloaded)

Boot the simulator and run a manual smoke test via the app target in M3. For now, confirm the type compiles cleanly. Document any API corrections needed as a comment in `LiveCardAuthoringService.swift` for the M3 wiring task.

- [ ] **Step 5: Commit**

```bash
git add Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/LiveCardAuthoringService.swift \
        Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Logging/IntelligenceLog.swift
git commit -m "feat(m2): LiveCardAuthoringService — FoundationModels streaming via SnapshotAccumulator"
```

---

## Task 9: EvalRunner executable

**Files:**
- Create: `Packages/AnghkooeyIntelligence/Sources/EvalRunner/main.swift`
- Create: `Packages/AnghkooeyIntelligence/Makefile`

- [ ] **Step 1: Create main.swift**

Create `Packages/AnghkooeyIntelligence/Sources/EvalRunner/main.swift`:

```swift
import ArgumentParser
import AnghkooeyIntelligence
import Foundation

@main
struct EvalRunner: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "EvalRunner",
        abstract: "Run the AnghkooeyIntelligence eval harness against live model output."
    )

    @Flag(name: .long, help: "Overwrite eval-fixtures.json with new golden output.")
    var updateGoldens = false

    @Option(name: .long, help: "Path to eval-fixtures.json. Defaults to repo-relative path.")
    var fixtures: String = "Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Fixtures/eval-fixtures.json"

    mutating func run() async throws {
        let fixturesURL = URL(fileURLWithPath: fixtures,
                              relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let data = try Data(contentsOf: fixturesURL)
        var evalFixtures = try JSONDecoder().decode([EvalFixture].self, from: data)

        let service = LiveCardAuthoringService()
        let avail = await service.availability
        guard case .available = avail else {
            print("❌ Model unavailable: \(avail). Run on macOS 26 with Apple Intelligence enabled.")
            throw ExitCode.failure
        }

        var passCount = 0
        var updatedFixtures: [EvalFixture] = []

        for fixture in evalFixtures {
            print("\n[\(fixture.id)] passage: \(fixture.passage.prefix(60))…")
            var collectedDrafts: [CardDraft] = []
            let stream = try await service.generateDrafts(from: fixture.passage)
            for try await draft in stream { collectedDrafts.append(draft) }

            let passes = RubricScorer.inputPasses(drafts: collectedDrafts, passage: fixture.passage)
            print("  Generated \(collectedDrafts.count) card(s). Input pass: \(passes ? "✓" : "✗")")

            for (i, draft) in collectedDrafts.enumerated() {
                let r = RubricScorer.score(draft: draft, passage: fixture.passage)
                let mark = r.cardPasses ? "✓" : "✗"
                print("  [\(i+1)] \(mark) atomic:\(r.atomic) specific:\(r.specific) grounded:\(r.groundednessPass) Q≠A:\(r.qNotA)")
                print("       Q: \(draft.question)")
            }

            if passes { passCount += 1 }
            var updated = fixture
            updated.goldenDrafts = collectedDrafts
            updatedFixtures.append(updated)
        }

        let total = evalFixtures.count
        let rate = Double(passCount) / Double(total) * 100
        print("\n=== Eval complete: \(passCount)/\(total) inputs passed (\(String(format: "%.1f", rate))%) ===")

        if updateGoldens {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let newData = try encoder.encode(updatedFixtures)
            try newData.write(to: fixturesURL)
            print("✓ Updated \(fixturesURL.path)")
        }

        if rate < 80.0 {
            print("❌ Pass rate \(String(format: "%.1f", rate))% is below 80% threshold.")
            throw ExitCode.failure
        }
    }
}
```

- [ ] **Step 2: Create Makefile**

Create `Packages/AnghkooeyIntelligence/Makefile`:

```makefile
.PHONY: eval eval-update

# Run live eval against current model. Must be run from repo root.
# Requires macOS 26 with Apple Intelligence enabled.
eval:
	swift run --package-path Packages/AnghkooeyIntelligence EvalRunner

# Re-run live eval and overwrite golden fixtures with new model output.
# Commit the updated fixtures alongside any prompt template change.
eval-update:
	swift run --package-path Packages/AnghkooeyIntelligence EvalRunner --update-goldens
```

- [ ] **Step 3: Build EvalRunner**

```bash
cd Packages/AnghkooeyIntelligence && swift build --product EvalRunner 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/AnghkooeyIntelligence/Sources/EvalRunner/ \
        Packages/AnghkooeyIntelligence/Makefile
git commit -m "feat(m2): EvalRunner CLI — live eval + golden-fixture update"
```

---

## Task 10: OCRService (Vision, CGImage)

OCR takes `CGImage` (not `UIImage`) to keep UIKit out of Intelligence sources.
The UI layer calls `image.cgImage` before handing off.

**Files:**
- Create: `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/OCR/OCRService.swift`
- Create: `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/OCR/LiveOCRService.swift`
- Create: `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/OCR/MockOCRService.swift`
- Create: `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/OCR/MockOCRServiceTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/OCR/MockOCRServiceTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import AnghkooeyIntelligence

@Suite("MockOCRService")
struct MockOCRServiceTests {

    private func blankImage() -> CGImage {
        let ctx = CGContext(data: nil, width: 1, height: 1,
                            bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    @Test("returns configured text")
    func returnsText() async throws {
        let svc = MockOCRService(result: .success("Hello world"))
        let text = try await svc.recognizeText(in: blankImage())
        #expect(text == "Hello world")
    }

    @Test("throws configured error")
    func throwsError() async {
        struct OCRFail: Error {}
        let svc = MockOCRService(result: .failure(OCRFail()))
        await #expect(throws: OCRFail.self) {
            _ = try await svc.recognizeText(in: blankImage())
        }
    }

    @Test("cleans up hyphens at line breaks")
    func hyphenCleanup() async throws {
        let svc = MockOCRService(result: .success("hyphen-\nated word"))
        let text = try await svc.recognizeText(in: blankImage())
        #expect(text == "hyphenated word")
    }
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd Packages/AnghkooeyIntelligence && swift test --filter MockOCRServiceTests 2>&1 | tail -5
```

Expected: compile error.

- [ ] **Step 3: Create OCRService.swift**

Create `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/OCR/OCRService.swift`:

```swift
import CoreGraphics

/// Contract for on-device optical character recognition.
///
/// Takes `CGImage` (not `UIImage`) to avoid importing UIKit.
/// The UI layer extracts `uiImage.cgImage` before calling.
public protocol OCRService: Sendable {
    /// Recognise text in `image` and return cleaned-up plain text.
    ///
    /// - Throws: `OCRError` on recognition failure.
    func recognizeText(in image: CGImage) async throws -> String
}

/// Errors thrown by `OCRService.recognizeText(in:)`.
public enum OCRError: Error, Sendable {
    case recognitionFailed(underlying: Error)
    case noTextFound
}
```

- [ ] **Step 4: Create MockOCRService.swift**

Create `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/OCR/MockOCRService.swift`:

```swift
import CoreGraphics

/// Deterministic test double for `OCRService`.
public struct MockOCRService: OCRService {
    private let result: Result<String, Error>

    public init(result: Result<String, Error>) {
        self.result = result
    }

    public func recognizeText(in image: CGImage) async throws -> String {
        let raw = try result.get()
        return Self.cleanup(raw)
    }

    /// Remove soft hyphens at line breaks (e.g. "hyphen-\nated" → "hyphenated").
    static func cleanup(_ text: String) -> String {
        text.replacingOccurrences(of: "-\n", with: "")
            .replacingOccurrences(of: "-\r\n", with: "")
    }
}
```

- [ ] **Step 5: Create LiveOCRService.swift**

Create `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/OCR/LiveOCRService.swift`:

```swift
import CoreGraphics
import Vision

/// Production OCR service backed by `VNRecognizeTextRequest`.
public struct LiveOCRService: OCRService {

    public init() {}

    public func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(underlying: error))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let raw = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                guard !raw.isEmpty else {
                    continuation.resume(throwing: OCRError.noTextFound)
                    return
                }
                continuation.resume(returning: MockOCRService.cleanup(raw))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(underlying: error))
            }
        }
    }
}
```

- [ ] **Step 6: Run tests**

```bash
cd Packages/AnghkooeyIntelligence && swift test --filter MockOCRServiceTests 2>&1 | tail -5
```

Expected: `Test run with 3 tests passed.`

- [ ] **Step 7: Confirm forbidden-pattern check still passes**

```bash
bash scripts/m1-forbidden-patterns.sh
```

Expected: `M1 forbidden-pattern check: OK`

- [ ] **Step 8: Commit**

```bash
git add Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/OCR/ \
        Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/OCR/
git commit -m "feat(m2): OCRService protocol + LiveOCRService (Vision) + MockOCRService"
```

---

## Task 11: CoreLog carry-over — configure(subsystem:)

**Files:**
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Logging/CoreLog.swift`

- [ ] **Step 1: Replace the subsystem static var with a configure method**

In `CoreLog.swift`, replace:

```swift
public nonisolated(unsafe) static var subsystem: String = "com.unknown.anghkooey"
```

With:

```swift
private nonisolated(unsafe) static var _subsystem: String = "com.unknown.anghkooey"

/// Inject the host app's bundle identifier before any log call fires.
///
/// Call once from the app's `@main` entry point:
/// ```swift
/// CoreLog.configure(subsystem: Bundle.main.bundleIdentifier ?? "com.unknown.anghkooey")
/// ```
/// Subsequent calls are ignored; subsystem is write-once.
public static func configure(subsystem: String) {
    guard _subsystem == "com.unknown.anghkooey" else { return }
    _subsystem = subsystem
}

internal static var subsystem: String { _subsystem }
```

- [ ] **Step 2: Run AnghkooeyCore tests to confirm nothing broke**

```bash
cd Packages/AnghkooeyCore && swift test 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 3: Wire configure in app entry point**

In `App/Anghkooey/AnghkooeyApp.swift` (the `@main` struct), add to `init()` or `body`:

```swift
CoreLog.configure(subsystem: Bundle.main.bundleIdentifier ?? "com.unknown.anghkooey")
```

(Adapt to whatever entry-point pattern M0 established.)

- [ ] **Step 4: Commit**

```bash
git add Packages/AnghkooeyCore/Sources/AnghkooeyCore/Logging/CoreLog.swift
git commit -m "refactor(core): CoreLog.configure(subsystem:) — replace nonisolated(unsafe) static var (M1 carry-over)"
```

---

## Task 12: CI script update + DocC + ARCHITECTURE.md

**Files:**
- Modify: `scripts/ci.sh`
- Modify: `ARCHITECTURE.md`
- Modify all public `.swift` files in `Sources/AnghkooeyIntelligence/` that lack `///` doc comments

- [ ] **Step 1: Update ci.sh Intelligence test step**

In `scripts/ci.sh`, replace:

```bash
echo "=== AnghkooeyIntelligence tests ==="
(cd "$WORKSPACE_ROOT/Packages/AnghkooeyIntelligence" && swift test)
```

With:

```bash
echo "=== AnghkooeyIntelligence tests ==="
xcodebuild test \
  -scheme AnghkooeyIntelligence \
  -destination "$SIMULATOR" \
  -resultBundlePath /tmp/anghkooey-m2.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath "$DERIVED"
```

Note: An `AnghkooeyIntelligence` scheme must exist in the Xcode project. If it does not, create it in Xcode: Product → Scheme → New Scheme → target `AnghkooeyIntelligence`.

- [ ] **Step 2: Run full CI locally to confirm green**

```bash
bash scripts/ci.sh 2>&1 | tail -20
```

Expected: `✓ All checks passed`

- [ ] **Step 3: Add DocC comments to any public API missing them**

Every `public` type, property, and method in `Sources/AnghkooeyIntelligence/` needs a `///` summary. Check with:

```bash
grep -rn "public " Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/ \
  | grep -v "///" | grep -v ".swiftinterface"
```

Add single-line `///` summaries above any hit. (The types created in Tasks 2–10 already have doc comments; this step catches any gaps.)

- [ ] **Step 4: Append M2 section to ARCHITECTURE.md**

Append the following to `ARCHITECTURE.md` (after the M1 section):

```markdown
---

## M2 — AnghkooeyIntelligence: Card Authoring + OCR

**Branch:** `m2/foundation-models`
**Status:** in progress
**Spec:** `docs/superpowers/specs/2026-05-21-m2-intelligence-design.md`

### Package topology addition

```
Anghkooey (app target)
├── AnghkooeyCore      (M1 — schema + FSRS-6)
└── AnghkooeyIntelligence  (this milestone)
    ├── Authoring/     — CardDraft, AuthorResponse, CardAuthoringService, Live + Mock, SnapshotAccumulator
    ├── OCR/           — OCRService, LiveOCRService (Vision), MockOCRService
    ├── Eval/          — EvalFixture, RubricScorer
    └── Logging/       — IntelligenceLog
```

`AnghkooeyIntelligence` imports `AnghkooeyCore` for `AnghkooeyCore` logging
patterns only. It imports no SwiftData, SwiftUI, or UIKit types. Enforced
by `scripts/m1-forbidden-patterns.sh`.

### Card authoring data flow

Text passage → `CardAuthoringService.generateDrafts(from:)` →
`AsyncThrowingStream<CardDraft, Error>`. The live implementation calls
`LanguageModelSession.streamResponse(to:generating:)` and routes each
`ResponseStream<AuthorResponse>.Snapshot` through `SnapshotAccumulator`,
which emits `CardDraft` values as each array slot reaches both `question`
and `answer` non-empty. One emission per array index; later refinements
discarded.

### Eval harness

Two modes:
- **CI mode** — `swift test` / xcodebuild runs `EvalFixtureGateTests`:
  `@Test(arguments:)` over `eval-fixtures.json` golden drafts; scores each
  card against 4 binary rubric criteria; fails build if any card fails.
  Zero model calls.
- **Live mode** — `make eval` (from repo root) runs the `EvalRunner`
  executable on macOS 26 with the real model; prints per-input verdicts;
  `make eval-update` overwrites golden fixtures.

### Module seam

`CardDraft` is the output type of `AnghkooeyIntelligence`. `Card(from:
CardDraft)` conversion is an `AnghkooeyUI` responsibility (M3), co-located
with the user-confirmation ViewModel.
```

- [ ] **Step 5: Commit**

```bash
git add scripts/ci.sh ARCHITECTURE.md \
        Packages/AnghkooeyIntelligence/Sources/
git commit -m "docs(m2): ARCHITECTURE.md M2 section + CI xcodebuild gate for Intelligence tests"
```

---

## Exit Gate Checklist

Before opening the M2 PR, confirm all items:

- [ ] `swift build` in `Packages/AnghkooeyIntelligence` exits 0
- [ ] `swift test` in `Packages/AnghkooeyIntelligence` — all tests pass (accumulator, mock, rubric, fixture gate)
- [ ] `bash scripts/m1-forbidden-patterns.sh` → `M1 forbidden-pattern check: OK`
- [ ] `bash scripts/ci.sh` → `✓ All checks passed`
- [ ] `LiveCardAuthoringService` compiles without error
- [ ] `make eval` runs end-to-end on macOS 26 with Apple Intelligence enabled; ≥ 80% input pass-rate on the golden fixture set
- [ ] `ARCHITECTURE.md` M2 section committed
- [ ] All public APIs have `///` doc comments
- [ ] UNVERIFIED items in spec §5 resolved (snapshot field names confirmed against real simulator build; any corrections documented in `LiveCardAuthoringService.swift`)
