import Foundation
import Observation
import UIKit

struct ClipboardOffer: Equatable {
    let text: String
}

/// Seam over `UIPasteboard.general` so the coordinator is testable and so
/// production call sites can be reasoned about without touching the real
/// pasteboard. `hasStrings` and `changeCount` are readable without
/// triggering iOS's paste-notification prompt; `string` is only read on
/// explicit user action (accept).
@MainActor
protocol PasteboardReading {
    var hasStrings: Bool { get }
    var changeCount: Int { get }
    var string: String? { get }
}

@MainActor
final class SystemPasteboard: PasteboardReading {
    var hasStrings: Bool { UIPasteboard.general.hasStrings }
    var changeCount: Int { UIPasteboard.general.changeCount }
    var string: String? { UIPasteboard.general.string }
}

/// Tracks the last pasteboard `changeCount` that was already offered or
/// dismissed, so the coordinator doesn't re-offer the same clipboard
/// content on every scene activation.
@MainActor
protocol LastHandledChangeCountStore: AnyObject {
    var lastHandledChangeCount: Int? { get set }
}

@MainActor
final class InMemoryLastHandledChangeCountStore: LastHandledChangeCountStore {
    var lastHandledChangeCount: Int?
}

@MainActor
final class UserDefaultsLastHandledChangeCountStore: LastHandledChangeCountStore {
    private let key = "anghkooey.clipboard.lastHandledChangeCount"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var lastHandledChangeCount: Int? {
        get {
            defaults.object(forKey: key) == nil ? nil : defaults.integer(forKey: key)
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

@Observable
@MainActor
final class ClipboardCaptureCoordinator {

    private(set) var pendingOffer: ClipboardOffer?
    var onRoute: ((String) -> Void)?

    private let pasteboard: any PasteboardReading
    private let store: any LastHandledChangeCountStore

    init(
        pasteboard: any PasteboardReading = SystemPasteboard(),
        store: any LastHandledChangeCountStore = UserDefaultsLastHandledChangeCountStore()
    ) {
        self.pasteboard = pasteboard
        self.store = store
    }

    /// Non-prompting detection: checks `hasStrings`/`changeCount` without
    /// reading content. Actual content is read in `acceptOffer()` after an
    /// explicit user tap.
    func refreshOffer() {
        guard pasteboard.hasStrings else { pendingOffer = nil; return }
        guard store.lastHandledChangeCount != pasteboard.changeCount else { return }
        guard pendingOffer == nil else { return }
        pendingOffer = ClipboardOffer(text: "")
    }

    func acceptOffer() {
        guard pendingOffer != nil else { return }
        let text = pasteboard.string ?? ""
        guard !text.isEmpty else { pendingOffer = nil; return }
        onRoute?(text)
        store.lastHandledChangeCount = pasteboard.changeCount
        pendingOffer = nil
    }

    func dismissOffer() {
        guard pendingOffer != nil else { return }
        store.lastHandledChangeCount = pasteboard.changeCount
        pendingOffer = nil
    }
}
