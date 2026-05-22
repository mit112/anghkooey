import Foundation

/// Wraps the Darwin `CFNotificationCenter` to signal inbox changes across processes.
///
/// The Share Extension calls `postInboxDidChange()` after each atomic rename.
/// The main app calls `observeInboxDidChange(handler:)` once on launch and
/// holds the returned token for the lifetime of the session.
public struct InboxNotifier {

    private init() {}

    /// Post a Darwin notification so the main app knows the inbox has new content.
    public static func postInboxDidChange() {
        let name = CFNotificationName(InboxConstants.darwinNotificationName as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            name,
            nil,
            nil,
            true
        )
    }

    /// Register a Darwin observer for inbox changes.
    ///
    /// - Parameter handler: Called on the main queue each time the extension posts
    ///   an inbox-did-change notification.
    /// - Returns: A token that removes the observer when deallocated. Hold it for
    ///   as long as you want to receive callbacks.
    public static func observeInboxDidChange(
        handler: @Sendable @escaping () -> Void
    ) -> InboxNotificationToken {
        InboxNotificationToken(handler: handler)
    }
}

/// Cancels the Darwin observer on deinit. Hold an instance for the lifetime of
/// the observation; release (or set to `nil`) to stop receiving notifications.
public final class InboxNotificationToken: @unchecked Sendable {

    private let name: CFNotificationName

    init(handler: @Sendable @escaping () -> Void) {
        name = CFNotificationName(InboxConstants.darwinNotificationName as CFString)

        // Box the handler so we can pass it through the C callback.
        let box = HandlerBox(handler: handler)
        let rawPointer = Unmanaged.passRetained(box).toOpaque()

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            rawPointer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let box = Unmanaged<HandlerBox>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { box.handler() }
            },
            InboxConstants.darwinNotificationName as CFString,
            nil,
            .deliverImmediately
        )

        self.rawPointer = rawPointer
    }

    private let rawPointer: UnsafeMutableRawPointer

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            rawPointer,
            name,
            nil
        )
        Unmanaged<HandlerBox>.fromOpaque(rawPointer).release()
    }
}

private final class HandlerBox: @unchecked Sendable {
    let handler: @Sendable () -> Void
    init(handler: @Sendable @escaping () -> Void) { self.handler = handler }
}
