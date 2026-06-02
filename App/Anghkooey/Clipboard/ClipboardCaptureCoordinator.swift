import Foundation
import Observation
import CryptoKit
import UIKit

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

    func consider(clipboardText: String) {
        let trimmed = clipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minLength else { return }
        let hash = Self.hash(for: clipboardText)
        guard !offerStore.offeredHashes.contains(hash) else { return }
        pendingOffer = ClipboardOffer(text: clipboardText)
    }

    /// Non-prompting detection: checks `hasStrings` without reading content.
    /// Actual content is read in `acceptOffer()` after explicit user tap.
    func refreshOffer() {
        guard UIPasteboard.general.hasStrings else { pendingOffer = nil; return }
        guard pendingOffer == nil else { return }
        pendingOffer = ClipboardOffer(text: "")
    }

    func acceptOffer() {
        guard let offer = pendingOffer else { return }
        // If consider() stored the text directly, use it; otherwise read from pasteboard now (user action).
        let text = offer.text.isEmpty ? (UIPasteboard.general.string ?? "") : offer.text
        guard !text.isEmpty else { pendingOffer = nil; return }
        onRoute?(text)
        offerStore.offeredHashes.append(Self.hash(for: text))
        while offerStore.offeredHashes.count > ringCapacity {
            offerStore.offeredHashes.removeFirst()
        }
        pendingOffer = nil
    }

    func dismissOffer() {
        guard let offer = pendingOffer else { return }
        offerStore.offeredHashes.append(Self.hash(for: offer.text))
        while offerStore.offeredHashes.count > ringCapacity {
            offerStore.offeredHashes.removeFirst()
        }
        pendingOffer = nil
    }

    static func hash(for text: String) -> String {
        let norm = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digest = SHA256.hash(data: Data(norm.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
