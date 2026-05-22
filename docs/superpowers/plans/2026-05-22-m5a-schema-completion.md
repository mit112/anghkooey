# M5.A — Schema Completion (Step-Machine Persistence) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist the five FSRS-6 step-machine fields (`reps`, `lapses`, `learningSteps`, `scheduledDays`, `elapsedDays`) on `Card` so step position survives app restarts, via the project's first real SwiftData versioned migration (V1 → V2).

**Architecture:** Introduce `AnghkooeySchemaV2` namespacing a new `Card` model carrying the extra columns (all with safe defaults). Migrate from V1 to V2 with `MigrationStage.lightweight` since every added field has a default value. A top-level `Card` typealias points to the current schema version so downstream call sites (CardStore, ReviewSession, AppState, tests) compile unchanged after import paths land. `Card.Snapshot` gains the five fields and stops zeroing them in `schedulingCard`. `CardStore.apply` writes them from `output.card`.

**Tech Stack:** Swift 6, SwiftData (`@Model`, `VersionedSchema`, `SchemaMigrationPlan`, `MigrationStage.lightweight`), Swift Testing, `xcodebuild test` for the app-target migration test (per `feedback_app_test_target_wiring.md`).

**Background you need before starting:**
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/Card.swift` — current `@Model final class Card` (top-level).
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeySchemaV1.swift` — `VersionedSchema` + empty `AnghkooeyMigrationPlan`.
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardStore.swift` — `Card.Snapshot` (lines 4–87), `CardStore` actor, `MockCardStore`.
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeyModelContainer.swift` — container factory; currently builds the schema from `AnghkooeySchemaV1.self`.
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/SchedulingCard.swift` — note `scheduledDays`/`elapsedDays` are `Double`, `reps`/`lapses`/`learningSteps` are `Int`.
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Scheduling/SchedulerOutput.swift` — `output.card: SchedulingCard` carries the post-review values to persist.
- `memory/feedback_swiftdata_schema_api.md` — use `Schema(versionedSchema: …)` (existing code does this) and `Schema(AnghkooeySchemaV1.models)` in tests; `.allModels` doesn't exist.
- `memory/feedback_app_test_target_wiring.md` — app-target tests run via `xcodebuild test -only-testing:AnghkooeyTests`, not `swift test`.

**Out of scope (deferred to other M5 lanes):**
- CloudKit sync wiring (Lane future).
- Any UI change (Lane D).
- Performance instrumentation (Lane B).

---

## File Structure

**Create:**
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeySchemaV2.swift` — V2 `VersionedSchema` enum + nested `Card` model with the five new fields.
- `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/SchemaMigrationTests.swift` — Swift Testing suite covering: defaults on V2-new cards, V1→V2 lightweight migration preserves data + zero-fills new columns, snapshot round-trip with non-zero step-machine state.

**Modify:**
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/Card.swift` — move the existing class body into `AnghkooeySchemaV1.Card` namespace; keep file as the V1 home.
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeySchemaV1.swift` — update `models` to reference `AnghkooeySchemaV1.Card.self`. Keep `Tag` and `ReviewLog` top-level (unchanged across versions).
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeyModelContainer.swift` — build schema from `AnghkooeySchemaV2.self`; wire `AnghkooeyMigrationPlan` with the V1→V2 stage.
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardStore.swift` — top-level `typealias Card = AnghkooeySchemaV2.Card`; extend `Card.Snapshot` with five fields; update `schedulingCard` to use them; update `CardStore.create` / `apply`; update `MockCardStore`.
- `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/CardStoreTests.swift` — extend existing assertions to verify step-machine fields persist through `apply`.
- `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/Integration/EndToEndReviewFlowTests.swift` — add assertion that `reps`/`scheduledDays` increment across a multi-review run.
- `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewSession.swift` & `Tests/.../ReviewSessionTests.swift` — only if compiler complains; updates to `Card.Snapshot` initializers must remain source-compatible by giving the new params default values.
- `ARCHITECTURE.md` — append an M5.A subsection under §M5 once migration lands.

**Do not touch:**
- `Tag.swift`, `ReviewLog.swift` — unchanged across V1 and V2.
- Any UI screen, AppState, or Share Extension code.

---

## Task 1: Branch and snapshot current baseline

**Files:** none (workspace setup).

- [ ] **Step 1: Verify clean state on `main`**

```bash
git checkout main
git pull
git status
```
Expected: `nothing to commit, working tree clean`. If PR #3 (m4/review-loop) hasn't been merged yet, abort and merge it first; this plan branches from `main`.

- [ ] **Step 2: Create `m5/polish` branch**

```bash
git checkout -b m5/polish
```

- [ ] **Step 3: Confirm baseline tests green before touching schema**

```bash
cd Packages/AnghkooeyCore && swift test 2>&1 | tail -20
```
Expected: all tests pass. If anything is red on `main`, stop and fix before continuing.

- [ ] **Step 4: Commit a no-op marker so the migration work has a clean diff base**

```bash
git commit --allow-empty -m "chore(m5.a): start schema completion lane"
```

---

## Task 2: Namespace existing `Card` under `AnghkooeySchemaV1`

The goal of this task is purely structural: get the V1 model living inside the V1 namespace so V2 can introduce a parallel `Card`. No fields change.

**Files:**
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/Card.swift`
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeySchemaV1.swift`

- [ ] **Step 1: Wrap `Card` in `AnghkooeySchemaV1` namespace**

Replace the entire body of `Card.swift` with:

```swift
import Foundation
import SwiftData

