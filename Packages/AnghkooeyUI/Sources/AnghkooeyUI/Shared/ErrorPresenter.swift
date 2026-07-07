import Foundation
import Observation
import SwiftUI

/// Shared error-surfacing primitive for AnghkooeyUI screens and view models.
///
/// Adoption is meant to be ≤3 lines per call site:
/// ```
/// // In a screen: @State private var errorPresenter = ErrorPresenter()
/// // Apply once at content root: .errorToast(errorPresenter)
/// // On failure (view or view-model): errorPresenter.present("Couldn't save.", retry: { await vm.retrySave() })
/// ```
///
/// For sheet contexts, give the sheet its own `ErrorPresenter` (and its own
/// `.errorToast(_:)`) so the toast renders above the sheet rather than being
/// clipped behind it by the presenting screen's presenter.
///
/// - Warning: Capture the retry closure's owner **weakly**. The presenter
///   holds the closure strongly until the next `present`, `dismiss`, or
///   `retry()` call, and the owner typically holds the presenter — capturing
///   `self` strongly creates a temporary retain cycle that lasts until
///   `autoDismiss` fires.
@MainActor
@Observable
public final class ErrorPresenter {

    /// The toast currently on screen, or `nil` when nothing is showing.
    public private(set) var toast: ErrorToast?

    private let autoDismiss: Duration
    private let sleep: @Sendable (Duration) async -> Void
    private let announce: @MainActor (String) -> Void

    private var retryAction: (() async -> Void)?
    // `nonisolated(unsafe)` so `deinit` (which runs nonisolated) can cancel it.
    // Required here: the `@Observable` macro's generated backing for this stored
    // property cannot be plain `nonisolated`. Safe: every other access is on the
    // MainActor and `deinit` runs with no other references left to race with.
    nonisolated(unsafe) private var dismissTask: Task<Void, Never>?

    /// - Parameters:
    ///   - autoDismiss: How long the toast stays on screen before it clears itself.
    ///   - sleep: Test seam for the auto-dismiss timer. Defaults to a real
    ///     `Task.sleep`; inject a controllable stand-in in tests so nothing
    ///     waits on real time. A custom `sleep` must observe cancellation for
    ///     `dismissTask?.cancel()` to take prompt effect — the default
    ///     `Task.sleep` already does.
    ///   - announce: Test seam for the accessibility announcement. Defaults
    ///     to posting a VoiceOver `AccessibilityNotification.Announcement`.
    public init(
        autoDismiss: Duration = .seconds(4),
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        announce: @escaping @MainActor (String) -> Void = { message in
            AccessibilityNotification.Announcement(message).post()
        }
    ) {
        self.autoDismiss = autoDismiss
        self.sleep = sleep
        self.announce = announce
    }

    deinit {
        dismissTask?.cancel()
    }

    /// Shows `message` as a toast, replacing any toast already on screen.
    /// Schedules an auto-dismiss after `autoDismiss`, cancelling any
    /// previously-scheduled one first.
    public func present(_ message: String, retry: (() async -> Void)? = nil) {
        dismissTask?.cancel()

        retryAction = retry
        toast = ErrorToast(message: message, hasRetry: retry != nil)
        announce(message)

        let sleep = sleep
        let duration = autoDismiss
        dismissTask = Task { @MainActor [weak self] in
            await sleep(duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Convenience overload forwarding `error.localizedDescription`.
    public func present(_ error: Error, retry: (() async -> Void)? = nil) {
        present(error.localizedDescription, retry: retry)
    }

    /// Dismisses the current toast, then runs its stored retry closure, if any.
    /// A no-op if the current (or last-shown) toast had no retry closure.
    public func retry() async {
        guard let retryAction else { return }
        dismiss()
        await retryAction()
    }

    /// Clears the toast and cancels any pending auto-dismiss.
    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        toast = nil
        retryAction = nil
    }
}
