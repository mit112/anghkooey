import Testing
import Foundation
@testable import Anghkooey
import AnghkooeyCore
import AnghkooeyIntelligence
import AnghkooeyUI

@Suite("ReviewSession mnemonic — Lane M")
@MainActor
struct ReviewSessionMnemonicTests {

    private func makeSession(
        service: MockMnemonicService? = nil,
        store: MockCardStore = MockCardStore(),
        now: Date = Date(timeIntervalSinceReferenceDate: 0)
    ) -> ReviewSession {
        ReviewSession(
            store: store,
            scheduler: { MockFSRS6Engine() },
            clock: { now },
            mnemonicService: service
        )
    }

    private func seedCard(
        in store: MockCardStore,
        mnemonic: String? = nil,
        now: Date = Date(timeIntervalSinceReferenceDate: 0)
    ) async throws -> Card.Snapshot {
        let snap = try await store.create(
            question: "What is 2+2?",
            answer: "4",
            sourceSpan: nil,
            now: now
        )
        if let mnemonic {
            try await store.updateMnemonic(id: snap.id, mnemonic: mnemonic)
        }
        return snap
    }

    // MARK: isMnemonicAvailable

    @Test("isMnemonicAvailable is false when no service injected")
    func isMnemonicAvailable_falseWithNoService() {
        let session = makeSession(service: nil)
        #expect(session.isMnemonicAvailable == false)
    }

    @Test("isMnemonicAvailable is true when service injected")
    func isMnemonicAvailable_trueWithService() {
        let session = makeSession(service: MockMnemonicService())
        #expect(session.isMnemonicAvailable == true)
    }

    // MARK: loadDueQueue seeds mnemonic

    @Test("loadDueQueue seeds currentMnemonic from stored card mnemonic")
    func loadDueQueue_seedsCurrentMnemonic() async throws {
        let store = MockCardStore()
        _ = try await seedCard(in: store, mnemonic: "Remember the flamingo.")
        let session = makeSession(service: MockMnemonicService(), store: store)

        await session.loadDueQueue()

        #expect(session.currentMnemonic == "Remember the flamingo.")
    }

    @Test("loadDueQueue sets currentMnemonic to nil for card with no stored mnemonic")
    func loadDueQueue_nilMnemonic_forNewCard() async throws {
        let store = MockCardStore()
        _ = try await seedCard(in: store)
        let session = makeSession(service: MockMnemonicService(), store: store)

        await session.loadDueQueue()

        #expect(session.currentMnemonic == nil)
    }

    // MARK: generateMnemonic

    @Test("generateMnemonic sets currentMnemonic and persists via store")
    func generateMnemonic_setsCurrentMnemonicAndPersists() async throws {
        let store = MockCardStore()
        _ = try await seedCard(in: store)
        let service = MockMnemonicService(mnemonic: "Think of a golden bridge.")
        let session = makeSession(service: service, store: store)
        await session.loadDueQueue()

        await session.generateMnemonic()

        #expect(session.currentMnemonic == "Think of a golden bridge.")
        #expect(session.isMnemonicLoading == false)
        let all = try await store.allCards()
        let updated = try #require(all.first)
        #expect(updated.mnemonic == "Think of a golden bridge.")
    }

    @Test("generateMnemonic on error leaves currentMnemonic nil and resets loading flag")
    func generateMnemonic_onError_resetsState() async throws {
        struct GenerationError: Error {}
        let store = MockCardStore()
        _ = try await seedCard(in: store)
        let service = MockMnemonicService(error: GenerationError())
        let session = makeSession(service: service, store: store)
        await session.loadDueQueue()

        await session.generateMnemonic()

        #expect(session.currentMnemonic == nil)
        #expect(session.isMnemonicLoading == false)
    }

    // MARK: Card advance resets mnemonic state

    @Test("submit resets currentMnemonic to next card's stored mnemonic")
    func submit_resetsMnemonicToNextCard() async throws {
        let store = MockCardStore()
        let now = Date(timeIntervalSinceReferenceDate: 0)
        _ = try await store.create(question: "Q1", answer: "A1", sourceSpan: nil, now: now)
        let snap2 = try await store.create(question: "Q2", answer: "A2", sourceSpan: nil, now: now)
        try await store.updateMnemonic(id: snap2.id, mnemonic: "Next card mnemonic.")

        let session = makeSession(service: MockMnemonicService(), store: store)
        await session.loadDueQueue()
        await session.generateMnemonic()
        #expect(session.currentMnemonic == "Picture a golden gate.")

        session.revealAnswer()
        await session.submit(grade: .good)

        #expect(session.currentMnemonic == "Next card mnemonic.")
        #expect(session.isMnemonicLoading == false)
    }

    @Test("submit on last card clears currentMnemonic")
    func submit_onLastCard_clearsMnemonic() async throws {
        let store = MockCardStore()
        _ = try await seedCard(in: store, mnemonic: "A mnemonic.")
        let session = makeSession(service: MockMnemonicService(), store: store)
        await session.loadDueQueue()
        #expect(session.currentMnemonic == "A mnemonic.")

        session.revealAnswer()
        await session.submit(grade: .good)

        #expect(session.state == .empty)
        #expect(session.currentMnemonic == nil)
    }
}