public extension AnghkooeySchemaV1 {
    /// V1 of the Card model. Frozen — do not add or remove stored
    /// properties. Schema-evolving changes happen by introducing a new
    /// `AnghkooeySchemaVN.Card` and a `MigrationStage` in
    /// `AnghkooeyMigrationPlan`.
    @Model
    final class Card {
        @Attribute(.unique) var id: UUID
        var question: String
        var answer: String
        var createdAt: Date
        var updatedAt: Date
        var tags: [Tag]
        var state: CardState
        var stability: Double
        var difficulty: Double
        var dueAt: Date
        var lastReviewedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \ReviewLog.card)
        var reviewLogs: [ReviewLog]

        var sourceSpan: String?

        init(
            id: UUID = UUID(),
            question: String,
            answer: String,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            tags: [Tag] = [],
            state: CardState = .new,
            stability: Double = 0,
            difficulty: Double = 0,
            dueAt: Date = .now,
            lastReviewedAt: Date? = nil,
            reviewLogs: [ReviewLog] = [],
            sourceSpan: String? = nil
        ) {
            self.id = id
            self.question = question
            self.answer = answer
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.tags = tags
            self.state = state
            self.stability = stability
            self.difficulty = difficulty
            self.dueAt = dueAt
            self.lastReviewedAt = lastReviewedAt
            self.reviewLogs = reviewLogs
            self.sourceSpan = sourceSpan
        }
    }
}
```

Note: the inner type is package-internal (no `public` on the class). Downstream code must go through the top-level `Card` typealias added in Task 4, which will be `public` and bound to V2. V1 is only referenced from migration plumbing inside the package.

- [ ] **Step 2: Update V1 schema's `models` array to point at the namespaced type**

In `AnghkooeySchemaV1.swift`, change:
```swift
public static var models: [any PersistentModel.Type] {
    [Card.self, ReviewLog.self, Tag.self]
}
```
to:
```swift
public static var models: [any PersistentModel.Type] {
    [AnghkooeySchemaV1.Card.self, ReviewLog.self, Tag.self]
}
```

- [ ] **Step 3: Confirm the package no longer builds (expected)**

```bash
cd Packages/AnghkooeyCore && swift build 2>&1 | tail -30
```
Expected: `Card` references in `CardStore.swift` etc. fail with "cannot find 'Card' in scope". This is the point of this task — Task 3/4 will add V2 and a top-level typealias.

- [ ] **Step 4: Do NOT commit yet**

Leave broken; the next two tasks restore the build. Committing a broken intermediate state would hurt bisection.

---

## Task 3: Add `AnghkooeySchemaV2` with new fields

**Files:**
- Create: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeySchemaV2.swift`

- [ ] **Step 1: Write the V2 schema file**

