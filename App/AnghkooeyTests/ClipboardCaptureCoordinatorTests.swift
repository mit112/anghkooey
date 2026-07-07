import Testing
import Foundation
@testable import Anghkooey

@MainActor
final class MockPasteboard: PasteboardReading {
    var hasStrings: Bool
    var changeCount: Int
    var string: String?

    init(hasStrings: Bool = true, changeCount: Int = 1, string: String? = nil) {
        self.hasStrings = hasStrings
        self.changeCount = changeCount
        self.string = string
    }
}

@Suite("Clipboard capture coordinator")
@MainActor
struct ClipboardCaptureCoordinatorTests {

    private func makeCoordinator(
        hasStrings: Bool = true,
        changeCount: Int = 1,
        string: String? = nil
    ) -> (ClipboardCaptureCoordinator, MockPasteboard, InMemoryLastHandledChangeCountStore) {
        let pasteboard = MockPasteboard(hasStrings: hasStrings, changeCount: changeCount, string: string)
        let store = InMemoryLastHandledChangeCountStore()
        let coord = ClipboardCaptureCoordinator(pasteboard: pasteboard, store: store)
        return (coord, pasteboard, store)
    }

    @Test("dismiss suppresses re-offer until changeCount bumps")
    func dismissSuppressesUntilChangeCountBumps() {
        let (coord, pasteboard, _) = makeCoordinator(hasStrings: true, changeCount: 1)

        coord.refreshOffer()
        #expect(coord.pendingOffer != nil)

        coord.dismissOffer()
        #expect(coord.pendingOffer == nil)

        coord.refreshOffer()
        #expect(coord.pendingOffer == nil) // suppressed: same changeCount

        pasteboard.changeCount = 2
        coord.refreshOffer()
        #expect(coord.pendingOffer != nil) // genuine change: re-offers
    }

    @Test("accept suppresses re-offer until changeCount bumps")
    func acceptSuppressesUntilChangeCountBumps() {
        let (coord, pasteboard, _) = makeCoordinator(hasStrings: true, changeCount: 1, string: "hello")
        var routed: String?
        coord.onRoute = { routed = $0 }

        coord.refreshOffer()
        #expect(coord.pendingOffer != nil)

        coord.acceptOffer()
        #expect(routed == "hello")
        #expect(coord.pendingOffer == nil)

        coord.refreshOffer()
        #expect(coord.pendingOffer == nil) // suppressed: same changeCount

        pasteboard.changeCount = 2
        coord.refreshOffer()
        #expect(coord.pendingOffer != nil) // genuine change: re-offers
    }

    @Test("no strings on the pasteboard clears any pending offer")
    func noStringsClearsOffer() {
        let (coord, _, _) = makeCoordinator(hasStrings: false)

        coord.refreshOffer()
        #expect(coord.pendingOffer == nil)
    }
}
