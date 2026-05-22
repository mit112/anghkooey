import Testing
import Foundation
@testable import AnghkooeyIntelligence

@Suite("EvalFixtureGate — CI rubric gate (no model calls)")
struct EvalFixtureGateTests {

    static let fixtures: [EvalFixture] = {
        guard let url = Bundle.module.url(forResource: "eval-fixtures", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([EvalFixture].self, from: data)
        else { return [] }
        return loaded
    }()

    @Test("fixtures file loads and is non-empty")
    func fixturesLoad() {
        #expect(!EvalFixtureGateTests.fixtures.isEmpty)
    }

    @Test("every golden card in every fixture passes all four rubric criteria",
          arguments: EvalFixtureGateTests.fixtures)
    func goldenPassesRubric(fixture: EvalFixture) {
        for draft in fixture.goldenDrafts {
            let result = RubricScorer.score(draft: draft, passage: fixture.passage)
            #expect(result.atomic,
                    "[\(fixture.id)] atomicity failed for: \(draft.question)")
            #expect(result.specific,
                    "[\(fixture.id)] specificity failed for answer: \(draft.answer)")
            #expect(result.groundednessPass,
                    "[\(fixture.id)] groundedness failed for answer: \(draft.answer)")
            #expect(result.qNotA,
                    "[\(fixture.id)] Q≠A failed for: \(draft.question)")
        }
    }
}