```swift
import Foundation
import SwiftData

/// V2 of the Anghkooey persistence schema.
///
/// Adds the FSRS-6 step-machine fields (`reps`, `lapses`, `learningSteps`,
/// `scheduledDays`, `elapsedDays`) to `Card`. All additions carry safe
/// defaults so V1 → V2 is a lightweight migration (no copy logic needed).
public enum AnghkooeySchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [AnghkooeySchemaV2.Card.self, ReviewLog.self, Tag.self]
    }
}

public extension AnghkooeySchemaV2 {
    /// V2 of the Card model. Adds five FSRS step-machine columns.
    @Model
    final class Card {
        @Attribute(.unique) var id: UUID
        var question: String
        var answer: String
        var createdAt: Date
        var updatedAt: Date
        var tags: [Tag]
        var state: CardState
        var stability: Double
        var difficulty: Double
        var dueAt: Date
        var lastReviewedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \ReviewLog.card)
        var reviewLogs: [ReviewLog]

        var sourceSpan: String?

        // M5.A additions — step-machine state.
        var reps: Int = 0
        var lapses: Int = 0
        var learningSteps: Int = 0
        var scheduledDays: Double = 0
        var elapsedDays: Double = 0

        init(
            id: UUID = UUID(),
            question: String,
            answer: String,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            tags: [Tag] = [],
            state: CardState = .new,
            stability: Double = 0,
            difficulty: Double = 0,
            dueAt: Date = .now,
            lastReviewedAt: Date? = nil,
            reviewLogs: [ReviewLog] = [],
            sourceSpan: String? = nil,
            reps: Int = 0,
            lapses: Int = 0,
            learningSteps: Int = 0,
            scheduledDays: Double = 0,
            elapsedDays: Double = 0
        ) {
            self.id = id
            self.question = question
            self.answer = answer
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.tags = tags
            self.state = state
            self.stability = stability
            self.difficulty = difficulty
            self.dueAt = dueAt
            self.lastReviewedAt = lastReviewedAt
            self.reviewLogs = reviewLogs
            self.sourceSpan = sourceSpan
            self.reps = reps
            self.lapses = lapses
            self.learningSteps = learningSteps
            self.scheduledDays = scheduledDays
            self.elapsedDays = elapsedDays
        }
    }
}
```

- [ ] **Step 2: Build to confirm V2 compiles in isolation**

```bash
cd Packages/AnghkooeyCore && swift build 2>&1 | tail -20
```
Expected: still broken (CardStore + other call sites still can't find top-level `Card`). The V2 file itself should compile clean — look for any error originating in `AnghkooeySchemaV2.swift` and fix before moving on.

---

## Task 4: Add top-level `Card` typealias and wire migration plan

**Files:**
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeySchemaV1.swift`
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeyModelContainer.swift`
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardStore.swift` (add typealias only, leave Snapshot for Task 5)

- [ ] **Step 1: Add the migration stage to `AnghkooeyMigrationPlan`**

In `AnghkooeySchemaV1.swift`, replace the `AnghkooeyMigrationPlan` enum:

```swift
public enum AnghkooeyMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [AnghkooeySchemaV1.self, AnghkooeySchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: AnghkooeySchemaV1.self,
                toVersion: AnghkooeySchemaV2.self
            )
        ]
    }
}
```

- [ ] **Step 2: Switch the container factory to V2**

In `AnghkooeyModelContainer.swift`, replace `AnghkooeySchemaV1.self` with `AnghkooeySchemaV2.self`:

```swift
public static func makeInMemoryContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: AnghkooeySchemaV2.self)
    let configuration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true
    )

    do {
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AnghkooeyMigrationPlan.self,
            configurations: [configuration]
        )
        CoreLog.persistence.debug("In-memory ModelContainer created (v2 schema)")
        return container
    } catch {
        CoreLog.persistence.error(
            "ModelContainer init failed: \(error.localizedDescription, privacy: .public)"
        )
        throw PersistenceError.containerCreationFailed(underlying: error)
    }
}
```

- [ ] **Step 3: Add the top-level `Card` typealias**

At the very top of `CardStore.swift` (above the existing `// MARK: - Card.Snapshot`), add:

```swift
import Foundation
import SwiftData

/// Public alias for the current persisted Card model. Downstream code
/// (UI, AppState, tests) should reference `Card` — never
/// `AnghkooeySchemaVN.Card` directly — so future migrations don't ripple
/// through call sites.
public typealias Card = AnghkooeySchemaV2.Card
```

If `CardStore.swift` already has `import Foundation` / `import SwiftData` at the top, do not duplicate; just insert the typealias after the imports.

- [ ] **Step 4: Build the package**

