import Testing
import Foundation
@testable import AnghkooeyCore

private class FixtureLoader {}

@Suite("AnkiImporter")
struct AnkiImporterTests {

    private var sampleApkgURL: URL {
        Bundle(for: FixtureLoader.self).url(forResource: "sample", withExtension: "apkg")!
    }

    // MARK: Scan phase

    @Test func scan_sampleApkg_returnsCorrectCounts() async throws {
        let store = MockCardStore()
        let importer = LiveAnkiImporter(store: store)
        let result = try await importer.scanPackage(at: sampleApkgURL)
        // sample.apkg: 3 Basic (2 Default + 1 Anatomy) + 1 Cloze = 4 total, 1 skippable
        #expect(result.totalNotes == 4)
        #expect(result.skippableNotes == 1)
    }

    // MARK: Import phase — full pipeline

    @Test func import_basicNotes_areCreatedInStore() async throws {
        let store = MockCardStore()
        let importer = LiveAnkiImporter(store: store)
        var result: AnkiImportResult?
        for try await event in importer.importPackage(at: sampleApkgURL, now: .now, maxCards: 5_000) {
            if case .completed(let r) = event { result = r }
        }
        let r = try #require(result)
        #expect(r.imported == 3)   // 3 Basic notes
        #expect(r.skipped == 1)    // 1 Cloze
        #expect(r.duplicates == 0)
        #expect(r.truncated == false)
        #expect(store.cards.count == 3)
    }

    @Test func import_progressEventsAreOrdered() async throws {
        let store = MockCardStore()
        let importer = LiveAnkiImporter(store: store)
        var importedCounts: [Int] = []
        for try await event in importer.importPackage(at: sampleApkgURL, now: .now, maxCards: 5_000) {
            if case .importing(let imported, _) = event { importedCounts.append(imported) }
        }
        #expect(importedCounts == importedCounts.sorted())
    }

    @Test func import_duplicate_skipsOnReimport() async throws {
        let store = MockCardStore()
        let importer = LiveAnkiImporter(store: store)
        // First import
        for try await _ in importer.importPackage(at: sampleApkgURL, now: .now, maxCards: 5_000) {}
        // Second import
        var result: AnkiImportResult?
        for try await event in importer.importPackage(at: sampleApkgURL, now: .now, maxCards: 5_000) {
            if case .completed(let r) = event { result = r }
        }
        let r = try #require(result)
        #expect(r.duplicates == 3)
        #expect(r.imported == 0)
        #expect(store.cards.count == 3)   // unchanged
    }

    @Test func import_storeFailure_streamThrows() async throws {
        let store = MockCardStore()
        store.createError = PersistenceError.containerCreationFailed(underlying: NSError(domain: "test", code: 1))
        let importer = LiveAnkiImporter(store: store)
        var threw = false
        do {
            for try await _ in importer.importPackage(at: sampleApkgURL, now: .now, maxCards: 5_000) {}
        } catch {
            threw = true
        }
        #expect(threw)
    }

    @Test func import_reviewCard_preservesDueDate() async throws {
        let store = MockCardStore()
        let importer = LiveAnkiImporter(store: store)
        for try await _ in importer.importPackage(at: sampleApkgURL, now: .now, maxCards: 5_000) {}
        // note 1001: type=2, due=100, crt=1700000000 → expected 1700000000 + 100*86400
        let expectedDue = Date(timeIntervalSince1970: 1_700_000_000 + 100 * 86_400)
        let card = store.cards.first { $0.sourceSpan == "anki:1001:0" }
        #expect(card?.dueAt == expectedDue)
    }

    @Test func import_corruptedZip_streamThrows() async throws {
        let badURL = FileManager.default.temporaryDirectory.appendingPathComponent("bad.apkg")
        try "not a zip".write(to: badURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: badURL) }
        let importer = LiveAnkiImporter(store: MockCardStore())
        var threw = false
        do {
            for try await _ in importer.importPackage(at: badURL, now: .now, maxCards: 5_000) {}
        } catch { threw = true }
        #expect(threw)
    }

    // MARK: MockAnkiImporter

    @Test func mockImporter_returnsConfiguredEvents() async throws {
        let mock = MockAnkiImporter()
        mock.importEvents = [
            .importing(imported: 1, total: 3),
            .completed(AnkiImportResult(imported: 3, skipped: 0, duplicates: 0, truncated: false))
        ]
        var events: [AnkiImportProgress] = []
        for try await event in mock.importPackage(at: URL(fileURLWithPath: "/dev/null"), now: .now, maxCards: 5_000) {
            events.append(event)
        }
        #expect(events.count == 2)
    }
}
