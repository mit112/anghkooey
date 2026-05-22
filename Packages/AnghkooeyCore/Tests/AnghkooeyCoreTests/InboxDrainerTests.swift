import Testing
import Foundation
@testable import AnghkooeyCore

// MARK: - Test doubles

private struct MockOCRService: OCRServiceProtocol {
    let result: Result<String, Error>

    init(returning text: String) {
        self.result = .success(text)
    }

    init(throwing error: Error) {
        self.result = .failure(error)
    }

    func recognizeText(inImageData data: Data) async throws -> String {
        try result.get()
    }
}

private enum RoutingError: Error { case intentional }

private final class MockDelegate: InboxDrainerDelegate, @unchecked Sendable {
    var receivedItems: [(item: InboxItem, text: String)] = []
    var failedItems: [(item: InboxItem, error: Error)] = []
    var shouldThrowOnRead = false

    func drainer(_ drainer: InboxDrainer, didReadItem item: InboxItem, resolvedText: String) async throws {
        receivedItems.append((item, resolvedText))
        if shouldThrowOnRead { throw RoutingError.intentional }
    }

    func drainer(_ drainer: InboxDrainer, didFailItem item: InboxItem, error: Error) async {
        failedItems.append((item, error))
    }
}

// MARK: - Fixture helpers

