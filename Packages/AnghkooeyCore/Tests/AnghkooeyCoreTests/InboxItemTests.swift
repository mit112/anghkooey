import Testing
import Foundation
@testable import AnghkooeyCore

@Suite("InboxItem model")
struct InboxItemTests {

    // A fixed Date with no sub-second component so ISO 8601 roundtrips exactly.
    private let fixedDate = Date(timeIntervalSince1970: 1_716_000_000)

    @Test func textItemRoundtrips() throws {
        let original = InboxItem(
            id: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!,
            capturedAt: fixedDate,
            sourceApp: "com.apple.mobilesafari",
            kind: .text,
            text: "The mitochondria is the powerhouse of the cell.",
            textHash: "abc123def456",
            imagePath: nil
        )
        let data = try InboxItem.encoder.encode(original)
        let decoded = try InboxItem.decoder.decode(InboxItem.self, from: data)
        #expect(decoded == original)
    }

    @Test func imageRefItemRoundtrips() throws {
        let original = InboxItem(
            id: UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!,
            capturedAt: fixedDate,
            sourceApp: "com.apple.photos",
            kind: .imageRef,
            text: nil,
            textHash: nil,
            imagePath: "images/6ba7b810-9dad-11d1-80b4-00c04fd430c8.heic"
        )
        let data = try InboxItem.encoder.encode(original)
        let decoded = try InboxItem.decoder.decode(InboxItem.self, from: data)
        #expect(decoded == original)
    }

    @Test("schemaVersion > 1 decodes without throwing — skip logic belongs to InboxDrainer")
    func unknownSchemaVersionDecodes() throws {
        let json = """
        {
          "capturedAt": "2026-05-21T12:00:00Z",
          "id": "550e8400-e29b-41d4-a716-446655440001",
          "imagePath": null,
          "kind": "text",
          "schemaVersion": 99,
          "sourceApp": "com.apple.mobilesafari",
          "text": "Some captured text",
          "textHash": "deadbeef"
        }
        """.data(using: .utf8)!
        let item = try InboxItem.decoder.decode(InboxItem.self, from: json)
        #expect(item.schemaVersion == 99)
        #expect(item.kind == .text)
    }

    @Test func schemaVersionDefaultsToConstant() {
        let item = InboxItem(sourceApp: "com.example.app", kind: .text)
        #expect(item.schemaVersion == InboxConstants.schemaVersion)
    }

    @Test func encodedJSONContainsExpectedKeys() throws {
        let item = InboxItem(
            capturedAt: fixedDate,
            sourceApp: "com.apple.mobilesafari",
            kind: .text,
            text: "Hello",
            textHash: "abc"
        )
        let data = try InboxItem.encoder.encode(item)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["schemaVersion"] != nil)
        #expect(json["id"] != nil)
        #expect(json["capturedAt"] != nil)
        #expect(json["sourceApp"] as? String == "com.apple.mobilesafari")
        #expect(json["kind"] as? String == "text")
        #expect(json["text"] as? String == "Hello")
    }
}
