import Foundation
import Observation
import AnghkooeyCore

/// Storage seam so tests can inject `InMemoryFreezeStorage` without UserDefaults.
@MainActor
public protocol FreezeStorage: AnyObject {
    var frozenSince: Date? { get set }
}

/// Production storage backed by UserDefaults.
/// Hand-rolled because `@AppStorage` is a property wrapper for SwiftUI views,
/// not a value usable inside a non-View class.
@MainActor
final class UserDefaultsFreezeStorage: FreezeStorage {
    private let key = "anghkooey.freezeStartedAt"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var frozenSince: Date? {
        get {
            let raw = defaults.double(forKey: key)
            return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

/// User-toggled "I'm away" state. When frozen, records the start time. On
/// unfreeze, shifts every card's `dueAt` forward by the elapsed integer days
/// so the user returns with zero overdue debt.
@Observable
@MainActor
final class FreezeController {

    private let cardStore: any CardStoreProtocol
    private let storage: any FreezeStorage

    /// Reentrancy guard for `unfreeze()`. The Settings "I'm away" toggle
    /// invokes `unfreeze()` from a `Task`-wrapped button action, and the
    /// method suspends mid-body on `cardStore.shiftAllDueDates`. Without this
    /// guard, a rapid double-toggle-off within that await window would let a
    /// second call also observe `storage.frozenSince != nil` and shift the
    /// deck a second time, sliding every card forward by `2 × away-days`
    /// instead of once (#96). Mirrors `AppState.acceptDraft`'s
    /// `isProcessingAccept` / `AppState.drain`'s `isDraining`.
    private var isUnfreezing = false

    init(cardStore: any CardStoreProtocol, storage: any FreezeStorage) {
        self.cardStore = cardStore
        self.storage = storage
    }

    var isFrozen: Bool { storage.frozenSince != nil }

    var frozenSince: Date? { storage.frozenSince }

    func freeze(now: Date = .now) {
        storage.frozenSince = now
    }

    /// Shifts every card's due date forward by `floor(elapsed / 86_400)` days
    /// and clears the frozen state. No-op if not currently frozen.
    ///
    /// The shift is `elapsed seconds / 86,400`, rounded DOWN — a partial day
    /// away never rounds up to a full day of grace. For example, freezing
    /// Friday 6pm and unfreezing Sunday 10am is 40 elapsed hours, which
    /// shifts by 1 day (not 2); a freeze under 24h elapsed shifts by 0 days.
    /// This is intentional and conservative: a brief freeze shouldn't grant a
    /// full day of slack it didn't earn (#48).
    func unfreeze(now: Date = .now) async throws {
        guard !isUnfreezing, let start = storage.frozenSince else { return }
        isUnfreezing = true
        defer { isUnfreezing = false }
        let elapsed = now.timeIntervalSince(start)
        let days = max(0, Int(elapsed / 86_400))
        try await cardStore.shiftAllDueDates(byDays: days)
        // Compare-and-clear: only clear the freeze we actually processed. If
        // `freeze()` ran during the `await` above (a rapid toggle-off→on
        // within the shift window), it wrote a NEW `frozenSince`; clearing
        // unconditionally here would silently delete that fresh freeze
        // period. `isUnfreezing` blocks a concurrent *unfreeze* but not a
        // concurrent *freeze* (which is intentionally always allowed), so
        // this guard is the one that protects the re-freeze.
        if storage.frozenSince == start {
            storage.frozenSince = nil
        }
    }
}
