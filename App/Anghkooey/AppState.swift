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

    // MARK: Observed by ContentView

    /// Persistence layer injected at app startup; `MockCardStore` until M4.9
    /// wires the real `CardStore` backed by a `ModelContainer`.
    let cardStore: any CardStoreProtocol

    // MARK: Private state

    private var pendingDrafts: [IdentifiedDraft] = []
    private let drainer: InboxDrainer
    private let bridge: DrainerBridge
    private var notificationToken: InboxNotificationToken?
    private let cardAuthor: any CardAuthoringService
    private var widgetReconciler: WidgetGradeReconciler
    private let optimizedParamsStore: OptimizedParametersStore
    private let widgetContainerURL: URL

    /// The resolved FSRS engine — default params until enough history accumulates.
    private(set) var scheduler: any FSRS6Engine = LiveFSRS6Engine()

    // Tracks the "card-review-sheet-ready" signpost interval: begun when a
    // draft is assigned to `presentedDraft`, ended on the sheet's onAppear.
    private var reviewSheetSignpostState: OSSignpostIntervalState?

    // MARK: Init

    init(
        cardAuthor: any CardAuthoringService = LiveCardAuthoringService(),
        cardStore: any CardStoreProtocol = MockCardStore()
    ) {
        self.cardAuthor = cardAuthor
        self.cardStore = cardStore

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
        self.widgetContainerURL = containerURL
        self.optimizedParamsStore = OptimizedParametersStore(containerURL: containerURL)
        self.widgetReconciler = WidgetGradeReconciler(
            store: cardStore,
            bridge: WidgetBridge(containerURL: containerURL)
        )

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
        try? await widgetReconciler.reconcile()
        await refreshScheduler()
    }

    /// Resolves optimized-or-default FSRS params from accumulated history and
    /// rebuilds the scheduler + widget reconciler. Call on launch and after
    /// each drain or optimization run.
    func refreshScheduler() async {
        let rows = (try? await cardStore.optimizationReviewLogs()) ?? []
        let eligible = OptimizationDataset(rows: rows).eligibleSampleCount
        let params = optimizedParamsStore.resolveParameters(eligibleSampleCount: eligible)
        let engine = LiveFSRS6Engine(parameters: params)
        self.scheduler = engine
        self.widgetReconciler = WidgetGradeReconciler(
            store: cardStore,
            bridge: WidgetBridge(containerURL: widgetContainerURL),
            scheduler: engine)
    }

    // MARK: Sheet queue

    /// Accepts the current draft with the supplied (possibly edited) Q/A.
    /// Called by `CardReviewSheet`'s Accept button.
    func acceptDraft(question: String, answer: String) {
        guard let draft = presentedDraft else { return }
        let tags = draft.draft.proposedTags
        advanceQueue()
        Task {
            try? await cardStore.create(
                question: question,
                answer: answer,
                sourceSpan: draft.draft.sourceSpan,
                tags: tags,
                now: .now
            )
            try? await widgetReconciler.rewriteSnapshot()
        }
        NotificationCenter.default.post(name: .anghkooeyCardAccepted, object: nil)
    }

    /// Convenience shim: accepts using the draft's original (unedited) Q/A.
    /// Kept so existing test call sites compile unchanged.
    func acceptDraft() {
        guard let draft = presentedDraft else { return }
        acceptDraft(question: draft.draft.question, answer: draft.draft.answer)
    }

    func skipDraft() { advanceQueue() }

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
    func enqueue(resolvedText: String) async {
        do {
            let draft = try await cardAuthor.author(from: resolvedText)
            pendingDrafts.append(IdentifiedDraft(draft: draft))
            if presentedDraft == nil { advanceQueue() }
        } catch {
            let fallback = CardDraft(question: resolvedText, answer: "(edit to add answer)")
            pendingDrafts.append(IdentifiedDraft(draft: fallback))
            if presentedDraft == nil { advanceQueue() }
        }
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