```bash
cd Packages/AnghkooeyCore && swift build 2>&1 | tail -30
```
Expected: build succeeds. If there's an "ambiguous use of 'Card'" error anywhere, it means a file is importing both V1.Card and the top-level alias — search for `AnghkooeySchemaV1.Card` outside `AnghkooeySchemaV1.swift` and the new schema file, and remove the qualifier.

- [ ] **Step 5: Run the existing test suite**

```bash
cd Packages/AnghkooeyCore && swift test 2>&1 | tail -30
```
Expected: all pre-existing tests still pass. Snapshot still has the old field set; `schedulingCard` still zero-fills step fields. Behavior is unchanged. Migration plumbing is now in place but unobserved.

- [ ] **Step 6: Commit**

```bash
git add Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence
git commit -m "feat(m5.a): introduce AnghkooeySchemaV2 with step-machine fields, lightweight migration"
```

---

## Task 5: Migration test — V1 store opens as V2 with zero-filled new columns

This is the test that proves the migration plan actually runs, not just compiles.

**Files:**
- Create: `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/SchemaMigrationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import SwiftData
import Testing
@testable import AnghkooeyCore

@Suite("Schema migration V1 → V2")
struct SchemaMigrationTests {

    /// A V1-only persistent store is opened with the V2 schema + migration
    /// plan. Pre-existing rows survive; the five new columns read back as 0.
    @Test func migratesV1StoreToV2WithZeroDefaults() throws {
        let storeURL = URL.temporaryDirectory.appending(
            path: "anghkooey-migration-\(UUID().uuidString).store"
        )
        defer { try? FileManager.default.removeItem(at: storeURL) }

        // --- Phase 1: write one row using V1 only ---
        do {
            let v1Schema = Schema(versionedSchema: AnghkooeySchemaV1.self)
            let v1Config = ModelConfiguration(
                schema: v1Schema,
                url: storeURL
            )
            let v1Container = try ModelContainer(
                for: v1Schema,
                migrationPlan: nil,
                configurations: [v1Config]
            )
            let ctx = ModelContext(v1Container)
            let v1Card = AnghkooeySchemaV1.Card(
                question: "Q",
                answer: "A",
                stability: 1.5,
                difficulty: 4.2,
                dueAt: Date(timeIntervalSince1970: 1_700_000_000),
                lastReviewedAt: Date(timeIntervalSince1970: 1_699_990_000)
            )
            ctx.insert(v1Card)
            try ctx.save()
        }

        // --- Phase 2: reopen with V2 schema + migration plan ---
        let v2Schema = Schema(versionedSchema: AnghkooeySchemaV2.self)
        let v2Config = ModelConfiguration(schema: v2Schema, url: storeURL)
        let v2Container = try ModelContainer(
            for: v2Schema,
            migrationPlan: AnghkooeyMigrationPlan.self,
            configurations: [v2Config]
        )
        let ctx = ModelContext(v2Container)
        let cards = try ctx.fetch(FetchDescriptor<Card>())

        #expect(cards.count == 1)
        let card = try #require(cards.first)
        #expect(card.question == "Q")
        #expect(card.answer == "A")
        #expect(card.stability == 1.5)
        #expect(card.difficulty == 4.2)

        // The five new columns must default to zero on migrated rows.
        #expect(card.reps == 0)
        #expect(card.lapses == 0)
        #expect(card.learningSteps == 0)
        #expect(card.scheduledDays == 0.0)
        #expect(card.elapsedDays == 0.0)
    }

    @Test func freshV2CardDefaultsAllStepFieldsToZero() throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let ctx = ModelContext(container)
        let card = Card(question: "Q", answer: "A")
        ctx.insert(card)
        try ctx.save()

        #expect(card.reps == 0)
        #expect(card.lapses == 0)
        #expect(card.learningSteps == 0)
        #expect(card.scheduledDays == 0.0)
        #expect(card.elapsedDays == 0.0)
    }
}
```

- [ ] **Step 2: Run only this test, expect PASS**

```bash
cd Packages/AnghkooeyCore && swift test --filter SchemaMigrationTests 2>&1 | tail -30
```
Expected: both tests pass. The lightweight migration should be a no-op at the SwiftData level since every added column has a default — but the test is what proves it. If the V1 phase fails to write because something tries to use the V2 schema, double-check that `migrationPlan: nil` is passed in Phase 1 and that `AnghkooeySchemaV1.Card` is being instantiated, not the top-level alias.

