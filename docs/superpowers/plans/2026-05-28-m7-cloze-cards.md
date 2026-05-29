# M7 — Cloze Deletion Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Anki-style cloze deletion cards — AI-authored from a passage, edited by the user, fanned into independently-scheduled sibling cards with persistent answer-leak burying.

**Architecture:** A pure `ClozeMarkupParser` in `AnghkooeyCore` is the single authority for the `{{cN::answer::hint}}` grammar (serves AI output, the manual editor, and future Anki cloze import). Schema V5 adds cloze metadata to `Card` while keeping `question`/`answer` as baked rendered strings, so the review UI and FSRS scheduler are unchanged. A new `@Generable` path in `AnghkooeyIntelligence` proposes markup; `CardStore.createClozeCards` fans an accepted template into N siblings sharing a `clozeGroupID`; persistent `clozeBuriedUntil` prevents cross-session leak.

**Tech Stack:** Swift 6, SwiftData (versioned schema + lightweight migration), FoundationModels (`@Generable`, `LanguageModelSession`), Swift Testing (parameterized), SwiftUI.

**Source spec:** `docs/superpowers/specs/2026-05-28-v2-cloze-fsrs-design.md` (§M7).

**Model routing (per `feedback_codex_concrete_roles_in_plans`):**

| Task | Model | Codex role |
|---|---|---|
| ADR-0003 | Opus | reviewer |
| T1 CardType + V5 schema + migration | Sonnet | none |
| T2 CloudKit V5 schema test | Sonnet | none |
| T3 ClozeMarkupParser | Sonnet writes failing tests + skeleton | **Codex primary impl** |
| T4 CardStore fan-out + burying | Sonnet | reviewer |
| T5 AnkiNoteMapper ordinal fix | Sonnet | none |
| T6 Cloze authoring service (@Generable) | Sonnet | reviewer |
| T7 Cloze UI (editor + toggle) | Sonnet | none |
| M7 exit review | Opus | reviewer |

