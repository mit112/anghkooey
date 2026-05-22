import Testing
@testable import AnghkooeyIntelligence

@Suite("MockMnemonicService — Lane M")
struct MockMnemonicServiceTests {

    @Test("returns configured mnemonic on happy path")
    func happyPath_returnsFixedMnemonic() async throws {
        let service = MockMnemonicService(mnemonic: "Think of a flamingo balancing.")

        let result = try await service.generateMnemonic(
            question: "What is the capital of France?",
            answer: "Paris"
        )

        #expect(result == "Think of a flamingo balancing.")
    }

    @Test("availability reflects configured value")
    func availabilityMatchesConfiguration() async {
        let service = MockMnemonicService(
            availability: .unavailable(reason: .deviceNotEligible)
        )
        let avail = await service.availability
        #expect(avail == .unavailable(reason: .deviceNotEligible))
    }

    @Test("throws unavailable when device is not eligible")
    func throwsUnavailable_whenDeviceNotEligible() async {
        let service = MockMnemonicService(
            availability: .unavailable(reason: .deviceNotEligible)
        )

        await #expect(throws: AuthoringError.unavailable(reason: .deviceNotEligible)) {
            _ = try await service.generateMnemonic(question: "Q", answer: "A")
        }
    }

    @Test("propagates injected error")
    func propagatesInjectedError() async {
        struct TestError: Error {}
        let service = MockMnemonicService(error: TestError())

        await #expect(throws: (any Error).self) {
            _ = try await service.generateMnemonic(question: "Q", answer: "A")
        }
    }
}