- [ ] **Step 3: Commit**

```bash
git add Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/SchemaMigrationTests.swift
git commit -m "test(m5.a): V1→V2 lightweight migration preserves data and zero-fills step-machine columns"
```

---

## Task 6: Extend `Card.Snapshot` with step-machine fields

**Files:**
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardStore.swift`

- [ ] **Step 1: Add the five new properties to `Card.Snapshot`**

In the `struct Snapshot: Sendable, Equatable { ... }` block, after `lastReviewedAt`, add:

```swift
public let reps: Int
public let lapses: Int
public let learningSteps: Int
public let scheduledDays: Double
public let elapsedDays: Double
```

- [ ] **Step 2: Extend the designated initializer with defaulted parameters**

Replace the existing `public init(...)` of `Snapshot` with:

```swift
public init(
    id: UUID,
    question: String,
    answer: String,
    sourceSpan: String? = nil,
    state: CardState,
    stability: Double,
    difficulty: Double,
    dueAt: Date,
    lastReviewedAt: Date? = nil,
    reps: Int = 0,
    lapses: Int = 0,
    learningSteps: Int = 0,
    scheduledDays: Double = 0,
    elapsedDays: Double = 0
) {
    self.id = id
    self.question = question
    self.answer = answer
    self.sourceSpan = sourceSpan
    self.state = state
    self.stability = stability
    self.difficulty = difficulty
    self.dueAt = dueAt
    self.lastReviewedAt = lastReviewedAt
    self.reps = reps
    self.lapses = lapses
    self.learningSteps = learningSteps
    self.scheduledDays = scheduledDays
    self.elapsedDays = elapsedDays
}
```

Defaults preserve source compatibility with the `MockCardStore` and `ReviewSessionTests` call sites that construct `Snapshot` manually.

- [ ] **Step 3: Read the new fields in `init(from:)`**

Replace the existing `init(from card: Card)` body with:

```swift
init(from card: Card) {
    self.init(
        id: card.id,
        question: card.question,
        answer: card.answer,
        sourceSpan: card.sourceSpan,
        state: card.state,
        stability: card.stability,
        difficulty: card.difficulty,
        dueAt: card.dueAt,
        lastReviewedAt: card.lastReviewedAt,
        reps: card.reps,
        lapses: card.lapses,
        learningSteps: card.learningSteps,
        scheduledDays: card.scheduledDays,
        elapsedDays: card.elapsedDays
    )
}
```

- [ ] **Step 4: Stop zero-filling in `schedulingCard`**

Replace the `var schedulingCard: SchedulingCard { ... }` body with:

```swift
/// Reconstructs a `SchedulingCard` suitable for passing to `FSRS6Engine`.
///
/// All step-machine fields are now persisted (M5.A), so the scheduler
/// receives the real position on every call rather than a zeroed proxy.
public var schedulingCard: SchedulingCard {
    SchedulingCard(
        state: state,
        stability: stability,
        difficulty: difficulty,
        due: dueAt,
        reps: reps,
        lapses: lapses,
        learningSteps: learningSteps,
        scheduledDays: scheduledDays,
        elapsedDays: elapsedDays,
        lastReview: lastReviewedAt
    )
}
```

Also delete the M4 "Note:" paragraph in the doc comment that says these fields default to 0; replace it with a one-liner: `As of M5.A all FSRS fields including step-machine state are persisted and round-trip through this snapshot.`

- [ ] **Step 5: Build and run existing tests**

```bash
cd Packages/AnghkooeyCore && swift test 2>&1 | tail -30
```
Expected: all tests still pass. New columns default to 0 everywhere so behavior is unchanged. Compile errors at this point would most likely be `MockCardStore.create` — its `Snapshot(...)` call works because all new params have defaults.

- [ ] **Step 6: Commit**

```bash
git add Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardStore.swift
git commit -m "feat(m5.a): Card.Snapshot carries step-machine fields; schedulingCard no longer zeros them"
```

---

## Task 7: Persist `output.card` step-machine fields in `CardStore.apply`

This is the behavioral change that makes the persisted fields actually mean something.

**Files:**
- Modify: `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardStore.swift`
- Modify: `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/CardStoreTests.swift`

- [ ] **Step 1: Write the failing test in `CardStoreTests.swift`**

Open the existing file and add a new `@Test` method at the bottom of the suite:

```swift
@Test func applyPersistsStepMachineFields() async throws {
    let container = try AnghkooeyModelContainer.makeInMemoryContainer()
    let store = CardStore(container: container)
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    let snap = try await store.create(
        question: "Q", answer: "A", sourceSpan: nil, now: now
    )

    // Hand-build a SchedulerOutput with non-zero step-machine state to
    // verify it round-trips through persistence.
    let updatedCard = SchedulingCard(
        state: .learning,
        stability: 2.0,
        difficulty: 5.0,
        due: now.addingTimeInterval(600),
        reps: 1,
        lapses: 0,
        learningSteps: 1,
        scheduledDays: 0.0,
        elapsedDays: 0.0,
        lastReview: now
    )
    let log = ReviewLogEntry(
        rating: .good,
        stateBefore: .new,
        stabilityBefore: 0,
        difficultyBefore: 0,
        elapsedDays: 0,
        scheduledDays: 0
    )
    let output = SchedulerOutput(card: updatedCard, log: log)
    try await store.apply(output, to: snap.id, grade: .good, now: now)

    let due = try await store.dueCards(asOf: now.addingTimeInterval(10_000))
    let persisted = try #require(due.first(where: { $0.id == snap.id }))
    #expect(persisted.reps == 1)
    #expect(persisted.learningSteps == 1)
    #expect(persisted.state == .learning)
}
```

(If `ReviewLogEntry`'s init signature differs, mirror exactly what's used in the existing `apply`-related tests in this file — do not invent a new shape. Grep first: `grep -n "ReviewLogEntry(" Packages/AnghkooeyCore/Tests`.)

- [ ] **Step 2: Run the failing test**

```bash
cd Packages/AnghkooeyCore && swift test --filter CardStoreTests/applyPersistsStepMachineFields 2>&1 | tail -20
```
Expected: FAIL — `persisted.reps == 1` will be `0` because `apply` doesn't write the new fields yet.

- [ ] **Step 3: Update `CardStore.apply` to write the five fields**

In `CardStore.swift`, in the `apply(_:to:grade:now:)` actor method, between the existing `card.lastReviewedAt = now` and `card.updatedAt = now` lines, insert:

```swift
card.reps = output.card.reps
card.lapses = output.card.lapses
card.learningSteps = output.card.learningSteps
card.scheduledDays = output.card.scheduledDays
card.elapsedDays = output.card.elapsedDays
```

- [ ] **Step 4: Mirror the change in `MockCardStore.apply`**

In `MockCardStore.apply`, the snapshot rebuild block needs the new fields too. Replace the existing `cards[idx] = Card.Snapshot(...)` call with:

```swift
cards[idx] = Card.Snapshot(
    id: old.id,
    question: old.question,
    answer: old.answer,
    sourceSpan: old.sourceSpan,
    state: output.card.state,
    stability: output.card.stability,
    difficulty: output.card.difficulty,
    dueAt: output.card.due,
    lastReviewedAt: now,
    reps: output.card.reps,
    lapses: output.card.lapses,
    learningSteps: output.card.learningSteps,
    scheduledDays: output.card.scheduledDays,
    elapsedDays: output.card.elapsedDays
)
```

- [ ] **Step 5: Re-run the test, expect PASS**

```bash
cd Packages/AnghkooeyCore && swift test --filter CardStoreTests/applyPersistsStepMachineFields 2>&1 | tail -20
```
Expected: PASS.

- [ ] **Step 6: Run the full Core suite**

```bash
cd Packages/AnghkooeyCore && swift test 2>&1 | tail -30
```
Expected: every test passes, including the existing CardStoreTests, SchedulingContractTests, FSRSAlgorithmTests, and SchemaMigrationTests from Task 5.

- [ ] **Step 7: Commit**

```bash
git add Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardStore.swift Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/CardStoreTests.swift
git commit -m "feat(m5.a): CardStore.apply persists reps/lapses/learningSteps/scheduledDays/elapsedDays"
```

---

## Task 8: End-to-end multi-review assertion

Confirm that across several `apply` calls the step-machine fields evolve monotonically — proving the round-trip works under realistic use, not just a single hand-crafted output.

**Files:**
- Modify: `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/Integration/EndToEndReviewFlowTests.swift`

- [ ] **Step 1: Skim the existing file to find the right insertion point**

```bash
sed -n '1,40p' Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/Integration/EndToEndReviewFlowTests.swift
```
Look for the longest existing scenario (multi-review loop driving the real `LiveFSRS6Engine`). Add the new assertion inside that scenario after the final `apply` call.

- [ ] **Step 2: After the existing final fetch, add**

```swift
// M5.A: step-machine state must be persisted, not zero-defaulted.
let finalDue = try await store.dueCards(asOf: .distantFuture)
let finalCard = try #require(finalDue.first(where: { $0.id == created.id }))
#expect(finalCard.reps >= 1, "reps should increment across reviews")
```

(If the variable holding the created card's id is named differently in the existing test, use that name.)

- [ ] **Step 3: Run the integration suite**

```bash
cd Packages/AnghkooeyCore && swift test --filter EndToEndReviewFlowTests 2>&1 | tail -20
```
Expected: PASS. If `reps` is 0 here, `LiveFSRS6Engine` isn't incrementing the field — file a separate bug and pin reps to whatever the engine actually returns; do not silently change the assertion.

- [ ] **Step 4: Commit**

```bash
git add Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/Integration/EndToEndReviewFlowTests.swift
git commit -m "test(m5.a): integration test asserts step-machine reps persist across reviews"
```

---

## Task 9: App-target smoke test

The app target uses `AnghkooeyModelContainer.makeInMemoryContainer()` through `AppState`. Confirm it still builds and the existing app-target tests pass under V2.

**Files:** none (verification only).

- [ ] **Step 1: Regenerate the Xcode project if `make generate` is the workflow**

```bash
ls -la Anghkooey.xcodeproj 2>/dev/null || ls -la Makefile project.yml 2>/dev/null
```
If `project.yml` is present and there's a `make generate` target, run it. Then re-apply the `PrivacyInfo.xcprivacy` patches per `feedback_xcodegen_xcprivacy_extensions.md` (4 entries).

- [ ] **Step 2: Run the app-target tests via xcodebuild**

```bash
xcodebuild test \
  -scheme Anghkooey \
  -destination 'platform=iOS Simulator,id=6DF96BFC-D26F-4995-8149-1A5F3C893492' \
  -only-testing:AnghkooeyTests \
  -derivedDataPath .ci-derived-data \
  2>&1 | tail -40
