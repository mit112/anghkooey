import Testing
@testable import AnghkooeyIntelligence

@Suite("MockCardAuthoringService")
struct MockCardAuthoringServiceTests {

    @Test("empty input throws AuthoringError.emptyInput")
    func emptyInput() async throws {
        let svc = MockCardAuthoringService()
        await #expect(throws: AuthoringError.emptyInput) {
            _ = try await svc.generateDrafts(from: "   ")
        }
    }

    @Test("availability: available returns .available")
    func availabilityAvailable() async {
        let svc = MockCardAuthoringService()
        let avail = await svc.availability
        #expect(avail == .available)
    }

    @Test("availability: unavailable(deviceNotEligible) surfaces correctly")
    func availabilityDeviceNotEligible() async throws {
        let svc = MockCardAuthoringService(
            availability: .unavailable(reason: .deviceNotEligible))
        await #expect(throws: AuthoringError.unavailable(reason: .deviceNotEligible)) {
            _ = try await svc.generateDrafts(from: "some text")
        }
    }

    @Test("availability: unavailable(appleIntelligenceNotEnabled) surfaces correctly")
    func availabilityNotEnabled() async throws {
        let svc = MockCardAuthoringService(
            availability: .unavailable(reason: .appleIntelligenceNotEnabled))
        await #expect(throws: AuthoringError.unavailable(reason: .appleIntelligenceNotEnabled)) {
            _ = try await svc.generateDrafts(from: "some text")
        }
    }

    @Test("availability: unavailable(modelNotReady) surfaces correctly")
    func availabilityModelNotReady() async throws {
        let svc = MockCardAuthoringService(
            availability: .unavailable(reason: .modelNotReady))
        await #expect(throws: AuthoringError.unavailable(reason: .modelNotReady)) {
            _ = try await svc.generateDrafts(from: "some text")
        }
    }

    @Test("emits configured drafts in order then finishes")
    func emitsDraftsInOrder() async throws {
        let expected = [
            CardDraft(question: "Q1", answer: "A1"),
            CardDraft(question: "Q2", answer: "A2")
        ]
        let svc = MockCardAuthoringService(drafts: expected)
        let stream = try await svc.generateDrafts(from: "passage")
        var collected: [CardDraft] = []
        for try await draft in stream { collected.append(draft) }
        #expect(collected == expected)
    }

    @Test("generationFailed wraps the underlying error")
    func generationFailedWraps() async throws {
        struct TestError: Error, Equatable {}
        let svc = MockCardAuthoringService(error: TestError())
        do {
            _ = try await svc.generateDrafts(from: "passage")
            Issue.record("Expected throw")
        } catch AuthoringError.generationFailed(let underlying) {
            #expect(underlying is TestError)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("cancellation terminates stream without error")
    func cancellationTerminates() async throws {
        let drafts = (1...10).map { CardDraft(question: "Q\($0)", answer: "A\($0)") }
        let svc = MockCardAuthoringService(drafts: drafts)
        let stream = try await svc.generateDrafts(from: "passage")
        let task = Task<Int, Error> {
            var count = 0
            for try await _ in stream { count += 1; if count == 2 { break } }
            return count
        }
        let count = try await task.value
        #expect(count == 2)
    }
}
