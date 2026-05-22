import Foundation

public extension Notification.Name {
    /// Posted by `AppState` after the user accepts a `CardDraft` (creating a
    /// persisted `Card`). `ReviewScreen` observes this to refresh its due queue.
    static let anghkooeyCardAccepted = Notification.Name(
        "com.mitsheth.anghkooey.cardAccepted"
    )
}
