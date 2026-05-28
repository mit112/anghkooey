import Testing
import Foundation
@testable import Anghkooey
@testable import AnghkooeyCore

@Suite("AddToAnghkooey intent")
struct AddToAnghkooeyIntentTests {

    @Test("performing the intent writes a text item to the inbox writer")
    func performWritesInboxItem() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let writer = InboxWriter(containerURL: tmp)
        try await AddToAnghkooeyIntent.write(
            text: "Mitochondria is the powerhouse of the cell.",
            using: writer
        )

        let inbox = tmp.appendingPathComponent(InboxConstants.inboxDirectory)
        let files = try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(files.count == 1)

        let data = try Data(contentsOf: files[0])
        let item = try InboxItem.decoder.decode(InboxItem.self, from: data)
        #expect(item.kind == .text)
        #expect(item.text == "Mitochondria is the powerhouse of the cell.")
        #expect(item.sourceApp == "siri")
    }

    @Test("blank text throws and writes nothing")
    func blankThrows() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let writer = InboxWriter(containerURL: tmp)
        await #expect(throws: (any Error).self) {
            try await AddToAnghkooeyIntent.write(text: "   ", using: writer)
        }
    }
}
