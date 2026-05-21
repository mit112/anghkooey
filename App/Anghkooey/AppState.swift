import Foundation
import AnghkooeyCore

// MARK: - Stub OCR service (replaced by LiveOCRService adapter in M3.9)

private struct NoOpOCRService: OCRServiceProtocol, Sendable {
    func recognizeText(inImageData _: Data) async throws -> String { "" }
}

// MARK: - Delegate bridge

/// Relays InboxDrainer callbacks to AppState on the main actor.
/// Holds a weak reference to avoid a retain cycle with the token.
private final class DrainerBridge: InboxDrainerDelegate, @unchecked Sendable {
    weak var appState: AppState?

    func drainer(_ drainer: InboxDrainer, didReadItem _: InboxItem, resolvedText: String) async throws {
        await appState?.enqueue(resolvedText: resolvedText)
    }

    func drainer(_ drainer: InboxDrainer, didFailItem _: InboxItem, error: Error) async {
        // Telemetry: wired in a later milestone.
        _ = error
    }
}

// MARK: - AppState

/// Owns the inbox drain pipeline and the sheet queue for one-at-a-time card review.
///
/// Hold one instance on `AnghkooeyApp` as `@State`. SwiftUI constructs it on the main
/// actor so all `@Observable` property accesses are correctly isolated.
@Observable
@MainActor
final class AppState: @unchecked Sendable {

    // MARK: Card draft model

    struct CardDraft: Identifiable {
        let id = UUID()
        let resolvedText: String
    }

    // MARK: Sheet state (observed by AnghkooeyApp)

    var presentedCard: CardDraft?

    // MARK: Private state

    private var pendingCards: [CardDraft] = []
    private let drainer: InboxDrainer
    private let bridge: DrainerBridge
    private var notificationToken: InboxNotificationToken?

    // MARK: Init

    init() {
        let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: InboxConstants.appGroupID)
            ?? FileManager.default.temporaryDirectory

        let bridge = DrainerBridge()
        let drainer = InboxDrainer(
            containerURL: containerURL,
            ocr: NoOpOCRService(),
            delegate: bridge
        )
        self.bridge = bridge
        self.drainer = drainer

        // All stored properties are initialized above; self is available.
        bridge.appState = self

        notificationToken = InboxNotifier.observeInboxDidChange { [weak self] in
            Task { @MainActor [weak self] in
                await self?.drain()
            }
        }
    }

    // MARK: Drain

    func drain() async {
        await drainer.drain()
    }

    // MARK: Sheet queue

    func acceptCard() { advanceQueue() }
    func skipCard()  { advanceQueue() }

    // MARK: Private

    /// Called by DrainerBridge when the drainer produces resolved text.
    fileprivate func enqueue(resolvedText: String) {
        pendingCards.append(CardDraft(resolvedText: resolvedText))
        if presentedCard == nil { advanceQueue() }
    }

    private func advanceQueue() {
        presentedCard = pendingCards.isEmpty ? nil : pendingCards.removeFirst()
    }
}
