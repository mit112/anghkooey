import Testing
@testable import AnghkooeyIntelligence

@Suite struct ClozeAuthoringServiceTests {
    @Test func mockYieldsConfiguredDrafts() async throws {
        let mock = MockClozeAuthoringService()
        mock.stubbed = [ClozeDraft(markedText: "The {{c1::a}} is {{c2::b}}", proposedTags: ["x"])]
        var got: [ClozeDraft] = []
        for try await d in try await mock.generateClozeDrafts(from: "passage") { got.append(d) }
        #expect(got.count == 1)
        #expect(got.first?.markedText.contains("{{c1::a}}") == true)
    }

    @Test func emptyInputThrows() async {
        let mock = MockClozeAuthoringService()
        await #expect(throws: AuthoringError.self) {
            _ = try await mock.generateClozeDrafts(from: "   ")
        }
    }
}
