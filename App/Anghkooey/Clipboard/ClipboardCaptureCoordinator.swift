import Foundation
import Observation
import CryptoKit

struct ClipboardOffer: Equatable {
    let text: String
}

@MainActor
protocol OfferHashStore: AnyObject {
    var offeredHashes: [String] { get set }
}

@MainActor
final class InMemoryOfferStore: OfferHashStore {
    var offeredHashes: [String] = []
}

@MainActor
final class UserDefaultsOfferStore: OfferHashStore {
    private let key = "anghkooey.clipboard.offeredHashes"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var offeredHashes: [String] {
        get { defaults.stringArray(forKey: key) ?? [] }
        set { defaults.set(newValue, forKey: key) }
    }
}

@Observable
@MainActor
final class ClipboardCaptureCoordinator {

    private(set) var pendingOffer: ClipboardOffer?
    var onRoute: ((String) -> Void)?

    private let offerStore: any OfferHashStore
    private let minLength: Int
    private let ringCapacity: Int

    init(offerStore: any OfferHashStore, minLength: Int = 20, ringCapacity: Int = 50) {
        self.offerStore = offerStore
        self.minLength = minLength
        self.ringCapacity = ringCapacity
    }

    func consider(clipboardText: String) { fatalError("Codex: implement") }
    func acceptOffer() { fatalError("Codex: implement") }
    func dismissOffer() { fatalError("Codex: implement") }

    static func hash(for text: String) -> String {
        let norm = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digest = SHA256.hash(data: Data(norm.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
