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
    func unfreeze(now: Date = .now) async throws {
        guard let start = storage.frozenSince else { return }
        let elapsed = now.timeIntervalSince(start)
        let days = max(0, Int(elapsed / 86_400))
        try await cardStore.shiftAllDueDates(byDays: days)
        storage.frozenSince = nil
    }
}
