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
