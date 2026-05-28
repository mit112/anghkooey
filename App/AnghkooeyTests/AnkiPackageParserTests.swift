import Testing
import Foundation
@testable import AnghkooeyCore

private class FixtureLoader {}

@Suite("AnkiPackageParser")
struct AnkiPackageParserTests {

    private var sampleApkgURL: URL {
        Bundle(for: FixtureLoader.self).url(forResource: "sample", withExtension: "apkg")!
    }

    @Test func parse_sampleApkg_returnsFourNotes() throws {
        let collection = try AnkiPackageParser.parse(apkgURL: sampleApkgURL)
        // 2 Basic (Default) + 1 Cloze + 1 Basic (Anatomy) = 4 notes in JOIN
        #expect(collection.notes.count == 4)
    }

    @Test func parse_sampleApkg_collectionEpochIsCorrect() throws {
        let collection = try AnkiPackageParser.parse(apkgURL: sampleApkgURL)
        #expect(Int(collection.createdAt.timeIntervalSince1970) == 1_700_000_000)
    }

    @Test func parse_sampleApkg_modelMapContainsBasicAndCloze() throws {
        let collection = try AnkiPackageParser.parse(apkgURL: sampleApkgURL)
        let basic = collection.models[1_000_000_001]
        let cloze = collection.models[1_000_000_002]
        #expect(basic?.type == 0)
        #expect(cloze?.type == 1)
    }

    @Test func parse_sampleApkg_deckNamesMappedCorrectly() throws {
        let collection = try AnkiPackageParser.parse(apkgURL: sampleApkgURL)
        #expect(collection.deckNames[1] == "Default")
        #expect(collection.deckNames[2] == "Medical::Anatomy")
    }

    @Test func parse_notAnApkgFile_throws() throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notafile.apkg")
        try "not a zip".write(to: tmpURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        #expect(throws: AnkiImportError.corruptedArchive) {
            try AnkiPackageParser.parse(apkgURL: tmpURL)
        }
    }
}
