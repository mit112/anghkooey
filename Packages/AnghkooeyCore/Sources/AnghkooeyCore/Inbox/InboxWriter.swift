import Foundation

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
/// **Lifecycle — extension side only.** `InboxWriter` only creates files;
/// it never reads or deletes them. See ADR-0003 for the full contract.
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
        // Implementation: Codex task M3.2
        // Contract (ADR-0003 §5, §6):
        //   1. Normalise: trimmed + lowercased.
        //   2. Compute SHA-256 hex as textHash.
        //   3. Check dedup: scan existing inbox/*.json for same textHash
        //      within dedupWindowSeconds. Return without writing on hit.
        //   4. Truncate text at textCharacterLimit (last sentence boundary, append "[truncated]").
        //   5. Create inbox/ and inbox/images/ directories if absent.
        //   6. Write JSON to inbox/<UUID>.json.tmp via InboxItem.encoder.
        //   7. Atomic rename: FileManager.moveItem(at:to:) to <UUID>.json.
        //   8. Post Darwin notification: CFNotificationCenterPostNotification
        //      with InboxConstants.darwinNotificationName.
    }

    public func write(imageData: Data, sourceApp: String) async throws {
        // Implementation: Codex task M3.2
        // Contract (ADR-0003 §4, §5):
        //   1. Create inbox/ and inbox/images/ directories if absent.
        //   2. Generate a UUID for this submission.
        //   3. Write imageData to inbox/images/<UUID>.heic.
        //   4. Write JSON item (kind: .imageRef, imagePath: "images/<UUID>.heic")
        //      to inbox/<UUID>.json.tmp via InboxItem.encoder.
        //   5. Atomic rename: moveItem to <UUID>.json.
        //   6. Post Darwin notification.
    }
}
