# Anghkooey M1 — AnghkooeyCore: Schema + FSRS-6 Engine

> Detailed M1 plan. Source-of-truth links: `foundation.md` §4 (scope), implementation plan §2 (arch), §4.1 (parity), §5 M1 (gates).

## Entry Gate Status

- [x] M0 tagged `m0-complete` on `main` (commit `6842c90`)

## M1 Exit Gate (verbatim from strategic plan §5 M1)

- `Card`, `ReviewLog`, `Tag` SwiftData models with v1 migration
- `FSRS6Engine` ported from pinned reference commit
- Parity harness runs on every PR; passes 100% of fixtures
- In-memory `ModelContainer` test container utility for downstream packages
- All public APIs documented with DocC
- `Logger(category: "FSRS")` and `Logger(category: "Persistence")` in place
  - **Reconciliation note:** §2.4 arch and existing `CoreLog.swift` use `Scheduling`, not `FSRS`. We keep `Scheduling` (already wired as `CoreLog.scheduling`) and treat the gate text as a naming drift.

## Cut-line

If parity passes for the 21-parameter default weights but custom-parameter optimization is incomplete, ship without it. (Personal optimization is v2 per `foundation.md §4`.)

## Schema sketch (locked field sets for v1)

**Card** (`@Model final class`)
- `id: UUID` — `@Attribute(.unique)`
- `question: String`
- `answer: String`
- `createdAt: Date`
- `updatedAt: Date`
- `tags: [Tag]` — many-to-many, inverse on Tag
- `state: CardState` — Int raw
- `stability: Double` (FSRS)
- `difficulty: Double` (FSRS)
- `dueAt: Date`
- `lastReviewedAt: Date?`
- `reviewLogs: [ReviewLog]` — one-to-many, cascade delete
- `sourceSpan: String?` — excerpt the card was generated from; not v1-rendered

**ReviewLog** (`@Model final class`)
- `id: UUID` — `@Attribute(.unique)`
- `card: Card?` — inverse of `Card.reviewLogs`
- `reviewedAt: Date`
- `rating: Rating` — Int raw
- `stateBefore: CardState` — Int raw
- `stabilityBefore: Double`
- `difficultyBefore: Double`
- `elapsedDays: Double`
- `scheduledDays: Double`

**Tag** (`@Model final class`)
- `id: UUID` — `@Attribute(.unique)`
- `name: String` — unique, case-insensitive normalized
- `createdAt: Date`
- `cards: [Card]` — inverse

No `Collection` in v1.

## Task breakdown

Sequenced; arrows mark hard dependencies. Owner: **C = Codex (Sonnet via /codex:rescue)**, **K = Claude (Opus, this session)**.

| # | Task | Owner | Depends on | Notes |
|---|---|---|---|---|
| T1 | SwiftData models (`Card`, `ReviewLog`, `Tag`) + `VersionedSchema` v1 + in-memory `ModelContainer` test utility + persistence error type | C | — | Pure scaffolding. Spec in this file. No FSRS knowledge required. |
| T2 | Pin FSRS reference commit, define parity-fixture format, generate ground-truth fixtures | K | — | Decision + research. Produces ADR-0002 and `Fixtures/fsrs6-parity.json`. Must precede T4/T5. |
| T3 | FSRS-6 type skeleton — `Rating`, `CardState` (already in T1), `SchedulingCard`, `SchedulerOutput`, `FSRSParameters` (21-weight default constants from pinned reference), `FSRS6Engine` protocol + `LiveFSRS6Engine` stub | C | T2 (constants come from reference) | Mechanical. Methods throw `fatalError("unimplemented")` until T4. |
| T4 | FSRS-6 math port — stability, difficulty, retrievability, next-interval — implementing `LiveFSRS6Engine` | K | T3 | Math correctness. Claude/Opus only per AGENTS.md §FSRS math exception. |
| T5 | Parity harness — fixture loader, engine runner, epsilon comparator, Swift Testing wrapper, CI wiring | C | T2, T4 | Compares Swift output to fixture ground truth within ε=1e-9 for doubles, exact for integer intervals. Fails build on divergence. |
| T6 | DocC pass on all public APIs of `AnghkooeyCore`, `ARCHITECTURE.md` M1 update | C | T1–T5 | Touches doc comments + one Markdown file. |

