import Foundation
import OSLog
import AnghkooeyCore
import AnghkooeyIntelligence
import AnghkooeyUI

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
        await appState?.recordDrainFailure(error)
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

    /// Surfaces `acceptDraft` failures as a toast. `acceptDraft` is only ever
    /// invoked from `CardReviewSheet`, and a failure always leaves a sheet on
    /// screen (the draft is re-presented, or the next one shows) — so
    /// `.errorToast(appState.errorPresenter)` is applied to the
    /// `CardReviewSheet` content in `AnghkooeyApp`'s `.sheet(item:)`, not to
    /// the app root. A root-level toast would render *behind* the modal
    /// sheet and never be seen (#20). The presenter itself still lives here
    /// on `AppState`, not as sheet-local `@State`, so it survives the sheet
    /// being torn down and re-presented between drafts.
    ///
    /// For app-level messages that can fire with no sheet up (e.g. dropped
    /// inbox captures, #28), see `rootErrorPresenter` instead — sharing this
    /// instance across both contexts would let a stale accept-draft toast
    /// resurface at the root the moment a sheet dismisses, or a drain-failure
    /// toast bleed into an unrelated `CardReviewSheet` that opens while it's
    /// still on screen.
    let errorPresenter = ErrorPresenter()

    /// Surfaces app-level failures that have no associated sheet — currently
    /// just the per-drain-pass "dropped captures" summary (#28). Applied via
    /// `.errorToast(appState.rootErrorPresenter)` at the `ContentView` root
    /// in `AnghkooeyApp`, so it stays visible regardless of sheet state.
    /// Kept separate from `errorPresenter` (see its doc comment) so the two
    /// contexts never cross-contaminate each other's toasts.
    let rootErrorPresenter = ErrorPresenter()

    // MARK: Private state

    private var pendingDrafts: [IdentifiedDraft] = []

    /// Reentrancy guard for `acceptDraft(question:answer:)`. `AnghkooeyApp`
    /// wraps the Accept button's tap in `Task { await appState.acceptDraft(...) }`,
    /// so a rapid double-tap enqueues two Tasks that both resolve
    /// `presentedDraft` at *task-run* time, not tap time. Without this guard,
    /// the second task can start running while the first is still suspended
    /// mid-persist, read `presentedDraft` as the draft the first task just
    /// advanced to, and persist that next draft using the first tap's
    /// (stale) question/answer text. Setting this flag for the duration of
    /// the whole method makes the second, overlapping call a no-op instead —
    /// the correct, current draft stays presented for a fresh accept.
    private var isProcessingAccept = false

    /// Number of inbox items dropped (`didFailItem`) during the drain pass
    /// currently in progress. Reset by `beginDrainPass()`, read and reported
    /// by `finishDrainPass()` — see `drain()` (#28).
    private var failedDrainItemCount = 0

    /// Reentrancy guard for `drain()`. `drain()` is invoked from three
    /// unsynchronized triggers (launch `.task`, scenePhase `.active`, and
    /// the Darwin-notification observer) and suspends at multiple points
    /// (`drainer.drain()`, `widgetReconciler.reconcile()`,
    /// `refreshScheduler()`). Without this guard, a second concurrent call
    /// runs its own `beginDrainPass()` — resetting `failedDrainItemCount` to
    /// zero — while the first pass is still recording drops via
    /// `recordDrainFailure`, corrupting or silently swallowing the
    /// end-of-pass summary (#28). Dropping a concurrent trigger outright is
    /// fine: `drainer.drain()` already processes every item currently in
    /// the inbox, and these triggers fire often enough that the next
    /// foreground/notification will pick up anything that arrives after.
    private var isDraining = false

    private let drainer: InboxDrainer
    private let bridge: DrainerBridge
    private var notificationToken: InboxNotificationToken?
    private let cardAuthor: any CardAuthoringService
    private var widgetReconciler: WidgetGradeReconciler
    let optimizedParamsStore: OptimizedParametersStore
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
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        beginDrainPass()
        await drainer.drain()
        do {
            try await widgetReconciler.reconcile()
        } catch {
            CoreLog.persistence.error(
                "drain: widget reconcile failed: \(error.localizedDescription, privacy: .public)")
        }
        await refreshScheduler()
        finishDrainPass()
    }

    /// Resets the per-pass drop counter. Called before `drainer.drain()` so
    /// each pass starts from zero regardless of what a previous pass saw.
    /// Split out from `drain()` so tests can drive `recordDrainFailure` +
    /// `finishDrainPass` directly without a real `InboxDrainer` (#28).
    func beginDrainPass() {
        failedDrainItemCount = 0
    }

    /// Reports the drain pass that just finished. Per ADR-0003 §9, a
    /// `didFailItem` drop means the drainer has already deleted the item's
    /// files — this is not a retry candidate, so the only recovery is
    /// telling the user to re-share it. Rather than one toast per dropped
    /// item, this shows a single summary once the whole pass is done.
    ///
    /// Known limitation: `rootErrorPresenter`'s toast is a `safeAreaInset`
    /// on `ContentView` (see the presenter's declaration above), so if a
    /// drain failure lands while a sheet (draft review, Anki import) is
    /// presented, this toast renders *behind* that sheet and may
    /// auto-dismiss before the user ever sees it. Still a strict
    /// improvement over the prior silent no-op (#28); a robust fix
    /// (persistent-until-seen toast, or sheet-aware presentation) is
    /// deferred.
    func finishDrainPass() {
        guard failedDrainItemCount > 0 else { return }
        rootErrorPresenter.present(
            "Couldn't read \(failedDrainItemCount) captured item(s). Try sharing them again."
        )
    }

    /// Resolves optimized-or-default FSRS params from accumulated history and
    /// rebuilds the scheduler + widget reconciler. Call on launch and after
    /// each drain or optimization run.
    ///
    /// A transient `optimizationReviewLogs()` read failure must never be
    /// coerced into "0 eligible reviews": that would resolve to `.default`
    /// params and silently discard whatever optimized params (#27) were
    /// already live, reverting the scheduler and widget reconciler with no
    /// indication anything went wrong. On a read error this logs and returns
    /// early, leaving the existing `scheduler`/`widgetReconciler` untouched.
    func refreshScheduler() async {
        let rows: [OptimizationReviewLogRow]
        do {
            rows = try await cardStore.optimizationReviewLogs()
        } catch {
            CoreLog.scheduling.error(
                "refreshScheduler: failed to load review history — keeping existing scheduler: \(error)")
            return
        }
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
    ///
    /// Advances the sheet immediately — before any `await` — so the UI stays
    /// snappy. `.anghkooeyCardAccepted` is posted only after the card is
    /// actually persisted: `ReviewScreen` reloads its due queue on that
    /// notification, and reloading before the card exists is the #20 race.
    /// On a failed save the draft is never dropped: it's put back at the
    /// head of the queue (re-presented immediately if the queue is now
    /// idle) and the failure is surfaced via `errorPresenter`.
    func acceptDraft(question: String, answer: String) async {
        guard !isProcessingAccept else { return }
        isProcessingAccept = true
        defer { isProcessingAccept = false }
        guard let draft = presentedDraft else { return }
        advanceQueue()
        await persistAcceptedDraft(draft, question: question, answer: answer)
    }

    /// Convenience shim: accepts using the draft's original (unedited) Q/A.
    /// Kept so existing test call sites compile unchanged.
    func acceptDraft() async {
        guard let draft = presentedDraft else { return }
        await acceptDraft(question: draft.draft.question, answer: draft.draft.answer)
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

    /// Called by `DrainerBridge` when the drainer permanently drops an inbox
    /// item (OCR failure, oversize image, corrupt file — see ADR-0003 §9).
    /// By the time this fires the drainer has already deleted the item's
    /// files, so there is nothing left to retry: this only counts the drop
    /// (for the end-of-pass summary in `finishDrainPass()`) and logs the
    /// underlying error immediately, per item, for diagnosis.
    func recordDrainFailure(_ error: Error) {
        failedDrainItemCount += 1
        CoreLog.captureInbox.error("inbox item dropped: \(error.localizedDescription, privacy: .public)")
    }

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
            let fallback = CardDraft(question: resolvedText, answer: "")
            pendingDrafts.append(IdentifiedDraft(draft: fallback))
            if presentedDraft == nil { advanceQueue() }
        }
    }

    // MARK: Private

    /// Does the actual persistence work for `acceptDraft(question:answer:)`,
    /// pinned to the exact `draft` the caller already resolved so a retry
    /// (below) re-attempts the same draft even if `presentedDraft`/
    /// `pendingDrafts` have since changed.
    private func persistAcceptedDraft(_ draft: IdentifiedDraft, question: String, answer: String) async {
        do {
            _ = try await cardStore.create(
                question: question,
                answer: answer,
                sourceSpan: draft.draft.sourceSpan,
                tags: draft.draft.proposedTags,
                now: .now
            )
            do {
                try await widgetReconciler.rewriteSnapshot()
            } catch {
                CoreLog.persistence.error("acceptDraft: widget snapshot refresh failed: \(error)")
            }
            NotificationCenter.default.post(name: .anghkooeyCardAccepted, object: nil)
            // A prior failed accept may have left a retry-able toast on screen
            // (see the catch branch below). Dismiss it now: its stale retry
            // closure still targets this same draft/question/answer, and if
            // left live the user could tap it after this success and create a
            // duplicate card for content that's already persisted.
            errorPresenter.dismiss()
        } catch {
            CoreLog.persistence.error("acceptDraft: card creation failed: \(error)")
            pendingDrafts.insert(draft, at: 0)
            if presentedDraft == nil { advanceQueue() }
            errorPresenter.present(
                "Couldn't save the card — try again.",
                retry: { [weak self] in
                    guard let self else { return }
                    await self.retryAcceptDraft(draft, question: question, answer: answer)
                }
            )
        }
    }

    /// Removes `draft` from wherever the failure path parked it (either
    /// re-presented or sitting at the head of `pendingDrafts`), then
    /// re-attempts persistence. Removing first means a repeat failure
    /// re-enqueues cleanly via `persistAcceptedDraft`'s own catch block
    /// instead of leaving a duplicate behind.
    private func retryAcceptDraft(_ draft: IdentifiedDraft, question: String, answer: String) async {
        if presentedDraft?.id == draft.id {
            advanceQueue()
        } else {
            pendingDrafts.removeAll { $0.id == draft.id }
        }
        await persistAcceptedDraft(draft, question: question, answer: answer)
    }

    private func advanceQueue() {
        // A failure/retry path can call advanceQueue() again before the
        // in-flight sheet ever reached onAppear (cardReviewSheetDidAppear),
        // leaving reviewSheetSignpostState still open. End it here first so
        // repeated failures don't leak an ever-growing set of unclosed
        // "card-review-sheet-ready" intervals.
        if let state = reviewSheetSignpostState {
            CoreLog.poiSignposter.endInterval("card-review-sheet-ready", state)
            reviewSheetSignpostState = nil
        }

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
