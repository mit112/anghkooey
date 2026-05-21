import Foundation

/// Discriminates the kind of captured material in an `InboxItem`.
public enum InboxItemKind: String, Codable, Sendable, Equatable {
    /// Captured plain text (from Share Extension text extraction).
    case text
    /// Reference to an image file stored at `InboxItem.imagePath`.
    /// Main app runs OCR on drain; the image is deleted after text extraction.
    case imageRef
}

/// One submission written by the Share Extension into the App Group inbox.
///
/// One JSON file per item; filename is `<id.uuidString>.json` relative to the
/// `inbox/` directory in the App Group container. See ADR-0003 for the full
/// contract (atomicity, lifecycle, dedup, payload limits).
public struct InboxItem: Codable, Sendable, Equatable {

    // MARK: - Fields

    /// Incremented when the JSON format changes. Main app skips items it cannot parse.
    public let schemaVersion: Int

    /// Stable per-submission identifier. Filename stem in `inbox/`.
    public let id: UUID

    /// Wall-clock time the extension created this item (UTC).
    public let capturedAt: Date

    /// Bundle ID of the host app that invoked the Share Extension.
    public let sourceApp: String

    /// Determines which optional fields are populated.
    public let kind: InboxItemKind

    /// Captured text. Populated when `kind == .text`; `nil` for `imageRef`.
    public let text: String?

    /// SHA-256 hex of normalized `text` (lowercased, whitespace-trimmed).
    /// Used by `InboxWriter` for dedup. `nil` for `imageRef` items.
    public let textHash: String?

    /// Path to the raw image file, relative to `inbox/`.
    /// Populated when `kind == .imageRef`; `nil` for `text` items.
    public let imagePath: String?

    // MARK: - Init

    public init(
        schemaVersion: Int = InboxConstants.schemaVersion,
        id: UUID = UUID(),
        capturedAt: Date = .now,
        sourceApp: String,
        kind: InboxItemKind,
        text: String? = nil,
        textHash: String? = nil,
        imagePath: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.capturedAt = capturedAt
        self.sourceApp = sourceApp
        self.kind = kind
        self.text = text
        self.textHash = textHash
        self.imagePath = imagePath
    }
}

// MARK: - Codable helpers

public extension InboxItem {
    /// Pre-configured encoder for inbox JSON files (ISO 8601 dates, sorted keys).
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    /// Pre-configured decoder for inbox JSON files (ISO 8601 dates).
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
