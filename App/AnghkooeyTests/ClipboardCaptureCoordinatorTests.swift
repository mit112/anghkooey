import Testing
import Foundation
@testable import Anghkooey

@Suite("Clipboard capture coordinator")
@MainActor
struct ClipboardCaptureCoordinatorTests {

    private func makeCoordinator() -> (ClipboardCaptureCoordinator, InMemoryOfferStore) {
        let store = InMemoryOfferStore()
        let coord = ClipboardCaptureCoordinator(offerStore: store, minLength: 20, ringCapacity: 50)
        return (coord, store)
    }

    @Test("text below the minimum length produces no offer")
    func tooShortNoOffer() {
        let (coord, _) = makeCoordinator()
        coord.consider(clipboardText: "short")
        #expect(coord.pendingOffer == nil)
    }

    @Test("fresh long text produces an offer")
    func freshTextOffers() {
        let (coord, _) = makeCoordinator()
        coord.consider(clipboardText: "This is a sufficiently long clipboard string to offer.")
        #expect(coord.pendingOffer?.text == "This is a sufficiently long clipboard string to offer.")
    }

    @Test("the same text is not offered twice")
    func dedupSameText() {
        let (coord, _) = makeCoordinator()
        let text = "This is a sufficiently long clipboard string to offer."
        coord.consider(clipboardText: text)
        coord.dismissOffer() // marks offered
        coord.consider(clipboardText: text)
        #expect(coord.pendingOffer == nil)
    }

    @Test("normalization makes whitespace-only differences dedup")
    func dedupNormalized() {
        let (coord, _) = makeCoordinator()
        coord.consider(clipboardText: "This is a sufficiently long clipboard string to offer.")
        coord.dismissOffer()
        coord.consider(clipboardText: "  This is a sufficiently long clipboard string to offer.  ")
        #expect(coord.pendingOffer == nil)
    }

    @Test("accepting routes the text and clears the offer")
    func acceptRoutes() {
        let (coord, _) = makeCoordinator()
        var routed: String?
        coord.onRoute = { routed = $0 }
        coord.consider(clipboardText: "This is a sufficiently long clipboard string to offer.")
        coord.acceptOffer()
        #expect(routed == "This is a sufficiently long clipboard string to offer.")
        #expect(coord.pendingOffer == nil)
    }

    @Test("ring evicts oldest hash beyond capacity")
    func ringEviction() {
        let store = InMemoryOfferStore()
        let coord = ClipboardCaptureCoordinator(offerStore: store, minLength: 1, ringCapacity: 2)
        coord.consider(clipboardText: "alpha one two three"); coord.dismissOffer()
        coord.consider(clipboardText: "bravo one two three"); coord.dismissOffer()
        coord.consider(clipboardText: "charlie one two three"); coord.dismissOffer()
        // "alpha" hash should have been evicted; offering it again succeeds.
        coord.consider(clipboardText: "alpha one two three")
        #expect(coord.pendingOffer != nil)
    }
}
