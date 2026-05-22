import Foundation
import OSLog
import AnghkooeyCore
import AnghkooeyIntelligence

// MARK: - IdentifiedDraft

/// Wraps the M2 `CardDraft` with a stable `id` for `sheet(item:)` binding.
///
/// `CardDraft` is `@Generable` and therefore not `Identifiable`; this thin
/// wrapper provides the `Identifiable` conformance the SwiftUI sheet API needs
/// without mutating the Intelligence module.
struct IdentifiedDraft: Identifiable {
    let id = UUID()
    let draft: CardDraft
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

    // MARK: Sheet state (observed by AnghkooeyApp)

    var presentedDraft: IdentifiedDraft?

    // MARK: Private state

    private var pendingDrafts: [IdentifiedDraft] = []
    private let drainer: InboxDrainer
    private let bridge: DrainerBridge
    private var notificationToken: InboxNotificationToken?
    private let cardAuthor: any CardAuthoringService

    // Tracks the "card-review-sheet-ready" signpost interval: begun when a
    // draft is assigned to `presentedDraft`, ended on the sheet's onAppear.
    private var reviewSheetSignpostState: OSSignpostIntervalState?

    // MARK: Init

    init(cardAuthor: any CardAuthoringService = LiveCardAuthoringService()) {
        self.cardAuthor = cardAuthor

        let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: InboxConstants.appGroupID)
            ?? FileManager.default.temporaryDirectory

        let bridge = DrainerBridge()
        let drainer = InboxDrainer(
            containerURL: containerURL,
            ocr: LiveOCRServiceDataAdapter(),
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

    func acceptDraft() { advanceQueue() }
    func skipDraft()   { advanceQueue() }

    /// Called from `CardReviewSheet.onAppear` to close the
    /// `"card-review-sheet-ready"` signpost interval.
    func cardReviewSheetDidAppear() {
        guard let state = reviewSheetSignpostState else { return }
        CoreLog.poiSignposter.endInterval("card-review-sheet-ready", state)
        reviewSheetSignpostState = nil
    }

    // MARK: Internal (testable via @testable import)

    /// Called by DrainerBridge when the drainer resolves text from an inbox item.
    ///
    /// Runs `cardAuthor.author(from:)` to produce a Q&A draft. On failure,
    /// falls back to a stub draft so captured text is never silently lost.
    /// Implementation is intentionally left as a stub here; see M4.2 for full body.
    func enqueue(resolvedText: String) async {
        // M4.2 stub: Codex replaces this body with the full cardAuthor call.
        let fallback = CardDraft(question: resolvedText, answer: "(edit to add answer)")
        pendingDrafts.append(IdentifiedDraft(draft: fallback))
        if presentedDraft == nil { advanceQueue() }
    }

    // MARK: Private

    private func advanceQueue() {
        let next = pendingDrafts.isEmpty ? nil : pendingDrafts.removeFirst()
        presentedDraft = next
        if next != nil {
            let signposter = CoreLog.poiSignposter
            reviewSheetSignpostState = signposter.beginInterval(
                "card-review-sheet-ready",
                id: signposter.makeSignpostID()
            )
        }
    }
}
