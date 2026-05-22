import Foundation

/// Constants that lock the App Group Inbox contract defined in ADR-0003.
///
/// Any value change here constitutes a revision to ADR-0003 and must
/// bump `schemaVersion` if it affects the JSON format.
public enum InboxConstants {
    public static let appGroupID             = "group.com.mitsheth.anghkooey"
    public static let inboxDirectory         = "inbox"
    public static let imagesDirectory        = "inbox/images"
    public static let darwinNotificationName = "com.mitsheth.anghkooey.inboxDidChange"

    /// Dedup window: submissions with the same `textHash` within this interval are dropped.
    public static let dedupWindowSeconds: TimeInterval = 60

    /// Raw text is truncated to this many characters before writing (last sentence boundary).
    public static let textCharacterLimit     = 50_000

    /// Images larger than this on drain are deleted and logged as warnings.
    public static let imageFileSizeLimit: Int64 = 25 * 1_024 * 1_024   // 25 MB

    /// Inbox items older than this are evicted on drain regardless of processing state.
    public static let orphanEvictionDays     = 7

    /// Grace period before an "orphan" image (no matching JSON yet) becomes eligible
    /// for eviction. Protects against the race where the extension has written the
    /// image but not yet renamed the JSON descriptor into place when a concurrent
    /// drain reaches its cleanup phase. See M3.10 device baseline notes.
    public static let orphanImageGraceSeconds: TimeInterval = 60

    /// Fault threshold: drain logs a fault if the inbox exceeds this item count.
    public static let inboxItemLimit         = 50

    /// JSON schema version for `InboxItem`. Bump when the JSON format changes.
    public static let schemaVersion          = 1
}
