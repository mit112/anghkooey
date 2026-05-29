import Foundation
import SwiftData
import Testing
@testable import AnghkooeyCore

@Suite("Schema migration V1 → V2")
struct SchemaMigrationTests {

    /// V1 → V2 lightweight migration: opening a V2 container (in-memory) with the
    /// migration plan succeeds and new cards have nil step-machine fields in the
    /// backing store (read back through the model directly).
    ///
    /// Note: exercising the actual V1-file → V2 migration (write V1 rows on disk,
    /// reopen with V2 schema) cannot be done within the same process when both
    /// AnghkooeySchemaV1.Card and AnghkooeySchemaV2.Card are @Model types in the
    /// same module — SwiftData stores the full Swift type name in PersistentIdentifiers
    /// and fails to cast after a lightweight migration. The migration plan is verified
    /// structurally here; the on-device path is tested by the app-target smoke test.
    @Test func migrationPlanStructureIsCorrect() {
        // V1→V2 (LTM), V2→V3 (mnemonic), V3→V4 (Anki import), V4→V5 (cloze).
        #expect(AnghkooeyMigrationPlan.schemas.count == 5)
        #expect(AnghkooeyMigrationPlan.stages.count == 4)
    }

    @Test func currentSchemaContainerWithMigrationPlanInitializesClean() throws {
        // Open at the CURRENT schema (V5) so the `Card` typealias (= V5.Card)
        // fetch is type-consistent. Declaring an older schema version here while
        // fetching V5.Card crashes SwiftData's PersistentIdentifier registry
        // when this test is co-resident with other V5 tests in the same process
        // (see feedback_swiftdata_versioned_namespacing).
        let schema = Schema(versionedSchema: AnghkooeySchemaV5.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AnghkooeyMigrationPlan.self,
            configurations: [config]
        )
        let ctx = ModelContext(container)
        let cards = try ctx.fetch(FetchDescriptor<Card>())
        #expect(cards.isEmpty)
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
