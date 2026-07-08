import Foundation

public extension Notification.Name {
    /// Posted by `AppState` after the user accepts a `CardDraft` (creating a
    /// persisted `Card`). `ReviewScreen` observes this to refresh its due queue.
    static let anghkooeyCardAccepted = Notification.Name(
        "com.mitsheth.anghkooey.cardAccepted"
    )

    /// Posted after a card is deleted, so the app can refresh the widget
    /// snapshot and any screen can prune stale in-memory queues. The deleted
    /// card's `UUID` is passed as the notification's `object`.
    static let anghkooeyDeckDidChange = Notification.Name(
        "com.mitsheth.anghkooey.deckDidChange"
    )
}