## Handoff Ledger

- **Current owner:** Claude — T4 complete; T5 (parity harness) opens next, Codex-suitable.
- **Current branch:** `m1/swiftdata-models` (6 commits ahead of `main`)
- **Last good commit:** T4 (FSRS-6 math port — `LiveFSRS6Engine.next`)
- **Active task:** — (T4 closed; T5 next)
- **Completed:**
  - T1 — SwiftData models green on macOS host + iOS 26 Simulator (Codex-verified, commit `97e5bef`).
  - T2 — Pinned `ts-fsrs v5.4.0` (SHA `80bab011a7f496b06c99924d54e772cf258244f2`) as the FSRS-6 reference. ADR-0002. 150 fixtures at `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/Fixtures/fsrs6-parity.json`. Commit `7964a1b`.
  - T3 contract (Claude) — `Scheduling/FSRSParameters.swift`, `SchedulingCard.swift`, `SchedulerOutput.swift`, `FSRS6Engine.swift`, `MockFSRS6Engine.swift` (stub), `Tests/SchedulingContractTests.swift` (18 cases), `scripts/m1-forbidden-patterns.sh` extension. Commit `e556200`.
  - T3 fill (Codex authored body, Claude verified on simulator due to Codex sandbox blocking `swift build`) — `MockFSRS6Engine.next` implements the doc-comment contract exactly. Commit `4545247`.
  - T4 (Claude/Opus) — Ported FSRS-6 algorithm and BasicScheduler dispatch into `LiveFSRS6Engine`. New file `Scheduling/LiveFSRS6Engine.swift` exposes `@usableFromInline` math primitives (`forgettingCurve`, `initStability`/`initDifficulty`, `linearDamping`, `meanReversion`, `nextDifficulty`, `nextRecallStability`, `nextForgetStability`, `nextShortTermStability`, `nextInterval`, `nextMemoryState`) plus the public `next(card:rating:now:)`. UTC-calendar-day `elapsed` computed by the engine; basic learning-step strategy ported verbatim; review-state triple applies the hard ≤ good < easy monotonicity from `BasicScheduler.next_interval`. New file `Tests/FSRSAlgorithmTests.swift` (`@testable`) with 24 cases: primitive math (derived constants, forgetting curve, init S/D, mean reversion, recall/forget/short-term stability, interval clamp, seed path) + end-to-end fixture matches (first-rating-{again,hard,good,easy}, graduate-good-good through step 2 stability/difficulty, review→Again lapse, error paths).
- **Verification run (T4, Claude):** `bash scripts/m1-forbidden-patterns.sh` → `M1 forbidden-pattern check: OK`. `xcodebuild test -scheme AnghkooeyCore -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0'` → `** TEST SUCCEEDED **`, 47/47 tests passed in 7 suites. xcresult at `/tmp/anghkooey-m1t4.xcresult`.
- **Known caveats:** Long-term scheduler (`enableShortTerm == false`) is not specialised — the basic dispatch is used regardless. FSRS-6 default parameters have short-term enabled (ADR-0002) so parity is unaffected; a dedicated long-term path can land later without API change.
- **Next step:** T5 — Parity harness. Codex-suitable. Fixture loader + Swift Testing wrapper that drives `LiveFSRS6Engine` step-by-step over all 150 fixtures and compares against `expected` with ε per ADR-0002. Use `@testable import AnghkooeyCore` and `LiveFSRS6Engine.dateDiffInUTCDays` if needed; the engine already accepts wall-clock `now`, so the harness only needs to materialise per-step `Date`s from `absolute_seconds_from_epoch`.
- **Review needed from:** — (T4 review complete; Claude authored and verified.)

---

## T1 — Contract-first split (post-misfire revision, 2026-05-20)