**Build/verify commands** (per memory — Codex sandbox can't build; Claude verifies locally):
```
xcodebuild test -project App/Anghkooey.xcodeproj -scheme Anghkooey \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/anghkooey-derived-data \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_STYLE=Manual
```
After any `project.yml` change: `cd App && xcodegen generate` then `python3 scripts/patch_privacy_info.py`.

---

## File Structure

**Create:**
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardType.swift` — `Int`-raw enum.
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeySchemaV5.swift` — `Card` + 5 new fields; final schema (owns `ReviewLog`/`Tag`).
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Cloze/ClozeTemplate.swift` — `ClozeTemplate`, `ClozeDeletion`, `ClozeParseError`.
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Cloze/ClozeMarkupParser.swift` — parse / validate / render.
- `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Cloze/ClozeDraft.swift` — `@Generable`.
- `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Cloze/ClozeResponse.swift` — `@Generable`.
- `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Cloze/ClozeAuthoringService.swift` — protocol.
- `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Cloze/LiveClozeAuthoringService.swift`
- `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Cloze/MockClozeAuthoringService.swift`
- `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Cloze/ClozeAuthoringView.swift`
- Tests under `App/AnghkooeyTests/`: `ClozeMarkupParserTests.swift`, `CloudKitV5SchemaTests.swift`, `SchemaMigrationV5Tests.swift`, `CardStoreClozeTests.swift`, `ClozeAuthoringServiceTests.swift`; modify `AnkiNoteMapperTests.swift`.

**Modify:**
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeySchemaV1.swift` — add V5 to migration plan; move `ReviewLog`/`Tag` ownership to V5.
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeySchemaV4.swift` — drop `ReviewLog`/`Tag` from `models` (duplicate-checksum rule, `feedback_swiftdata_duplicate_checksum`).
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeyModelContainer.swift` — point schema at `AnghkooeySchemaV5`.
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardStore.swift` — `typealias Card = …V5.Card`; Snapshot cloze fields; `createClozeCards`; bury filter in `dueCards`; bury write in `apply`.
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Import/AnkiNoteMapper.swift` — ordinal-aware identity + cloze skip.
- `Packages/AnghkooeyUI/.../Capture` entry point — Q&A / Cloze mode toggle (bind to real file during T7).

---

## Task 1: CardType enum, Schema V5, lightweight migration

**Files:**
- Create: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardType.swift`
- Create: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeySchemaV5.swift`
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeySchemaV4.swift`
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeySchemaV1.swift`
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeyModelContainer.swift`
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardStore.swift`
- Test: `App/AnghkooeyTests/SchemaMigrationV5Tests.swift`

- [ ] **Step 1: Write the failing migration test**

Model it on the existing `SchemaMigrationV4Tests.swift` (same in-process-store technique; per `feedback_swiftdata_versioned_namespacing`, assert on V5 reads, not cross-version identifier equality).

```swift
import Testing
import SwiftData
import Foundation
@testable import AnghkooeyCore

@Suite struct SchemaMigrationV5Tests {
    @Test func v4RowsGainNilClozeFieldsUnderV5() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mig-v5-\(UUID()).store")
        defer { try? FileManager.default.removeItem(at: url) }

        // Seed a V4 store with one Q&A card.
        do {
            let v4Schema = Schema(versionedSchema: AnghkooeySchemaV4.self)
            let cfg = ModelConfiguration(schema: v4Schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: v4Schema,
                migrationPlan: AnghkooeyMigrationPlan.self, configurations: [cfg])
            let ctx = ModelContext(container)
            ctx.insert(AnghkooeySchemaV4.Card(question: "Q", answer: "A"))
            try ctx.save()
        }

        // Reopen under V5 — lightweight migration runs.
        let v5Schema = Schema(versionedSchema: AnghkooeySchemaV5.self)
        let cfg = ModelConfiguration(schema: v5Schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: v5Schema,
            migrationPlan: AnghkooeyMigrationPlan.self, configurations: [cfg])
        let ctx = ModelContext(container)
        let cards = try ctx.fetch(FetchDescriptor<AnghkooeySchemaV5.Card>())
        #expect(cards.count == 1)
        #expect(cards.first?.cardType == nil)          // migrated rows default to nil → .qa on read
        #expect(cards.first?.clozeGroupID == nil)
        #expect(cards.first?.clozeBuriedUntil == nil)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run the build/verify command filtered to `SchemaMigrationV5Tests`. Expected: FAIL — `AnghkooeySchemaV5` undefined.

- [ ] **Step 3: Create `CardType.swift`**

```swift
import Foundation

/// Whether a card is a plain Q&A card or one deletion of a cloze group.
///
/// Raw values are pinned (`Int`) like `CardState` so SwiftData storage is
/// stable and CloudKit-safe. Migrated (pre-V5) rows have `cardType == nil`;
/// callers nil-coalesce to `.qa`.
public enum CardType: Int, Codable, Sendable, CaseIterable {
    case qa = 0
    case cloze = 1
}
```

- [ ] **Step 4: Create `AnghkooeySchemaV5.swift`**

V5 is the final schema, so it — not V4 — owns the unversioned `ReviewLog`/`Tag` (`feedback_swiftdata_duplicate_checksum`). New fields are Optional (`feedback_swiftdata_versioned_namespacing`). Write `public final class` inside `public extension` (`feedback_swiftdata_model_public_class`).

```swift
import Foundation
import SwiftData

public enum AnghkooeySchemaV5: VersionedSchema {
    public static let versionIdentifier = Schema.Version(5, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [AnghkooeySchemaV5.Card.self, ReviewLog.self, Tag.self]
    }
}

public extension AnghkooeySchemaV5 {
    @Model
    public final class Card {
        @Attribute(.unique) public var id: UUID
        public var question: String
        public var answer: String
        public var createdAt: Date
        public var updatedAt: Date
        public var tags: [Tag]
        public var state: CardState
        public var stability: Double
        public var difficulty: Double
        public var dueAt: Date
        public var lastReviewedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \ReviewLog.card)
        public var reviewLogs: [ReviewLog]

        public var sourceSpan: String?
        public var reps: Int?
        public var lapses: Int?
        public var learningSteps: Int?
        public var scheduledDays: Double?
        public var elapsedDays: Double?
        public var mnemonic: String?

        // V5: cloze metadata. All Optional for lightweight migration.
        public var cardType: CardType?
        public var clozeGroupID: UUID?
        public var clozeIndex: Int?
        public var clozeSourceText: String?
        public var clozeBuriedUntil: Date?

        public init(
            id: UUID = UUID(), question: String, answer: String,
            createdAt: Date = .now, updatedAt: Date = .now, tags: [Tag] = [],
            state: CardState = .new, stability: Double = 0, difficulty: Double = 0,
            dueAt: Date = .now, lastReviewedAt: Date? = nil, reviewLogs: [ReviewLog] = [],
            sourceSpan: String? = nil, reps: Int = 0, lapses: Int = 0,
            learningSteps: Int = 0, scheduledDays: Double = 0, elapsedDays: Double = 0,
            mnemonic: String? = nil,
            cardType: CardType? = nil, clozeGroupID: UUID? = nil, clozeIndex: Int? = nil,
            clozeSourceText: String? = nil, clozeBuriedUntil: Date? = nil
        ) {
            self.id = id; self.question = question; self.answer = answer
            self.createdAt = createdAt; self.updatedAt = updatedAt; self.tags = tags
            self.state = state; self.stability = stability; self.difficulty = difficulty
            self.dueAt = dueAt; self.lastReviewedAt = lastReviewedAt; self.reviewLogs = reviewLogs
            self.sourceSpan = sourceSpan; self.reps = reps; self.lapses = lapses
            self.learningSteps = learningSteps; self.scheduledDays = scheduledDays
            self.elapsedDays = elapsedDays; self.mnemonic = mnemonic
            self.cardType = cardType; self.clozeGroupID = clozeGroupID
            self.clozeIndex = clozeIndex; self.clozeSourceText = clozeSourceText
            self.clozeBuriedUntil = clozeBuriedUntil
        }
    }
}
```

- [ ] **Step 5: Drop `ReviewLog`/`Tag` from V4's `models`**

In `AnghkooeySchemaV4.swift`, change `models` to `[AnghkooeySchemaV4.Card.self]` only. (They now live in V5 — final-version-only ownership avoids the duplicate-checksum crash.)

- [ ] **Step 6: Wire V5 into the migration plan**

In `AnghkooeySchemaV1.swift`, add `AnghkooeySchemaV5.self` to `schemas`, and append to `stages`:
```swift
// V5 adds cloze metadata fields, all Optional → V4 rows get NULL. No data movement.
.lightweight(fromVersion: AnghkooeySchemaV4.self, toVersion: AnghkooeySchemaV5.self)
```

- [ ] **Step 7: Point the container + typealias at V5**

In `AnghkooeyModelContainer.swift`, replace both `Schema(versionedSchema: AnghkooeySchemaV4.self)` with `AnghkooeySchemaV5.self` and update the log strings to "v5 schema".
In `CardStore.swift`, change `public typealias Card = AnghkooeySchemaV4.Card` → `AnghkooeySchemaV5.Card`.

- [ ] **Step 8: Run the migration test**

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence App/AnghkooeyTests/SchemaMigrationV5Tests.swift
git commit -m "feat(core): schema V5 — CardType + cloze metadata fields, V4→V5 lightweight migration"
```

---

## Task 2: CloudKit V5 schema validation (gate — do before any UI)

**Files:**
- Test: `App/AnghkooeyTests/CloudKitV5SchemaTests.swift`

Rationale: per spec §M7.2 and `feedback_ios26_cloudkit_auto_enable`, every attribute must be Optional for CloudKit mirroring. This proves V5 still builds a container under the CloudKit-shaped config before we build features on it.

- [ ] **Step 1: Write the test**

```swift
import Testing
import SwiftData
@testable import AnghkooeyCore

@Suite struct CloudKitV5SchemaTests {
    // CloudKit requires all attributes optional & no .unique except the CK system id.
    // We can't hit real CloudKit in CI, but we CAN assert the V5 schema builds a
    // container under an in-memory config that mirrors the production wiring.
    @Test func v5SchemaBuildsContainer() throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        #expect(container.schema.entities.contains { $0.name == "Card" })
    }
}
```

- [ ] **Step 2: Run — expected PASS** (this is a regression guard; if it fails, the V5 `@Attribute(.unique)` or a non-optional new field is the cause — investigate before proceeding).

- [ ] **Step 3: Commit**
```bash
git add App/AnghkooeyTests/CloudKitV5SchemaTests.swift
git commit -m "test(core): V5 schema builds container (CloudKit-shape gate)"
```

---

## Task 3: ClozeMarkupParser (contract-first → Codex primary impl)

**Files:**
- Create: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Cloze/ClozeTemplate.swift`
- Create: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Cloze/ClozeMarkupParser.swift`
- Test: `App/AnghkooeyTests/ClozeMarkupParserTests.swift`

> **Codex handoff:** Sonnet writes the value types, the empty parser API, and the full failing parameterized test suite below. Codex (gpt-5.5-xhigh) implements `parse`/`render` to make them pass. Claude verifies locally (Codex sandbox can't build). Test-case structs must be non-`private` and at least as visible as the test (`feedback_swift_testing_arguments_visibility`).

- [ ] **Step 1: Create the value types + parser skeleton**

```swift
// ClozeTemplate.swift
import Foundation

public struct ClozeDeletion: Equatable, Sendable {
    public let index: Int        // 1-based, like Anki c1/c2
    public let answer: String
    public let hint: String?
    public init(index: Int, answer: String, hint: String? = nil) {
        self.index = index; self.answer = answer; self.hint = hint
    }
}

public struct ClozeTemplate: Equatable, Sendable {
    /// Original markup text, e.g. "The {{c1::mitochondria}} is the {{c2::powerhouse}}".
    public let markup: String
    /// Deletions sorted ascending by index, deduplicated by index.
    public let deletions: [ClozeDeletion]
    public init(markup: String, deletions: [ClozeDeletion]) {
        self.markup = markup; self.deletions = deletions
    }
    /// Distinct cloze indices present, ascending.
    public var indices: [Int] { deletions.map(\.index).sorted() }
}

public enum ClozeParseError: Error, Equatable, Sendable {
    case noDeletions
    case unclosedMarker
    case nestedMarker
    case duplicateIndex(Int)
    case nonPositiveIndex(Int)
    case tooManyDeletions(count: Int, max: Int)
    case emptyAnswer(index: Int)
}
```

```swift
// ClozeMarkupParser.swift
import Foundation

/// The single authority for the cloze `{{cN::answer::hint}}` grammar.
/// Pure value logic — used by AI output, the manual editor, and future Anki import.
public enum ClozeMarkupParser {
    public static let maxDeletions = 20

    /// Parses and validates cloze markup into a template.
    public static func parse(_ markup: String) throws -> ClozeTemplate {
        fatalError("Codex: implement")
    }

    /// Renders the visible prompt for one deletion: the target deletion shown as
    /// "[…]", all OTHER deletions shown with their answers revealed.
    public static func renderQuestion(_ template: ClozeTemplate, index: Int) -> String {
        fatalError("Codex: implement")
    }

    /// The answer string for one deletion (its `answer`).
    public static func renderAnswer(_ template: ClozeTemplate, index: Int) -> String {
        fatalError("Codex: implement")
    }
}
```

- [ ] **Step 2: Write the failing parameterized test suite**

```swift
import Testing
@testable import AnghkooeyCore

@Suite struct ClozeMarkupParserTests {

    struct ParseCase: Sendable {
        let markup: String
        let expectedIndices: [Int]
        let expectedAnswers: [String]
    }

    static let valid: [ParseCase] = [
        .init(markup: "The {{c1::mitochondria}} is the {{c2::powerhouse}} of the cell",
              expectedIndices: [1, 2], expectedAnswers: ["mitochondria", "powerhouse"]),
        .init(markup: "{{c1::Paris}} is the capital of France",
              expectedIndices: [1], expectedAnswers: ["Paris"]),
        .init(markup: "Water is {{c1::H2O::chemical formula}}",
              expectedIndices: [1], expectedAnswers: ["H2O"]),
    ]

    @Test(arguments: valid) func parsesValidMarkup(_ c: ParseCase) throws {
        let t = try ClozeMarkupParser.parse(c.markup)
        #expect(t.indices == c.expectedIndices)
        #expect(t.deletions.map(\.answer) == c.expectedAnswers)
    }

    @Test func parsesHint() throws {
        let t = try ClozeMarkupParser.parse("Water is {{c1::H2O::chemical formula}}")
        #expect(t.deletions.first?.hint == "chemical formula")
    }

    @Test func rendersQuestionHidingTargetRevealingSiblings() throws {
        let t = try ClozeMarkupParser.parse("The {{c1::mitochondria}} is the {{c2::powerhouse}} of the cell")
        #expect(ClozeMarkupParser.renderQuestion(t, index: 1) == "The […] is the powerhouse of the cell")
        #expect(ClozeMarkupParser.renderQuestion(t, index: 2) == "The mitochondria is the […] of the cell")
    }

    @Test func rendersAnswer() throws {
        let t = try ClozeMarkupParser.parse("The {{c1::mitochondria}} is the {{c2::powerhouse}} of the cell")
        #expect(ClozeMarkupParser.renderAnswer(t, index: 1) == "mitochondria")
    }

    @Test func rejectsNoDeletions() {
        #expect(throws: ClozeParseError.noDeletions) { try ClozeMarkupParser.parse("plain text") }
    }
    @Test func rejectsUnclosed() {
        #expect(throws: ClozeParseError.unclosedMarker) { try ClozeMarkupParser.parse("a {{c1::b") }
    }
    @Test func rejectsDuplicateIndex() {
        #expect(throws: ClozeParseError.duplicateIndex(1)) {
            try ClozeMarkupParser.parse("{{c1::a}} and {{c1::b}}")
        }
    }
    @Test func rejectsEmptyAnswer() {
        #expect(throws: ClozeParseError.emptyAnswer(index: 1)) { try ClozeMarkupParser.parse("{{c1::}}") }
    }
    @Test func rejectsNonPositiveIndex() {
        #expect(throws: ClozeParseError.nonPositiveIndex(0)) { try ClozeMarkupParser.parse("{{c0::a}}") }
    }
}
```

- [ ] **Step 3: Run to verify failure** (`fatalError` / crash). Expected: FAIL.
- [ ] **Step 4: Codex implements `parse`/`renderQuestion`/`renderAnswer`.** Constraints: reject nested `{{`, cap at `maxDeletions`, dedupe-by-index is an *error* not silent collapse, `renderQuestion` replaces only the target marker with `[…]` and substitutes other markers' answers, preserve surrounding whitespace exactly.
- [ ] **Step 5: Run — expected PASS.** Claude verifies locally.
- [ ] **Step 6: Codex fresh-eyes review pass** on the regex/scanner (catch greedy-match and unicode pitfalls). Apply `superpowers:receiving-code-review` rigor.
- [ ] **Step 7: Commit**
```bash
git add Packages/AnghkooeyCore/Sources/AnghkooeyCore/Cloze App/AnghkooeyTests/ClozeMarkupParserTests.swift
git commit -m "feat(core): ClozeMarkupParser — parse/validate/render {{cN::answer::hint}} grammar"
```

---

## Task 4: CardStore — cloze fan-out + persistent sibling burying

**Files:**
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardStore.swift`
- Test: `App/AnghkooeyTests/CardStoreClozeTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Testing
import Foundation
@testable import AnghkooeyCore

@Suite struct CardStoreClozeTests {
    private func makeStore() throws -> CardStore {
        CardStore(container: try AnghkooeyModelContainer.makeInMemoryContainer())
    }

    @Test func fanOutCreatesOneCardPerDeletion() async throws {
        let store = try makeStore()
        let t = try ClozeMarkupParser.parse("The {{c1::mitochondria}} is the {{c2::powerhouse}} of the cell")
        let snaps = try await store.createClozeCards(from: t, tags: ["bio"], now: .now)
        #expect(snaps.count == 2)
        #expect(Set(snaps.map(\.question)).count == 2)        // distinct prompts
        // siblings share a group id (exposed on Snapshot)
        #expect(Set(snaps.compactMap(\.clozeGroupID)).count == 1)
    }

    @Test func reviewingOneSiblingBuriesOthersUntilNextDay() async throws {
        let store = try makeStore()
        let t = try ClozeMarkupParser.parse("The {{c1::a}} and the {{c2::b}}")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snaps = try await store.createClozeCards(from: t, tags: [], now: now)
        // Both due now.
        #expect(try await store.dueCards(asOf: now).count == 2)
        // Review the first sibling.
        let engine = LiveFSRS6Engine()
        let out = engine.next(card: snaps[0].schedulingCard, rating: .good, now: now)
        try await store.apply(out, to: snaps[0].id, grade: .good, now: now)
        // Same day: the other sibling is buried, so only 0 remain due (reviewed one rescheduled).
        let dueSameDay = try await store.dueCards(asOf: now.addingTimeInterval(60))
        #expect(dueSameDay.allSatisfy { $0.id != snaps[1].id })   // sibling not served same day
        // Next day: sibling resurfaces.
        let nextDay = now.addingTimeInterval(86_400 + 60)
        #expect(try await store.dueCards(asOf: nextDay).contains { $0.id == snaps[1].id })
    }
}
```

- [ ] **Step 2: Run — expected FAIL** (`createClozeCards` undefined; `clozeGroupID` not on Snapshot).

- [ ] **Step 3: Add `clozeGroupID` to `Card.Snapshot`**

Add `public let clozeGroupID: UUID?` (default `nil` in the memberwise init), set it in `init(from:)` via `card.clozeGroupID`, and mirror in `MockCardStore` snapshot constructions (default nil). Keep `cardType`/`clozeIndex` off the snapshot unless the UI needs them — YAGNI; add only `clozeGroupID` now (burying needs it).

- [ ] **Step 4: Implement `createClozeCards` on the protocol + actor + mock**

Protocol addition:
```swift
/// Fans a cloze template into one card per deletion, all sharing a fresh
/// `clozeGroupID`. Each card's `question`/`answer` are pre-rendered.
func createClozeCards(from template: ClozeTemplate, tags: [String], now: Date) async throws -> [Card.Snapshot]
```
Actor impl:
```swift
public func createClozeCards(from template: ClozeTemplate, tags: [String], now: Date) async throws -> [Card.Snapshot] {
    let tagObjects = try findOrCreateTags(tags)
    let groupID = UUID()
    var snaps: [Card.Snapshot] = []
    for idx in template.indices {
        let card = Card(
            question: ClozeMarkupParser.renderQuestion(template, index: idx),
            answer: ClozeMarkupParser.renderAnswer(template, index: idx),
            createdAt: now, updatedAt: now, tags: tagObjects,
            state: .new, dueAt: now, sourceSpan: nil,
            cardType: .cloze, clozeGroupID: groupID, clozeIndex: idx,
            clozeSourceText: template.markup, clozeBuriedUntil: nil
        )
        modelContext.insert(card)
        snaps.append(Card.Snapshot(from: card))
    }
    do { try modelContext.save() } catch { modelContext.rollback(); throw error }
    return snaps
}
```
Mock impl: build N snapshots with a shared `clozeGroupID`, append to `cards`.

- [ ] **Step 5: Add the bury filter to `dueCards` and the bury write to `apply`**

`dueCards` — exclude buried cards and sort deterministically:
```swift
public func dueCards(asOf now: Date) async throws -> [Card.Snapshot] {
    let predicate = #Predicate<Card> { $0.dueAt <= now &&
        ($0.clozeBuriedUntil == nil || $0.clozeBuriedUntil! <= now) }
    let descriptor = FetchDescriptor<Card>(predicate: predicate,
        sortBy: [SortDescriptor(\.dueAt), SortDescriptor(\.id)])
    return try modelContext.fetch(descriptor).map { Card.Snapshot(from: $0) }
}
```
`apply` — after updating the reviewed card, bury its same-group siblings until next local day:
```swift
// After the reviewed card is updated, before save():
if let groupID = card.clozeGroupID {
    let buryUntil = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
    let reviewedID = card.id
    let sibPredicate = #Predicate<Card> { $0.clozeGroupID == groupID && $0.id != reviewedID }
    for sib in try modelContext.fetch(FetchDescriptor<Card>(predicate: sibPredicate)) {
        sib.clozeBuriedUntil = buryUntil
    }
}
```
Mirror the bury logic in `MockCardStore.apply` (set a `clozeBuriedUntil`-equivalent on sibling snapshots; add `clozeBuriedUntil` to Snapshot if the mock needs to honor it in `dueCards`). For the mock, add `public let clozeBuriedUntil: Date?` to Snapshot and filter on it in both `dueCards` implementations.

- [ ] **Step 6: Run — expected PASS.**
- [ ] **Step 7: Codex reviewer pass** on the predicate (SwiftData `#Predicate` optional-unwrap of `clozeBuriedUntil!` — verify it compiles under the macro; if not, hoist with a sentinel `Date.distantPast`, per `feedback_swiftdata_predicate_local_binding`).
- [ ] **Step 8: Commit**
```bash
git add Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardStore.swift App/AnghkooeyTests/CardStoreClozeTests.swift
git commit -m "feat(core): cloze fan-out + persistent sibling burying in CardStore"
```

---

## Task 5: AnkiNoteMapper ordinal identity + cloze skip

**Files:**
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Import/AnkiNoteMapper.swift`
- Test: `App/AnghkooeyTests/AnkiNoteMapperTests.swift`

- [ ] **Step 1: Add failing tests** (append to existing suite)

```swift
@Test func sourceSpanIncludesCardOrdinal() {
    // A note that maps to multiple cards must produce distinct source spans.
    let span0 = AnkiNoteMapper.sourceSpan(noteID: 42, cardOrd: 0)
    let span1 = AnkiNoteMapper.sourceSpan(noteID: 42, cardOrd: 1)
    #expect(span0 == "anki:42:0")
    #expect(span1 == "anki:42:1")
    #expect(span0 != span1)
}

@Test func clozeNoteTypesAreSkipped() {
    // Cloze import stays deferred past v2 — mapper must skip, not corrupt.
    #expect(AnkiNoteMapper.isClozeModel(name: "Cloze") == true)
    #expect(AnkiNoteMapper.isClozeModel(name: "Basic") == false)
}
```

- [ ] **Step 2: Run — expected FAIL.**
- [ ] **Step 3: Implement.** Change the `sourceSpan` construction from `"anki:\(note.id)"` to `"anki:\(note.id):\(cardOrd)"` (thread the card ordinal through from the parser layer; if the current mapper only sees notes, add the ordinal parameter to the mapping entry point and default existing callers to `0`). Add `static func sourceSpan(noteID:cardOrd:) -> String` and `static func isClozeModel(name:) -> Bool` (case-insensitive contains "cloze"). Where note types are mapped, skip models where `isClozeModel` is true and log the skip via `CoreLog`.
- [ ] **Step 4: Run — expected PASS.** Re-run the full `AnkiImporterTests`/`AnkiPackageParserTests` to confirm no regression in the existing Basic path.
- [ ] **Step 5: Commit**
```bash
git add Packages/AnghkooeyCore/Sources/AnghkooeyCore/Import/AnkiNoteMapper.swift App/AnghkooeyTests/AnkiNoteMapperTests.swift
git commit -m "fix(import): ordinal-aware Anki source identity + skip cloze note types"
```

---

## Task 6: Cloze authoring service (@Generable)

**Files:**
- Create: `…/AnghkooeyIntelligence/Cloze/ClozeDraft.swift`, `ClozeResponse.swift`, `ClozeAuthoringService.swift`, `LiveClozeAuthoringService.swift`, `MockClozeAuthoringService.swift`
- Test: `App/AnghkooeyTests/ClozeAuthoringServiceTests.swift`

> Mirror the `CardAuthoringService` family exactly (`AuthorResponse`/`CardDraft`/`LiveCardAuthoringService`/`SnapshotAccumulator`). Reuse `AuthoringAvailability`/`AuthoringError`. Per `feedback_foundation_models_api`: `streamResponse(to:generating:)`, `snapshot.content.items`, all `PartiallyGenerated` fields Optional, `@Generable` ≠ Sendable (don't add Sendable to the draft beyond what compiles).

- [ ] **Step 1: Write the failing test (mock-backed)**

```swift
import Testing
@testable import AnghkooeyIntelligence

@Suite struct ClozeAuthoringServiceTests {
    @Test func mockYieldsConfiguredDrafts() async throws {
        let mock = MockClozeAuthoringService()
        mock.stubbed = [ClozeDraft(markedText: "The {{c1::a}} is {{c2::b}}", proposedTags: ["x"])]
        var got: [ClozeDraft] = []
        for try await d in try await mock.generateClozeDrafts(from: "passage") { got.append(d) }
        #expect(got.count == 1)
        #expect(got.first?.markedText.contains("{{c1::a}}") == true)
    }

    @Test func emptyInputThrows() async {
        let mock = MockClozeAuthoringService()
        await #expect(throws: AuthoringError.self) {
            _ = try await mock.generateClozeDrafts(from: "   ")
        }
    }
}
```

- [ ] **Step 2: Run — expected FAIL.**
- [ ] **Step 3: Create the `@Generable` types**

```swift
// ClozeDraft.swift
import FoundationModels
@Generable
public struct ClozeDraft: Codable, Equatable {
    /// Cloze markup using {{cN::answer::hint}} markers.
    public var markedText: String
    /// Proposed lowercase topic tags.
    public var proposedTags: [String]
    public init(markedText: String, proposedTags: [String] = []) {
        self.markedText = markedText; self.proposedTags = proposedTags
    }
}
```
```swift
// ClozeResponse.swift
import FoundationModels
@Generable
public struct ClozeResponse: Codable {
    public var items: [ClozeDraft]
}
```

- [ ] **Step 4: Create the protocol + Mock + Live**

Protocol:
```swift
public protocol ClozeAuthoringService: Sendable {
    var availability: AuthoringAvailability { get async }
    func generateClozeDrafts(from text: String) async throws -> AsyncThrowingStream<ClozeDraft, Error>
}
```
`MockClozeAuthoringService`: `public var stubbed: [ClozeDraft] = []`; throw `AuthoringError.emptyInput` on blank input; otherwise yield `stubbed`.
`LiveClozeAuthoringService`: copy `LiveCardAuthoringService` structure with a cloze-specific system prompt:
> "You are a spaced-repetition cloze author. Given a passage, return it with the most salient facts wrapped in Anki-style cloze markers `{{c1::answer}}`, `{{c2::answer}}`, … Rules: each deletion hides exactly one fact; number deletions sequentially from c1; never nest markers; do not invent facts; propose 1–3 lowercase tags. If no memorable facts exist, return an empty list."
Stream `ClozeResponse`, read `snapshot.content.items`, emit drafts whose `markedText` is non-empty.

- [ ] **Step 5: Run — expected PASS.**
- [ ] **Step 6: Codex reviewer pass** on the Live streaming (PartiallyGenerated optionality, cancellation via `continuation.onTermination`).
- [ ] **Step 7: Commit**
```bash
git add Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Cloze App/AnghkooeyTests/ClozeAuthoringServiceTests.swift
git commit -m "feat(intelligence): ClozeAuthoringService — @Generable cloze markup authoring"
```

---

## Task 7: Cloze authoring UI + capture mode toggle

**Files:**
- Create: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Cloze/ClozeAuthoringView.swift`
- Modify: the existing capture entry point (locate during the task: `grep -rln "CardAuthoringService\|AuthoringView" Packages/AnghkooeyUI/Sources`) to add a Q&A / Cloze segmented toggle.

> UI work is hard to unit-test meaningfully; rely on a lightweight view-model test plus device QA. The editor — not raw AI output — is the source of truth (spec §M7.1/§M7.3). Parser validation must run before the Accept button enables.

- [ ] **Step 1: Write a failing view-model test**

```swift
import Testing
@testable import AnghkooeyUI
@testable import AnghkooeyCore

@Suite struct ClozeAuthoringViewModelTests {
    @MainActor @Test func acceptDisabledUntilMarkupValid() {
        let vm = ClozeAuthoringViewModel(store: MockCardStore())
        vm.markedText = "plain text, no deletions"
        #expect(vm.canAccept == false)               // parser rejects → cannot accept
        vm.markedText = "The {{c1::mitochondria}} is the powerhouse"
        #expect(vm.canAccept == true)
    }

    @MainActor @Test func acceptFansOutSiblings() async throws {
        let store = MockCardStore()
        let vm = ClozeAuthoringViewModel(store: store)
        vm.markedText = "The {{c1::a}} and the {{c2::b}}"
        try await vm.accept(tags: ["bio"], now: .now)
        #expect(store.cards.count == 2)
    }
}
```

- [ ] **Step 2: Run — expected FAIL.**
- [ ] **Step 3: Implement `ClozeAuthoringViewModel`** (in the same file or a sibling): holds `markedText`, computes `canAccept` via `try? ClozeMarkupParser.parse(markedText) != nil`, and `accept` parses then calls `store.createClozeCards(from:tags:now:)`.
- [ ] **Step 4: Implement `ClozeAuthoringView`**: a TextEditor bound to `markedText` (the tap-to-blank affordance can wrap selected text in `{{cN::…}}`; minimal version = manual markup + live parse preview listing detected deletions), a generate button (calls `ClozeAuthoringService`), a live preview of detected deletions, and an Accept button gated on `canAccept`.
- [ ] **Step 5: Add the Q&A / Cloze toggle** to the capture entry point; route to `ClozeAuthoringView` when Cloze is selected.
- [ ] **Step 6: Run — expected PASS.**
- [ ] **Step 7: Regenerate project if `project.yml` changed** (`cd App && xcodegen generate && cd .. && python3 scripts/patch_privacy_info.py`), then full test run + build.
- [ ] **Step 8: Commit**
```bash
git add Packages/AnghkooeyUI App/AnghkooeyTests/ClozeAuthoringViewModelTests.swift App/project.yml
git commit -m "feat(ui): cloze authoring view + Q&A/Cloze capture toggle"
```

---

## Task 8: ADR-0003 + M7 exit review (Opus)

- [ ] **Step 1: Write `docs/DECISIONS/0003-cloze-data-model.md`** — decision (one card per deletion, baked Q/A, group immutability, persistent bury), context, rejected alternatives (one-card-all-blanks, render-on-the-fly), consequences (re-author instead of edit). Opus authors; Codex fresh-eyes review.
- [ ] **Step 2: Append the M7 section to `ARCHITECTURE.md`** (per `reference_architecture_md.md`: append-only, one section per milestone).
- [ ] **Step 3: Re-read `foundation.md` §out-of-scope bullet-by-bullet** (`feedback_foundation_recheck_at_milestone_close`) — confirm no silent v1 omissions resurface; note cloze now moves from "v2" to "shipped".
- [ ] **Step 4: Run the full test suite + device QA** (see Exit Gates) and record results in the PR body honestly (`feedback_code_complete_vs_pass`).
- [ ] **Step 5: Commit + open PR** (no squash — `reference_github_repo`).

---

## Exit Gates (M7)

- [ ] `xcodebuild test` green; all new + existing tests pass.
- [ ] CloudKit V5 container builds (Task 2).
- [ ] `ClozeMarkupParser` parameterized parse/validate/render + malformed-input edge cases pass.
- [ ] V4→V5 lightweight migration test passes.
- [ ] Persistent sibling-bury test passes across a simulated relaunch (next-day resurfacing).
- [ ] `AnkiNoteMapper` ordinal-identity + cloze-skip tests pass; existing Basic-import tests still green.
- [ ] Device QA on iPhone 17 Pro sim (UI taps are unreliable in automation per `feedback_simulator_ui_interaction` — do this manually): author a passage as Cloze → edit a deletion → Accept → N siblings created → review one → sibling buried today, resurfaces next day after force-quit/relaunch.
- [ ] ADR-0003 merged; `ARCHITECTURE.md` appended; `foundation.md` re-check done.

---

## Self-Review Notes (author)

- **Spec coverage:** every §M7 requirement maps to a task — data model/migration (T1), CloudKit gate (T2), parser+validation (T3), fan-out+persistent burying (T4), Anki ordinal fix+cloze skip (T5), `@Generable` authoring (T6), editor-as-source-of-truth UI (T7), ADR/immutability/foundation-recheck (T8).
- **Immutability invariant** is enforced by *omission* — no per-card `clozeSourceText` edit path is added; the existing `update(id:question:answer:tags:)` stays Q&A-oriented. Flagged for the executor: do NOT wire cloze cards into the plain edit screen.
- **Type consistency:** `createClozeCards(from:tags:now:)`, `ClozeMarkupParser.parse/renderQuestion/renderAnswer`, `ClozeTemplate.indices`, `ClozeDraft.markedText`, `ClozeResponse.items` used consistently across T3/T4/T6/T7.