```
Expected: PASS. The simulator id is the iOS 26 "iPhone 17 Pro" per `feedback_ios26_sim_name.md`. If the destination is missing, run `xcrun simctl list devices available` and substitute the current iPhone 17 Pro id.

- [ ] **Step 3: If anything broke, fix in place**

The most likely cause of breakage is a Snapshot call site that named arguments positionally and now mis-binds. Fix by adding explicit argument labels.

- [ ] **Step 4: Commit any project-file regeneration churn separately**

```bash
git status
# If only project.pbxproj / project.yml changed:
git add Anghkooey.xcodeproj project.yml
git commit -m "chore(m5.a): regenerate Xcode project after schema completion"
```

---

## Task 10: Documentation + memory

**Files:**
- Modify: `ARCHITECTURE.md`
- Create/append: `~/.claude/projects/-Users-mitsheth-Documents-rewind/memory/feedback_swiftdata_versioned_namespacing.md`

- [ ] **Step 1: Append M5.A subsection to `ARCHITECTURE.md`**

Add (under the existing §M5 heading, or create §M5 if absent):

```markdown
### M5.A — Schema V2 (step-machine persistence)

Introduced `AnghkooeySchemaV2.Card` adding `reps`, `lapses`, `learningSteps`,
`scheduledDays`, `elapsedDays` with safe defaults. Migration from V1 is
`MigrationStage.lightweight` — no copy logic. Downstream code references
the top-level `Card` typealias bound to `AnghkooeySchemaV2.Card`; future
migrations swap the alias and add a stage without rippling through call
sites. `Card.Snapshot.schedulingCard` no longer zero-fills step-machine
state, closing the M4 carry-over noted in §M4.
```

- [ ] **Step 2: Write a one-shot memory entry for the namespacing pattern**

Create `~/.claude/projects/-Users-mitsheth-Documents-rewind/memory/feedback_swiftdata_versioned_namespacing.md`:

```markdown
---
name: feedback-swiftdata-versioned-namespacing
description: SwiftData VersionedSchema model layout pattern used in Anghkooey — nest @Model classes inside the schema enum namespace, expose top-level typealias to the current version
metadata:
  type: feedback