After two Codex rejections (see Handoff Ledger), T1 was restructured per AGENTS.md → "Contract-first task shape":

**Claude wrote the contract (committed by Claude):**
- `Persistence/Card.swift`, `ReviewLog.swift`, `Tag.swift`
- `Persistence/CardState.swift`, `Rating.swift`, `PersistenceError.swift`
- `Persistence/AnghkooeySchemaV1.swift` (`VersionedSchema` + `AnghkooeyMigrationPlan`)
- `Persistence/AnghkooeyModelContainer.swift` (`makeInMemoryContainer()`)
- `Tests/AnghkooeyCoreTests/PersistenceTests.swift` (7 named tests)
- `scripts/m1-forbidden-patterns.sh` (tripwire — bans `Deck`, `front`/`back`, `easeFactor`, hard-coded `Logger(subsystem:)`, etc.)

**Codex's residual T1 task (narrow):**
- Run `xcodebuild test` for `AnghkooeyCore` on an iOS 26 Simulator (the existing `swift test` green doesn't catch SwiftData-on-iOS-only behavior).
- Run `scripts/m1-forbidden-patterns.sh` and confirm exit 0.
- If both green, commit on `m1/swiftdata-models` using the template message.
- Do NOT edit any source file. If the simulator run fails, report and stop — Claude fixes.

## T1 Original Task Card (kept for history)

**Scope:** Add SwiftData models `Card`, `ReviewLog`, `Tag` to `AnghkooeyCore` plus an in-memory `ModelContainer` test utility and `VersionedSchema` scaffolding.

**Files Codex may create:**
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/Card.swift`
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/ReviewLog.swift`
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/Tag.swift`
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/CardState.swift` — enum `.new`/`.learning`/`.review`/`.relearning`; Int raw 0..3; `Codable`, `Sendable`
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/Rating.swift` — enum `.again`/`.hard`/`.good`/`.easy`; Int raw 1..4 (FSRS spec); `Codable`, `Sendable`
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeySchemaV1.swift` — `enum AnghkooeySchemaV1: VersionedSchema` + `enum AnghkooeyMigrationPlan: SchemaMigrationPlan` (empty `stages`)
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/AnghkooeyModelContainer.swift` — `public enum AnghkooeyModelContainer { static func makeInMemoryContainer() throws -> ModelContainer }`
- `Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/PersistenceError.swift` — `enum PersistenceError: Error, LocalizedError { case schemaInitFailed(underlying: Error); case containerCreationFailed(underlying: Error) }`
- `Packages/AnghkooeyCore/Tests/AnghkooeyCoreTests/PersistenceTests.swift`

**Files Codex must NOT edit:**
- `Packages/AnghkooeyCore/Package.swift` (no new deps — SwiftData ships in the SDK)
- Anything outside `Packages/AnghkooeyCore/`
- `docs/superpowers/plans/2026-05-20-rewind-m1-core.md` (the Handoff Ledger is Claude's to write)

**Tests Codex must write first (Swift Testing — `@Test`, `#expect`, `#require`):**
1. `inMemoryContainer_initializesWithoutThrowing`
2. `inMemoryContainer_canInsertAndFetchCard` — insert a `Card`, fetch by `id`, assert equality
3. `card_tagRelationship_isInverseLinked` — attach a `Tag`, save, refetch and assert reverse link populated
4. `card_reviewLogCascadeDelete` — insert card with one log, delete card, assert log count is 0
5. `tag_uniqueByName_caseInsensitive` — inserting `Tag(name: "swift")` and `Tag(name: "Swift")` must collapse to one (acceptable to enforce via a normalized-name attribute; if `@Attribute(.unique)` can't enforce case-insensitive uniqueness alone, document the approach in a code comment and prove the chosen behavior with the test)
6. `rating_rawValue_matchesFSRSSpec` — `.again`=1, `.hard`=2, `.good`=3, `.easy`=4
7. `cardState_rawValue_isStable` — `.new`=0, `.learning`=1, `.review`=2, `.relearning`=3 (pin raws so migrations can detect drift)

**Schema requirements (match exactly):**
- All three models `@Model final class`.
- `id: UUID` with `@Attribute(.unique)`.
- Relationships:
  - `Card.tags` ↔ `Tag.cards` — many-to-many, `@Relationship(inverse:)` on the Tag side.
  - `Card.reviewLogs` ↔ `ReviewLog.card` — one-to-many, `deleteRule: .cascade` on the Card side.
- `state`, `rating`, `stateBefore` are stored as raw `Int` via the enum's `rawValue`. If SwiftData's native enum storage works under Swift 6 strict concurrency on iOS 26, use it; otherwise store as `Int` with a computed convenience.
- `@Model` classes are not `Sendable` — do not force it. Other public value types should be.

**Schema versioning (day-one scaffolding even though v1 has no prior version):**
```swift
public enum AnghkooeySchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] { [Card.self, ReviewLog.self, Tag.self] }
}

public enum AnghkooeyMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [AnghkooeySchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
```
`AnghkooeyModelContainer.makeInMemoryContainer()` constructs the container with `AnghkooeySchemaV1.self` + `AnghkooeyMigrationPlan.self` + `ModelConfiguration(isStoredInMemoryOnly: true)`.

**Logging:** wire `CoreLog.persistence`:
- On success: `CoreLog.persistence.debug("In-memory ModelContainer created (v1 schema)")`
- On failure: `CoreLog.persistence.error("ModelContainer init failed: \(error.localizedDescription, privacy: .public)")`

**DocC:** every public type, property, and method has a `///` doc comment with at least a one-sentence summary.

**Verification command (Codex runs and pastes exit code + tail of log):**
```
xcodebuild test \
  -scheme AnghkooeyCore \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' \
  -resultBundlePath /tmp/anghkooey-m1t1.xcresult \
  | tee /tmp/anghkooey-m1t1.log
```
If `iPhone 17 Pro` isn't available, pick the highest available iOS 26 simulator and note the substitution in the handoff.

All 7 new tests + the existing M0 smoke tests must pass.

**Commit message (Codex composes from this template):**
```
feat(core): SwiftData v1 schema — Card, ReviewLog, Tag + in-memory container

Adds the v1 persistence layer for AnghkooeyCore:
- @Model classes Card, ReviewLog, Tag with cascade delete and inverse
  relationships per docs/superpowers/plans/2026-05-20-rewind-m1-core.md
- CardState / Rating enums with pinned Int raws (FSRS spec for Rating)
- VersionedSchema scaffolding (AnghkooeySchemaV1) with empty migration plan
- AnghkooeyModelContainer.makeInMemoryContainer() for downstream tests
- 7 Swift Testing cases covering insertion, relationships, cascade,
  tag uniqueness, and raw-value pinning

Refs M1 exit gate (schema + in-memory test container).
```

**Review checklist (Claude after Codex returns):**
- [ ] Field set matches the schema sketch exactly — no drift, no extras
- [ ] No `import SwiftUI` / `import UIKit` / `import FoundationModels` / `import Vision` anywhere in `AnghkooeyCore`
- [ ] All `@Model` classes are `final`
- [ ] Cascade delete actually fires in the test (not just declared)
- [ ] Tag uniqueness implementation is honest — if `@Attribute(.unique)` can't enforce case-insensitive uniqueness, the code documents how it's enforced
- [ ] No `print`, no GCD, no completion handlers
- [ ] DocC comments present on every public symbol
- [ ] Verification command output present; non-zero failures = blocker
- [ ] Handoff Ledger updated with completion + verification evidence

---

## Reference

- Strategic plan: `docs/superpowers/plans/2026-05-20-rewind-implementation-plan.md` §5 M1
- Foundation: `foundation.md` §4 (in-scope), §9 (quality bar item 3 = parity)
- Cross-cutting: implementation plan §4.1 (parity harness spec — owned here)
- Collaboration model: `AGENTS.md` §Claude / Codex Collaboration Model
