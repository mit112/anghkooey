import Foundation
import OSLog

private let log = Logger(subsystem: "com.mitsheth.anghkooey", category: "InboxDrainer")

/// Called by `InboxDrainer` as it processes each inbox item.
public protocol InboxDrainerDelegate: AnyObject, Sendable {
    /// Called when text is ready for routing (text item verbatim, or
    /// imageRef item after successful OCR).
    ///
    /// **Throwing signals routing failure:** `InboxDrainer` catches the error,
    /// leaves the item's JSON file in the inbox for retry on the next drain,
    /// and stops the current drain pass.
    func drainer(_ drainer: InboxDrainer, didReadItem item: InboxItem, resolvedText: String) async throws

    /// Called when the drainer itself cannot produce text for an item
    /// (e.g. OCR failure, corrupt file). The drainer has already deleted
    /// the item's files before calling this. Delegates use this for telemetry.
    func drainer(_ drainer: InboxDrainer, didFailItem item: InboxItem, error: Error) async
}

/// Drains `InboxItem` files from the App Group inbox and routes them to
/// `CardAuthor` (or the manual-entry flow) via `InboxDrainerDelegate`.
///
/// **Actor-serialised.** Concurrent `drain()` calls are queued automatically.
/// The main app calls `drain()` at launch, on foreground transition, and on
/// Darwin notification from the Share Extension. See ADR-0003 §5.
public actor InboxDrainer {

    private let containerURL: URL
    private let ocr: any OCRServiceProtocol
    private weak var delegate: (any InboxDrainerDelegate)?

    /// - Parameters:
    ///   - containerURL: Root of the App Group container.
    ///   - ocr: OCR service for resolving `imageRef` items.
    ///   - delegate: Receives processed items and failure notifications.
    public init(
        containerURL: URL,
        ocr: any OCRServiceProtocol,
        delegate: any InboxDrainerDelegate
    ) {
        self.containerURL = containerURL
        self.ocr = ocr
        self.delegate = delegate
    }

    /// Process all items currently in the inbox, oldest first.
    ///
    /// Stops on the first routing failure (delegate `didReadItem` throws).
    /// Always runs orphan eviction and 7-day TTL cleanup regardless.
    ///
    /// Implementation: Codex task M3.3.
    /// Contract (ADR-0003 §5):
    ///   1. Enumerate inbox/*.json, sort by capturedAt ascending.
    ///   2. Log a fault if count > InboxConstants.inboxItemLimit.
    ///   3. For each item:
    ///      a. Decode; on decode failure: delete file, continue.
    ///      b. If schemaVersion > InboxConstants.schemaVersion: skip (leave file).
    ///      c. If .imageRef: check image file size against imageFileSizeLimit;
    ///         on oversize: delete both files, call didFailItem, continue.
    ///      d. If .imageRef: call ocr.recognizeText(inImageData:);
    ///         on OCR error: delete both files, call didFailItem, continue.
    ///      e. Call delegate.drainer(_:didReadItem:resolvedText:).
    ///         On throw: leave file, STOP drain loop.
    ///         On success: delete JSON file (and image file if .imageRef).
    ///   4. Orphan eviction:
    ///      - Delete inbox/images/*.heic with no matching inbox/*.json.
    ///      - Delete inbox/*.json with capturedAt older than orphanEvictionDays.
    public func drain() async {
        // Implementation: Codex task M3.3
    }
}
