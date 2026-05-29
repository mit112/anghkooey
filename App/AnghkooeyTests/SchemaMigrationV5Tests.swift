import Testing
import SwiftData
import Foundation
@testable import AnghkooeyCore

@Suite struct SchemaMigrationV5Tests {
    @Test func migrationPlanHasFiveSchemasAndFourStages() {
        #expect(AnghkooeyMigrationPlan.schemas.count == 5)
        #expect(AnghkooeyMigrationPlan.stages.count == 4)
    }

    @Test func v4RowsGainNilClozeFieldsUnderV5() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mig-v5-\(UUID()).store")
        defer { try? FileManager.default.removeItem(at: url) }

        // Seed a V4 store with one Q&A card.
        do {
            let v4Schema = Schema(versionedSchema: AnghkooeySchemaV4.self)
            let cfg = ModelConfiguration(schema: v4Schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: v4Schema, configurations: [cfg])
            let ctx = ModelContext(container)
            ctx.insert(AnghkooeySchemaV4.Card(question: "Q", answer: "A"))
            try ctx.save()
        }

        // Reopen under V5 — SwiftData auto-applies the lightweight migration.
        // We intentionally omit the staged migration plan here: unversioned
        // relationship types (Tag, ReviewLog) appear in every schema's entity
        // graph transitively, so NSStagedMigrationManager sees "duplicate
        // checksums" when it tries to resolve the current version. All our
        // stages are .lightweight(), so SwiftData migrates automatically
        // without the plan.
        let v5Schema = Schema(versionedSchema: AnghkooeySchemaV5.self)
        let cfg = ModelConfiguration(schema: v5Schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: v5Schema, configurations: [cfg])
        let ctx = ModelContext(container)
        let cards = try ctx.fetch(FetchDescriptor<AnghkooeySchemaV5.Card>())
        #expect(cards.count == 1)
        #expect(cards.first?.cardType == nil)
        #expect(cards.first?.clozeGroupID == nil)
        #expect(cards.first?.clozeBuriedUntil == nil)
    }
}
