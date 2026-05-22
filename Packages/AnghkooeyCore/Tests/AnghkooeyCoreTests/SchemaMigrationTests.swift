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
        #expect(AnghkooeyMigrationPlan.schemas.count == 3)
        #expect(AnghkooeyMigrationPlan.stages.count == 2)
    }

    @Test func v3ContainerWithMigrationPlanInitializesClean() throws {
        let v3Schema = Schema(versionedSchema: AnghkooeySchemaV3.self)
        let config = ModelConfiguration(schema: v3Schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: v3Schema,
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
