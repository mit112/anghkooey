import Foundation
import OSLog

private let log = Logger(subsystem: "com.mitsheth.anghkooey", category: "InboxDrainer")

private enum InboxDrainerError: Error, Sendable {
    case missingImagePath(itemID: UUID)
    case imageFileTooLarge(path: String, actualSize: Int64, limit: Int64)
}

private struct InboxFile: Sendable {
    let url: URL
    let capturedAt: Date
}

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
    weak var delegate: (any InboxDrainerDelegate)?
    private var isDraining = false

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
        guard !isDraining else { return }
        isDraining = true
        let signposter = CoreLog.poiSignposter
        let signpostID = signposter.makeSignpostID()
        let intervalState = signposter.beginInterval("inbox-drain", id: signpostID)
        defer {
            signposter.endInterval("inbox-drain", intervalState)
            isDraining = false
        }
        _ = await drainOnce()
    }

    private func drainOnce() async -> Bool {
        let inboxURL = containerURL.appendingPathComponent(InboxConstants.inboxDirectory)
        var stoppedForRoutingFailure = false

        if directoryExists(at: inboxURL) {
            let jsonURLs: [URL]

            do {
                jsonURLs = try sortedInboxItemURLs(inboxURL: inboxURL)
            } catch {
                return false
            }

            if jsonURLs.count > InboxConstants.inboxItemLimit {
                log.fault(
                    "Inbox item count \(jsonURLs.count, privacy: .public) exceeds limit \(InboxConstants.inboxItemLimit, privacy: .public)"
                )
            }

            for jsonURL in jsonURLs {
                let data: Data
                let item: InboxItem

                do {
                    data = try Data(contentsOf: jsonURL)
                    item = try InboxItem.decoder.decode(InboxItem.self, from: data)
                } catch {
                    removeItemIfPresent(at: jsonURL)
                    continue
                }

                guard item.schemaVersion <= InboxConstants.schemaVersion else {
                    continue
                }

                let resolvedText: String

                switch item.kind {
                case .text:
                    resolvedText = item.text ?? ""

                case .imageRef:
                    guard let imagePath = item.imagePath else {
                        let error = InboxDrainerError.missingImagePath(itemID: item.id)
                        removeItemIfPresent(at: jsonURL)
                        await delegate?.drainer(self, didFailItem: item, error: error)
                        continue
                    }

                    let imageURL = inboxURL.appendingPathComponent(imagePath)

                    if let imageSize = fileSize(at: imageURL),
                       imageSize > InboxConstants.imageFileSizeLimit {
                        let error = InboxDrainerError.imageFileTooLarge(
                            path: imagePath,
                            actualSize: imageSize,
                            limit: InboxConstants.imageFileSizeLimit
                        )
                        log.warning(
                            "Deleting oversize inbox image \(imagePath, privacy: .public) size \(imageSize, privacy: .public)"
                        )
                        removeItemIfPresent(at: jsonURL)
                        removeItemIfPresent(at: imageURL)
                        await delegate?.drainer(self, didFailItem: item, error: error)
                        continue
                    }

                    do {
                        let imageData = try Data(contentsOf: imageURL)
                        resolvedText = try await ocr.recognizeText(inImageData: imageData)
                    } catch {
                        log.error(
                            "Failed to OCR inbox image for item \(item.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                        removeItemIfPresent(at: jsonURL)
                        removeItemIfPresent(at: imageURL)
                        await delegate?.drainer(self, didFailItem: item, error: error)
                        continue
                    }
                }

                do {
                    try await delegate?.drainer(self, didReadItem: item, resolvedText: resolvedText)
                } catch {
                    stoppedForRoutingFailure = true
                    break
                }

                removeItemIfPresent(at: jsonURL)

                if item.kind == .imageRef, let imagePath = item.imagePath {
                    let imageURL = inboxURL.appendingPathComponent(imagePath)
                    removeItemIfPresent(at: imageURL)
                }
            }
        }

        cleanup(inboxURL: inboxURL)
        return stoppedForRoutingFailure
    }

    private func sortedInboxItemURLs(inboxURL: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(
                at: inboxURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == "json" }
            .map { url in
                InboxFile(
                    url: url,
                    capturedAt: (try? decodeInboxItem(at: url).capturedAt) ?? .distantPast
                )
            }
            .sorted { lhs, rhs in
                lhs.capturedAt < rhs.capturedAt
            }
            .map(\.url)
    }

    private func cleanup(inboxURL: URL) {
        evictOrphanImages(inboxURL: inboxURL)
        evictExpiredJSONItems(inboxURL: inboxURL)
    }

    private func evictOrphanImages(inboxURL: URL) {
        let imagesURL = inboxURL.appendingPathComponent("images")

        guard let imageURLs = try? FileManager.default.contentsOfDirectory(
            at: imagesURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let now = Date()
        for imageURL in imageURLs where imageURL.pathExtension == "heic" {
            // Skip recently-written images. The extension writes image then JSON;
            // a drain that races into cleanup between those two steps would
            // otherwise delete the image before the JSON arrives, losing the share.
            if let mtime = try? imageURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate,
               now.timeIntervalSince(mtime) < InboxConstants.orphanImageGraceSeconds {
                continue
            }

            let jsonURL = inboxURL.appendingPathComponent(imageURL.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("json")

            if !FileManager.default.fileExists(atPath: jsonURL.path) {
                removeItemIfPresent(at: imageURL)
            }
        }
    }

    private func evictExpiredJSONItems(inboxURL: URL) {
        guard let jsonURLs = try? FileManager.default.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let expirationDate = Date().addingTimeInterval(
            -Double(InboxConstants.orphanEvictionDays) * 86_400
        )

        for jsonURL in jsonURLs where jsonURL.pathExtension == "json" {
            guard let item = try? decodeInboxItem(at: jsonURL),
                  item.capturedAt < expirationDate else {
                continue
            }

            removeItemIfPresent(at: jsonURL)
        }
    }

    private func decodeInboxItem(at url: URL) throws -> InboxItem {
        let data = try Data(contentsOf: url)
        return try InboxItem.decoder.decode(InboxItem.self, from: data)
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            return nil
        }

        return size.int64Value
    }

    private func removeItemIfPresent(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            log.error("Failed to remove inbox file \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