---

For SwiftData schema versioning, nest each `@Model` class inside its
`VersionedSchema` enum (e.g. `AnghkooeySchemaV2.Card`) rather than at
top-level. Expose a `public typealias Card = AnghkooeySchemaV2.Card` so
downstream code never references the version directly.

**Why:** SwiftData requires distinct types per schema version. A
top-level `Card` would force every migration to rename the class
everywhere it's used. The typealias absorbs version churn.

**How to apply:** When adding a new schema version, create
`AnghkooeySchemaVN.swift`, add a `MigrationStage` (lightweight when all
new columns have defaults), and update the top-level alias to point at
the latest version. Update `AnghkooeyModelContainer.makeInMemoryContainer`
to build the schema from the latest `VersionedSchema`. See M5.A commits
on `m5/polish` for the worked example.
```

Then add a line to `MEMORY.md` index:

```markdown
- [SwiftData versioned schema namespacing](feedback_swiftdata_versioned_namespacing.md) — nest @Model in enum, expose top-level typealias to current version
```

- [ ] **Step 3: Commit docs + memory**

```bash
git add ARCHITECTURE.md
git commit -m "docs(m5.a): ARCHITECTURE.md notes V2 schema + step-machine persistence"
```

(Memory file lives outside the repo; no git commit needed.)

---

## Task 11: Ready for review

- [ ] **Step 1: Verify branch state**

```bash
git log --oneline main..HEAD
```
Expected: roughly 7 commits — start marker, V2 schema, migration test, snapshot extension, apply persistence, integration test, docs.

- [ ] **Step 2: Run the full test matrix one more time**

```bash
cd Packages/AnghkooeyCore && swift test 2>&1 | tail -10
cd ../AnghkooeyIntelligence && swift test 2>&1 | tail -10
cd ../AnghkooeyUI && swift test 2>&1 | tail -10
cd ../..
xcodebuild test -scheme Anghkooey -destination 'platform=iOS Simulator,id=6DF96BFC-D26F-4995-8149-1A5F3C893492' -only-testing:AnghkooeyTests -derivedDataPath .ci-derived-data 2>&1 | tail -10
```
Expected: all green.

- [ ] **Step 3: Push and open PR**

```bash
git push -u origin m5/polish
gh pr create --title "M5.A: SwiftData V2 schema — step-machine persistence" \
  --body "$(cat <<'EOF'
