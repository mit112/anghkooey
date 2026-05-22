import Foundation
import CryptoKit

/// Write-side contract for the App Group inbox.
///
/// Implemented by `InboxWriter`; the protocol exists for test-time substitution.
public protocol InboxWriterProtocol: Sendable {
    /// Write a text capture to the inbox.
    ///
    /// No-ops silently on a dedup hit (same normalised text hash within
    /// `InboxConstants.dedupWindowSeconds`). Truncates text longer than
    /// `InboxConstants.textCharacterLimit` at the last sentence boundary.
    func write(text: String, sourceApp: String) async throws

    /// Write a raw image capture to the inbox.
    ///
    /// Saves `imageData` to `inbox/images/<UUID>.heic`, then writes the
    /// corresponding JSON item atomically. No dedup is applied to images.
    func write(imageData: Data, sourceApp: String) async throws
}

/// Writes `InboxItem` files atomically to the App Group inbox directory.
///
/// **Lifecycle — extension side only.** `InboxWriter` appends files and reads
/// existing JSON only for text dedup; it never deletes them. See ADR-0003 for
/// the full contract.
///
/// Use a temp directory as `containerURL` in unit tests — no App Group
/// provisioning is required.
public actor InboxWriter: InboxWriterProtocol {

    private let containerURL: URL

    /// - Parameter containerURL: Root of the App Group container
    ///   (`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`).
    public init(containerURL: URL) {
        self.containerURL = containerURL
    }

    public func write(text: String, sourceApp: String) async throws {
        let now = Date.now
        let normalisedText = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let textHash = Self.sha256Hex(for: normalisedText)

        guard try !hasDuplicate(textHash: textHash, now: now) else { return }

        try createInboxDirectories()

        let id = UUID()
        let item = InboxItem(
            id: id,
            capturedAt: now,
            sourceApp: sourceApp,
            kind: .text,
            text: Self.truncatedTextIfNeeded(text),
            textHash: textHash
        )

        try writeJSONItem(item)
        postInboxDidChangeNotification()
    }

    public func write(imageData: Data, sourceApp: String) async throws {
        try createInboxDirectories()

        let id = UUID()
        let imageFilename = "\(id.uuidString).heic"
        let relativeImagePath = "images/\(imageFilename)"
        let imageURL = imagesURL.appendingPathComponent(imageFilename)
        try imageData.write(to: imageURL)

        let item = InboxItem(
            id: id,
            capturedAt: .now,
            sourceApp: sourceApp,
            kind: .imageRef,
            imagePath: relativeImagePath
        )

        try writeJSONItem(item)
        postInboxDidChangeNotification()
    }
}

private extension InboxWriter {
    var inboxURL: URL {
        containerURL.appendingPathComponent(InboxConstants.inboxDirectory, isDirectory: true)
    }

    var imagesURL: URL {
        containerURL.appendingPathComponent(InboxConstants.imagesDirectory, isDirectory: true)
    }

    func createInboxDirectories() throws {
        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
    }

    func hasDuplicate(textHash: String, now: Date) throws -> Bool {
        guard FileManager.default.fileExists(atPath: inboxURL.path) else { return false }

        let jsonFiles = try FileManager.default.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        for fileURL in jsonFiles {
            guard
                let data = try? Data(contentsOf: fileURL),
                let item = try? InboxItem.decoder.decode(InboxItem.self, from: data),
                item.textHash == textHash
            else {
                continue
            }

            let age = abs(now.timeIntervalSince(item.capturedAt))
            if age <= InboxConstants.dedupWindowSeconds {
                return true
            }
        }

        return false
    }

    func writeJSONItem(_ item: InboxItem) throws {
        let data = try InboxItem.encoder.encode(item)
        let finalURL = inboxURL.appendingPathComponent("\(item.id.uuidString).json")
        let tmpURL = inboxURL.appendingPathComponent("\(item.id.uuidString).json.tmp")

        try data.write(to: tmpURL)
        try FileManager.default.moveItem(at: tmpURL, to: finalURL)
    }

    func postInboxDidChangeNotification() {
        let name = CFNotificationName(InboxConstants.darwinNotificationName as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            name,
            nil,
            nil,
            true
        )
    }

    static func sha256Hex(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func truncatedTextIfNeeded(_ text: String) -> String {
        let limit = InboxConstants.textCharacterLimit
        guard text.count > limit else { return text }

        let limitIndex = text.index(text.startIndex, offsetBy: limit)
        var index = text.startIndex
        var sentenceBoundary: String.Index?

        while index < limitIndex {
            let nextIndex = text.index(after: index)
            if ".!?".contains(text[index]), nextIndex < limitIndex {
                sentenceBoundary = nextIndex
            }
            index = nextIndex
        }

        let truncationIndex = sentenceBoundary ?? text.index(before: limitIndex)
        return String(text[..<truncationIndex]) + " [truncated]"
    }
}