private func makeTempContainer() throws -> URL {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("InboxDrainerTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    return tmp
}

private func inboxURL(_ container: URL) -> URL {
    container.appendingPathComponent(InboxConstants.inboxDirectory)
}

/// Plant a text `InboxItem` JSON file directly into `inbox`.
@discardableResult
private func plantTextItem(
    _ text: String,
    in inbox: URL,
    capturedAt: Date = .now,
    schemaVersion: Int = InboxConstants.schemaVersion
) throws -> InboxItem {
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    let item = InboxItem(
        schemaVersion: schemaVersion,
        capturedAt: capturedAt,
        sourceApp: "com.test",
        kind: .text,
        text: text,
        textHash: "placeholder"
    )
    try InboxItem.encoder.encode(item).write(
        to: inbox.appendingPathComponent("\(item.id.uuidString).json")
    )
    return item
}

/// Plant an imageRef `InboxItem` pair (JSON + fake image bytes) into `inbox`.
@discardableResult
private func plantImageRefItem(
    imageData: Data,
    in inbox: URL,
    capturedAt: Date = .now
) throws -> InboxItem {
    let imagesDir = inbox.appendingPathComponent("images")
    try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    let imageID = UUID()
    let item = InboxItem(
        capturedAt: capturedAt,
        sourceApp: "com.test",
        kind: .imageRef,
        imagePath: "images/\(imageID.uuidString).heic"
    )
    try imageData.write(to: inbox.appendingPathComponent(item.imagePath!))
    try InboxItem.encoder.encode(item).write(
        to: inbox.appendingPathComponent("\(item.id.uuidString).json")
    )
    return item
}

// MARK: - Tests

@Suite("InboxDrainer")
struct InboxDrainerTests {

    // MARK: Text item processing

    @Test func drainProcessesTextItem() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        try plantTextItem("Memory is the mother of all wisdom.", in: inboxURL(container))

        let delegate = MockDelegate()
        let drainer = InboxDrainer(containerURL: container, ocr: MockOCRService(returning: ""), delegate: delegate)
        await drainer.drain()

        #expect(delegate.receivedItems.count == 1)
        try #require(!delegate.receivedItems.isEmpty)
        #expect(delegate.receivedItems[0].text == "Memory is the mother of all wisdom.")
    }

    @Test func drainSortsItemsOldestFirst() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let inbox = inboxURL(container)

        try plantTextItem("Older", in: inbox, capturedAt: Date(timeIntervalSinceNow: -10))
        try plantTextItem("Newer", in: inbox, capturedAt: Date(timeIntervalSinceNow: -1))

        let delegate = MockDelegate()
        let drainer = InboxDrainer(containerURL: container, ocr: MockOCRService(returning: ""), delegate: delegate)
        await drainer.drain()

        try #require(delegate.receivedItems.count == 2)
        #expect(delegate.receivedItems[0].text == "Older")
        #expect(delegate.receivedItems[1].text == "Newer")
    }

    // MARK: File lifecycle

    @Test func drainDeletesJsonFileAfterSuccess() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let inbox = inboxURL(container)

        let item = try plantTextItem("Delete me.", in: inbox)
        let jsonURL = inbox.appendingPathComponent("\(item.id.uuidString).json")
        #expect(FileManager.default.fileExists(atPath: jsonURL.path))

        let delegate = MockDelegate()
        let drainer = InboxDrainer(containerURL: container, ocr: MockOCRService(returning: ""), delegate: delegate)
        await drainer.drain()

        #expect(!FileManager.default.fileExists(atPath: jsonURL.path), "JSON must be deleted after successful routing")
    }

    @Test func drainLeavesFileOnDelegateFailure() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let inbox = inboxURL(container)

        let item = try plantTextItem("Route me — routing will fail.", in: inbox)
        let jsonURL = inbox.appendingPathComponent("\(item.id.uuidString).json")

        let delegate = MockDelegate()
        delegate.shouldThrowOnRead = true
        let drainer = InboxDrainer(containerURL: container, ocr: MockOCRService(returning: ""), delegate: delegate)
        await drainer.drain()

        #expect(delegate.receivedItems.count == 1, "Drain must attempt to route the item before seeing the throw")
        #expect(FileManager.default.fileExists(atPath: jsonURL.path), "JSON must survive when delegate throws (retry on next drain)")
    }

    @Test func drainStopsAfterFirstDelegateFailure() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let inbox = inboxURL(container)

        try plantTextItem("First", in: inbox, capturedAt: Date(timeIntervalSinceNow: -5))
        try plantTextItem("Second", in: inbox, capturedAt: Date(timeIntervalSinceNow: -4))
        try plantTextItem("Third", in: inbox, capturedAt: Date(timeIntervalSinceNow: -3))

        let delegate = MockDelegate()
        delegate.shouldThrowOnRead = true
        let drainer = InboxDrainer(containerURL: container, ocr: MockOCRService(returning: ""), delegate: delegate)
        await drainer.drain()

        // Drain must stop after the first routing failure.
        #expect(delegate.receivedItems.count == 1)
    }

    // MARK: Schema version guard

    @Test func drainSkipsUnknownSchemaVersion() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let inbox = inboxURL(container)

        let futureItem = try plantTextItem("Future format.", in: inbox, schemaVersion: 99)
        let jsonURL = inbox.appendingPathComponent("\(futureItem.id.uuidString).json")

        let delegate = MockDelegate()
        let drainer = InboxDrainer(containerURL: container, ocr: MockOCRService(returning: ""), delegate: delegate)
        await drainer.drain()

        #expect(delegate.receivedItems.isEmpty, "Unknown schema version must not be routed")
        #expect(FileManager.default.fileExists(atPath: jsonURL.path), "Unknown schema version file must be left for a future app version")
    }

    // MARK: imageRef items

    @Test func drainProcessesImageRefItemViaOCR() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let ocrText = "Recognised text from image."
        try plantImageRefItem(imageData: Data(repeating: 0xAB, count: 256), in: inboxURL(container))

        let delegate = MockDelegate()
        let drainer = InboxDrainer(containerURL: container, ocr: MockOCRService(returning: ocrText), delegate: delegate)
        await drainer.drain()

        #expect(delegate.receivedItems.count == 1)
        try #require(!delegate.receivedItems.isEmpty)
        #expect(delegate.receivedItems[0].text == ocrText)
    }

    @Test func drainDeletesBothFilesAfterImageRefSuccess() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let inbox = inboxURL(container)

        let item = try plantImageRefItem(imageData: Data(repeating: 0x01, count: 256), in: inbox)
        let jsonURL = inbox.appendingPathComponent("\(item.id.uuidString).json")
        let imageURL = inbox.appendingPathComponent(item.imagePath!)

        let delegate = MockDelegate()
        let drainer = InboxDrainer(containerURL: container, ocr: MockOCRService(returning: "text"), delegate: delegate)
        await drainer.drain()

        #expect(!FileManager.default.fileExists(atPath: jsonURL.path))
        #expect(!FileManager.default.fileExists(atPath: imageURL.path))
    }

    @Test func drainDeletesOversizeImage() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let inbox = inboxURL(container)
        let imagesDir = inbox.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        let imageID = UUID()
        let item = InboxItem(
            capturedAt: .now,
            sourceApp: "com.test",
            kind: .imageRef,
            imagePath: "images/\(imageID.uuidString).heic"
        )
        let imageURL = inbox.appendingPathComponent(item.imagePath!)
        // Allocate a file 1 byte over the limit.
        let oversizeData = Data(count: Int(InboxConstants.imageFileSizeLimit) + 1)
        try oversizeData.write(to: imageURL)
        try InboxItem.encoder.encode(item).write(
            to: inbox.appendingPathComponent("\(item.id.uuidString).json")
        )

        let delegate = MockDelegate()
        let drainer = InboxDrainer(containerURL: container, ocr: MockOCRService(returning: ""), delegate: delegate)
        await drainer.drain()

        #expect(delegate.receivedItems.isEmpty, "Oversize image must not be routed")
        #expect(!FileManager.default.fileExists(atPath: imageURL.path), "Oversize image file must be deleted")
    }

    @Test func drainDeletesBothFilesOnOCRFailure() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let inbox = inboxURL(container)

        let item = try plantImageRefItem(imageData: Data(repeating: 0x01, count: 256), in: inbox)
        let jsonURL = inbox.appendingPathComponent("\(item.id.uuidString).json")
        let imageURL = inbox.appendingPathComponent(item.imagePath!)

        enum OCRFail: Error { case oops }
        let delegate = MockDelegate()
        let drainer = InboxDrainer(containerURL: container, ocr: MockOCRService(throwing: OCRFail.oops), delegate: delegate)
        await drainer.drain()

        #expect(delegate.failedItems.count == 1, "OCR failure must call didFailItem")
        #expect(!FileManager.default.fileExists(atPath: jsonURL.path), "JSON deleted on unrecoverable OCR failure")
        #expect(!FileManager.default.fileExists(atPath: imageURL.path), "Image deleted on unrecoverable OCR failure")
    }

    // MARK: Orphan eviction

    @Test func drainEvictsTextItemsOlderThan7Days() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let inbox = inboxURL(container)

        let ancientDate = Date(timeIntervalSinceNow: -(Double(InboxConstants.orphanEvictionDays) * 86_400 + 1))
        let staleItem = try plantTextItem("Ancient news.", in: inbox, capturedAt: ancientDate)
        let staleURL = inbox.appendingPathComponent("\(staleItem.id.uuidString).json")

        let freshItem = try plantTextItem("Fresh news.", in: inbox)
        let freshURL = inbox.appendingPathComponent("\(freshItem.id.uuidString).json")

        let delegate = MockDelegate()
        let drainer = InboxDrainer(containerURL: container, ocr: MockOCRService(returning: ""), delegate: delegate)
        await drainer.drain()

        #expect(!FileManager.default.fileExists(atPath: staleURL.path), "7-day-old item must be evicted")
        // Fresh item was routed successfully and therefore also deleted.
        #expect(!FileManager.default.fileExists(atPath: freshURL.path))
    }

    @Test func drainEvictsOrphanImageFiles() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let inbox = inboxURL(container)
        let imagesDir = inbox.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        // Drop an image file with no corresponding JSON (orphan from a prior extension crash).
        let orphanURL = imagesDir.appendingPathComponent("orphan-\(UUID().uuidString).heic")
        try Data(repeating: 0xFF, count: 64).write(to: orphanURL)

        // Backdate the mtime past the grace period — fresh orphans are intentionally
        // preserved to dodge the extension-write race; see `drainPreservesRecentlyWrittenOrphanImages`.
        let staleDate = Date(timeIntervalSinceNow: -(InboxConstants.orphanImageGraceSeconds + 5))
        try FileManager.default.setAttributes(
            [.modificationDate: staleDate],
            ofItemAtPath: orphanURL.path
        )

        let delegate = MockDelegate()
        let drainer = InboxDrainer(containerURL: container, ocr: MockOCRService(returning: ""), delegate: delegate)
        await drainer.drain()

        #expect(!FileManager.default.fileExists(atPath: orphanURL.path), "Stale orphan image with no matching JSON must be deleted")
    }

    @Test func drainPreservesRecentlyWrittenOrphanImages() async throws {
        // Regression test for the M3.10 race: the extension writes the image
        // file, then the JSON descriptor; a concurrent drain in its cleanup
        // phase must NOT delete the image during the brief in-between window,
        // because the JSON is about to arrive.
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let inbox = inboxURL(container)
        let imagesDir = inbox.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        let freshOrphanURL = imagesDir.appendingPathComponent("fresh-\(UUID().uuidString).heic")
        try Data(repeating: 0xAA, count: 64).write(to: freshOrphanURL)
        // mtime is current "now" — well inside the grace window.

        let delegate = MockDelegate()
        let drainer = InboxDrainer(containerURL: container, ocr: MockOCRService(returning: ""), delegate: delegate)
        await drainer.drain()

        #expect(
            FileManager.default.fileExists(atPath: freshOrphanURL.path),
            "Fresh orphan image inside the grace window must be preserved — the matching JSON may still be on its way from the extension"
        )
    }

    // MARK: Concurrency

    @Test func concurrentDrainCallsSerialize() async throws {
        let container = try makeTempContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let inbox = inboxURL(container)

        try plantTextItem("Item A", in: inbox, capturedAt: Date(timeIntervalSinceNow: -2))
        try plantTextItem("Item B", in: inbox, capturedAt: Date(timeIntervalSinceNow: -1))

        let delegate = MockDelegate()
        let drainer = InboxDrainer(containerURL: container, ocr: MockOCRService(returning: ""), delegate: delegate)

        // Two concurrent drain calls — the actor serialises them. Each item must be
        // routed exactly once; no double-processing.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await drainer.drain() }
            group.addTask { await drainer.drain() }
        }

        #expect(delegate.receivedItems.count == 2, "Exactly 2 items routed — no duplicates from concurrent drains")
    }
}
