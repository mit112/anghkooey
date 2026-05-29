import Testing
import SwiftData
@testable import AnghkooeyCore

@Suite("Schema V4 migration")
struct SchemaMigrationV4Tests {

    @Test func migrationPlanHasFourSchemasAndThreeStages() {
        // V5 has been added; this test now reflects the full plan shape.
        #expect(AnghkooeyMigrationPlan.schemas.count == 5)
        #expect(AnghkooeyMigrationPlan.stages.count == 4)
    }

    @Test func v4ContainerInitializesClean() throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let ctx = ModelContext(container)
        let cards = try ctx.fetch(FetchDescriptor<Card>())
        #expect(cards.isEmpty)
    }
}
