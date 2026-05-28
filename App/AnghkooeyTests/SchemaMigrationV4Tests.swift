import Testing
import SwiftData
@testable import AnghkooeyCore

@Suite("Schema V4 migration")
struct SchemaMigrationV4Tests {

    @Test func migrationPlanHasFourSchemasAndThreeStages() {
        #expect(AnghkooeyMigrationPlan.schemas.count == 4)
        #expect(AnghkooeyMigrationPlan.stages.count == 3)
    }

    @Test func v4ContainerInitializesClean() throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let ctx = ModelContext(container)
        let cards = try ctx.fetch(FetchDescriptor<Card>())
        #expect(cards.isEmpty)
    }
}