## Summary
- Introduces `AnghkooeySchemaV2.Card` with five step-machine columns (`reps`, `lapses`, `learningSteps`, `scheduledDays`, `elapsedDays`), all defaulted.
- V1 → V2 lightweight migration; first non-trivial SwiftData migration in the project.
- `Card.Snapshot.schedulingCard` no longer zero-fills step-machine fields — closes M4 carry-over.
- `CardStore.apply` and `MockCardStore.apply` persist the new fields from `SchedulerOutput`.

## Test plan
- [ ] `swift test` green in all three packages
- [ ] `xcodebuild test -only-testing:AnghkooeyTests` green on iPhone 17 Pro simulator
- [ ] New `SchemaMigrationTests` proves V1 store opens as V2 with zero-filled new columns
- [ ] `EndToEndReviewFlowTests` asserts `reps >= 1` after multi-review run

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: Update `project_m5_in_progress.md` memory**

Record `m5/polish` branch + PR url so the next session has the handoff. (Use the project_m4_complete.md memory as a template — same shape.)

---

## Risk notes

- **Lightweight migration silently failing into recreate.** If SwiftData decides the migration isn't actually lightweight (e.g. a default isn't recognized), it may drop the store. Task 5's migration test catches this by checking `cards.count == 1` after reopen — if it ever reads 0, the migration isn't lightweight and we need an explicit `.custom` stage with copy logic. Don't skip Task 5.
- **CloudKit interaction.** V2 schema must remain CloudKit-compatible if/when sync turns on. All added properties are scalar with defaults, which CloudKit private DB accepts without schema migration on its side. No action needed in M5.A but worth noting for Lane future.
- **Reps semantics divergence.** `LiveFSRS6Engine` is the authority for what `reps`/`lapses` increment to. Task 8 asserts `>= 1`, not a specific number — if the engine's bookkeeping changes, this test stays valid.
