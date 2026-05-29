import Testing
import Foundation
@testable import AnghkooeyCore

@Suite("AnkiNoteMapper")
struct AnkiNoteMapperTests {

    let basicModel = AnkiModel(id: 1, type: 0, fieldNames: ["Front", "Back"])
    let clozeModel = AnkiModel(id: 2, type: 1, fieldNames: ["Text"])
    let noFBModel  = AnkiModel(id: 3, type: 0, fieldNames: ["Expression", "Reading"])
    let collectionEpoch = Date(timeIntervalSince1970: 1_700_000_000)
    let importedAt = Date(timeIntervalSince1970: 1_750_000_000)

    func makeCollection(model: AnkiModel, deckName: String = "Default") -> AnkiCollection {
        AnkiCollection(
            createdAt: collectionEpoch,
            models: [model.id: model],
            deckNames: [1: deckName],
            notes: []
        )
    }

    func makeNote(modelID: Int, front: String, back: String,
                  cardType: Int = 2, due: Int = 100, odue: Int = 0, odid: Int = 0) -> AnkiNote {
        AnkiNote(id: 9001, modelID: modelID, fields: [front, back],
                 deckID: 1, cardType: cardType, due: due, odue: odue, odid: odid)
    }

    // MARK: Happy path

    @Test func basicNote_mapsToBothFields() throws {
        let collection = makeCollection(model: basicModel)
        let note = makeNote(modelID: 1, front: "What is ATP?", back: "Adenosine triphosphate")
        let mapped = try #require(AnkiNoteMapper.map(note: note, collection: collection, importedAt: importedAt))
        #expect(mapped.question == "What is ATP?")
        #expect(mapped.answer == "Adenosine triphosphate")
        #expect(mapped.sourceSpan == "anki:9001:0")
    }

    @Test func basicNote_htmlStripped() throws {
        let collection = makeCollection(model: basicModel)
        let note = makeNote(modelID: 1, front: "&lt;b&gt;Mitosis&lt;/b&gt;", back: "Two cells [sound:x.mp3]")
        let mapped = try #require(AnkiNoteMapper.map(note: note, collection: collection, importedAt: importedAt))
        #expect(mapped.question == "Mitosis")
        #expect(mapped.answer == "Two cells ")
    }

    @Test func nestedDeckName_splitIntoTags() throws {
        let collection = makeCollection(model: basicModel, deckName: "Medical::Anatomy")
        let note = makeNote(modelID: 1, front: "Q", back: "A")
        let mapped = try #require(AnkiNoteMapper.map(note: note, collection: collection, importedAt: importedAt))
        #expect(mapped.tags == ["Medical", "Anatomy"])
    }

    @Test func singleDeckName_becomesSingleTag() throws {
        let collection = makeCollection(model: basicModel, deckName: "Default")
        let note = makeNote(modelID: 1, front: "Q", back: "A")
        let mapped = try #require(AnkiNoteMapper.map(note: note, collection: collection, importedAt: importedAt))
        #expect(mapped.tags == ["Default"])
    }

    // MARK: Due date conversion

    @Test func dueDate_reviewCard_usesCollectionEpoch() throws {
        let collection = makeCollection(model: basicModel)
        let note = makeNote(modelID: 1, front: "Q", back: "A", cardType: 2, due: 100)
        let mapped = try #require(AnkiNoteMapper.map(note: note, collection: collection, importedAt: importedAt))
        let expectedDue = collectionEpoch.addingTimeInterval(100 * 86_400)
        #expect(mapped.dueAt == expectedDue)
    }

    @Test func dueDate_learningCard_usesUnixTimestamp() throws {
        let collection = makeCollection(model: basicModel)
        let note = makeNote(modelID: 1, front: "Q", back: "A", cardType: 1, due: 1_700_100_000)
        let mapped = try #require(AnkiNoteMapper.map(note: note, collection: collection, importedAt: importedAt))
        #expect(mapped.dueAt == Date(timeIntervalSince1970: 1_700_100_000))
    }

    @Test func dueDate_newCard_usesImportedAt() throws {
        let collection = makeCollection(model: basicModel)
        let note = makeNote(modelID: 1, front: "Q", back: "A", cardType: 0, due: 5)
        let mapped = try #require(AnkiNoteMapper.map(note: note, collection: collection, importedAt: importedAt))
        #expect(mapped.dueAt == importedAt)
    }

    @Test func dueDate_filteredDeck_usesOdue() throws {
        let collection = makeCollection(model: basicModel)
        let note = makeNote(modelID: 1, front: "Q", back: "A", cardType: 2, due: 999, odue: 50, odid: 7)
        let mapped = try #require(AnkiNoteMapper.map(note: note, collection: collection, importedAt: importedAt))
        let expectedDue = collectionEpoch.addingTimeInterval(50 * 86_400)
        #expect(mapped.dueAt == expectedDue)
    }

    // MARK: Skip cases

    @Test func clozeNote_isSkipped() {
        let collection = makeCollection(model: clozeModel)
        let note = makeNote(modelID: 2, front: "{{c1::Paris}}", back: "")
        let mapped = AnkiNoteMapper.map(note: note, collection: collection, importedAt: importedAt)
        #expect(mapped == nil)
    }

    @Test func modelMissingFrontBack_isSkipped() {
        let collection = makeCollection(model: noFBModel)
        let note = makeNote(modelID: 3, front: "Bonjour", back: "Hello")
        let mapped = AnkiNoteMapper.map(note: note, collection: collection, importedAt: importedAt)
        #expect(mapped == nil)
    }

    // MARK: Ordinal-aware identity + cloze skip

    @Test func sourceSpanIncludesCardOrdinal() {
        let span0 = AnkiNoteMapper.sourceSpan(noteID: 42, cardOrd: 0)
        let span1 = AnkiNoteMapper.sourceSpan(noteID: 42, cardOrd: 1)
        #expect(span0 == "anki:42:0")
        #expect(span1 == "anki:42:1")
        #expect(span0 != span1)
    }

    @Test func clozeNoteTypesAreSkipped() {
        #expect(AnkiNoteMapper.isClozeModel(name: "Cloze") == true)
        #expect(AnkiNoteMapper.isClozeModel(name: "Basic") == false)
    }
}
