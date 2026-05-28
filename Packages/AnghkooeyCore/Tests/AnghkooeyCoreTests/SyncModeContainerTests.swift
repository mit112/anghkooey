import Testing
import Foundation
import SwiftData
@testable import AnghkooeyCore

@Suite("Sync-mode container factory")
struct SyncModeContainerTests {

    @Test("local sync mode builds an on-disk container at a custom URL")
    func localContainerBuilds() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let container = try AnghkooeyModelContainer.makeContainer(syncMode: .local, url: url)
        let context = ModelContext(container)
        let card = Card(question: "q", answer: "a")
        context.insert(card)
        #expect((try? context.save()) != nil)
    }

    @Test("the V3 schema version is correct")
    func schemaVersionCorrect() {
        #expect(AnghkooeySchemaV3.versionIdentifier == Schema.Version(3, 0, 0))
    }
}
