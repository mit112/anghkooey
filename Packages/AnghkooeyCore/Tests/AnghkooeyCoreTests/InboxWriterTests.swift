import Testing
import Foundation
import CryptoKit
@testable import AnghkooeyCore

// MARK: - Helpers

private func makeTempContainer() throws -> URL {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("InboxWriterTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    return tmp
}

private func inboxURL(_ container: URL) -> URL {
    container.appendingPathComponent(InboxConstants.inboxDirectory)
}

private func jsonFiles(in inbox: URL) throws -> [URL] {
    guard FileManager.default.fileExists(atPath: inbox.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
}

// SHA-256 using the same normalisation InboxWriter should apply: trim + lowercase.
private func textHash(for text: String) -> String {
    let normalised = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let digest = SHA256.hash(data: Data(normalised.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

// MARK: - Tests

@Suite("InboxWriter")
struct InboxWriterTests {

    @Test func textWriteCreatesFile() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let writer = InboxWriter(containerURL: container)
        try await writer.write(text: "The mitochondria is the powerhouse of the cell.", sourceApp: "com.apple.mobilesafari")

        let files = try jsonFiles(in: inboxURL(container))
        try #require(files.count == 1, "Expected exactly 1 JSON file in inbox")

        let item = try InboxItem.decoder.decode(InboxItem.self, from: Data(contentsOf: files[0]))
        #expect(item.kind == .text)
        #expect(item.text == "The mitochondria is the powerhouse of the cell.")
        #expect(item.sourceApp == "com.apple.mobilesafari")
        #expect(item.textHash != nil)
        #expect(item.schemaVersion == InboxConstants.schemaVersion)
    }

    @Test func writtenFilenameMatchesItemID() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let writer = InboxWriter(containerURL: container)
        try await writer.write(text: "Filename matches ID.", sourceApp: "com.example")

        let files = try jsonFiles(in: inboxURL(container))
        try #require(!files.isEmpty)
        let item = try InboxItem.decoder.decode(InboxItem.self, from: Data(contentsOf: files[0]))
        let stem = files[0].deletingPathExtension().lastPathComponent
        #expect(stem == item.id.uuidString)
    }

    @Test func textHashUsesNormalisedInput() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let rawText = "  Hello World  "
        let writer = InboxWriter(containerURL: container)
        try await writer.write(text: rawText, sourceApp: "com.example")

        let files = try jsonFiles(in: inboxURL(container))
        try #require(!files.isEmpty)
        let item = try InboxItem.decoder.decode(InboxItem.self, from: Data(contentsOf: files[0]))
        #expect(item.textHash == textHash(for: rawText))
    }

    // MARK: Dedup

    @Test func dedupDropsDuplicateWithin60s() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let writer = InboxWriter(containerURL: container)
        try await writer.write(text: "Identical text.", sourceApp: "com.apple.mobilesafari")
        try await writer.write(text: "Identical text.", sourceApp: "com.apple.mobilesafari")

        let files = try jsonFiles(in: inboxURL(container))
        #expect(files.count == 1, "Second submission within 60 s must be silently dropped")
    }

    @Test func dedupNormalisesBeforeHashing() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let writer = InboxWriter(containerURL: container)
        try await writer.write(text: "  Hello World  ", sourceApp: "com.apple.mobilesafari")
        try await writer.write(text: "hello world", sourceApp: "com.apple.mobilesafari")

        let files = try jsonFiles(in: inboxURL(container))
        #expect(files.count == 1, "Whitespace-trimmed lowercase duplicates must be dropped")
    }

    @Test func dedupAllowsDuplicateOutsideWindow() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let inbox = inboxURL(container)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        let text = "I am repeated after the window."
        // Plant an item whose capturedAt is 61 s in the past (outside the 60 s window).
        let oldItem = InboxItem(
            capturedAt: Date(timeIntervalSinceNow: -(InboxConstants.dedupWindowSeconds + 1)),
            sourceApp: "com.example",
            kind: .text,
            text: text,
            textHash: textHash(for: text)
        )
        try InboxItem.encoder.encode(oldItem).write(
            to: inbox.appendingPathComponent("\(oldItem.id.uuidString).json")
        )

        let writer = InboxWriter(containerURL: container)
        try await writer.write(text: text, sourceApp: "com.example")

        let files = try jsonFiles(in: inbox)
        #expect(files.count == 2, "Duplicate outside the 60 s window must be accepted")
    }

    // MARK: Truncation

    @Test func textTruncatesAtCharacterLimit() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        // Build text clearly over the limit; repeat a sentence so there is a
        // sentence boundary to truncate at.
        let sentence = "The quick brown fox jumps. "
        let overLimit = String(repeating: sentence, count: (InboxConstants.textCharacterLimit / sentence.count) + 5)
        #expect(overLimit.count > InboxConstants.textCharacterLimit)

        let writer = InboxWriter(containerURL: container)
        try await writer.write(text: overLimit, sourceApp: "com.example")

        let files = try jsonFiles(in: inboxURL(container))
        try #require(!files.isEmpty)
        let item = try InboxItem.decoder.decode(InboxItem.self, from: Data(contentsOf: files[0]))
        let stored = try #require(item.text)
        #expect(stored.hasSuffix("[truncated]"))
        #expect(stored.count <= InboxConstants.textCharacterLimit + "[truncated]".count)
    }

    @Test func textWithinLimitIsNotTruncated() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let shortText = "Short text, well within the limit."
        let writer = InboxWriter(containerURL: container)
        try await writer.write(text: shortText, sourceApp: "com.example")

        let files = try jsonFiles(in: inboxURL(container))
        try #require(!files.isEmpty)
        let item = try InboxItem.decoder.decode(InboxItem.self, from: Data(contentsOf: files[0]))
        #expect(item.text == shortText)
    }

    // MARK: Image write

    @Test func imageRefWritesTwoFiles() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let writer = InboxWriter(containerURL: container)
        let fakeImageData = Data(repeating: 0xFF, count: 1_024)
        try await writer.write(imageData: fakeImageData, sourceApp: "com.apple.photos")

        let inbox = inboxURL(container)
        let jsonItems = try jsonFiles(in: inbox)
        try #require(jsonItems.count == 1)

        let item = try InboxItem.decoder.decode(InboxItem.self, from: Data(contentsOf: jsonItems[0]))
        #expect(item.kind == .imageRef)
        let imagePath = try #require(item.imagePath)
        #expect(item.text == nil)
        #expect(item.textHash == nil)

        let imageURL = inbox.appendingPathComponent(imagePath)
        #expect(FileManager.default.fileExists(atPath: imageURL.path), "Image file must exist at reported path")
        #expect(try Data(contentsOf: imageURL) == fakeImageData)
    }

    @Test func imageRefImagePathIsRelativeToInbox() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let writer = InboxWriter(containerURL: container)
        try await writer.write(imageData: Data(repeating: 0xAB, count: 512), sourceApp: "com.example")

        let files = try jsonFiles(in: inboxURL(container))
        try #require(!files.isEmpty)
        let item = try InboxItem.decoder.decode(InboxItem.self, from: Data(contentsOf: files[0]))
        let imagePath = try #require(item.imagePath)
        #expect(!imagePath.hasPrefix("/"), "imagePath must be relative (ADR-0003 §3)")
        #expect(imagePath.hasPrefix("images/"))
    }

    // MARK: Atomic write

    @Test func atomicRenameNoTmpFilesVisible() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let writer = InboxWriter(containerURL: container)
        // Two concurrent writes with distinct text so dedup does not interfere.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await writer.write(text: "First unique item.", sourceApp: "com.a") }
            group.addTask { try await writer.write(text: "Second unique item.", sourceApp: "com.b") }
            try await group.waitForAll()
        }

        let inbox = inboxURL(container)
        guard FileManager.default.fileExists(atPath: inbox.path) else {
            // No inbox directory means no writes happened — fail via count check.
            let jsonItems = try jsonFiles(in: inbox)
            #expect(jsonItems.count == 2, "Expected 2 JSON files")
            return
        }
        let tmpFiles = try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "tmp" }
        #expect(tmpFiles.isEmpty, "No .tmp staging files must remain after writes complete")

        let jsonItems = try jsonFiles(in: inbox)
        #expect(jsonItems.count == 2)
    }
}
