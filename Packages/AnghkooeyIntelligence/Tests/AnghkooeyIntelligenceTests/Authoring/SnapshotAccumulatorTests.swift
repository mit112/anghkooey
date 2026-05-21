import Testing
@testable import AnghkooeyIntelligence

@Suite("SnapshotAccumulator")
struct SnapshotAccumulatorTests {

    @Test("partial draft with only question does not emit")
    func partialQuestionOnly() {
        var acc = SnapshotAccumulator()
        let result = acc.update([.init(question: "Q", answer: "", proposedTags: [], sourceSpan: nil)])
        #expect(result.isEmpty)
    }

    @Test("partial draft with only answer does not emit")
    func partialAnswerOnly() {
        var acc = SnapshotAccumulator()
        let result = acc.update([.init(question: "", answer: "A", proposedTags: [], sourceSpan: nil)])
        #expect(result.isEmpty)
    }

    @Test("completed draft emits exactly once")
    func emitsOnce() {
        var acc = SnapshotAccumulator()
        let partial = SnapshotAccumulator.PartialDraft(
            question: "Q", answer: "A", proposedTags: ["t"], sourceSpan: "span")
        let first = acc.update([partial])
        let second = acc.update([partial])   // same snapshot again
        #expect(first.count == 1)
        #expect(first[0] == CardDraft(question: "Q", answer: "A",
                                      proposedTags: ["t"], sourceSpan: "span"))
        #expect(second.isEmpty)
    }

    @Test("second draft becomes available in later snapshot")
    func secondDraftLater() {
        var acc = SnapshotAccumulator()
        let d1 = SnapshotAccumulator.PartialDraft(question: "Q1", answer: "A1",
                                                   proposedTags: [], sourceSpan: nil)
        let d2 = SnapshotAccumulator.PartialDraft(question: "Q2", answer: "A2",
                                                   proposedTags: [], sourceSpan: nil)
        let first = acc.update([d1, .init(question: "Q2", answer: "", proposedTags: [], sourceSpan: nil)])
        let second = acc.update([d1, d2])
        #expect(first.count == 1)
        #expect(first[0].question == "Q1")
        #expect(second.count == 1)
        #expect(second[0].question == "Q2")
    }

    @Test("two drafts complete in one snapshot both emitted")
    func twoCompletionsOneUpdate() {
        var acc = SnapshotAccumulator()
        let partials = [
            SnapshotAccumulator.PartialDraft(question: "Q1", answer: "A1", proposedTags: [], sourceSpan: nil),
            SnapshotAccumulator.PartialDraft(question: "Q2", answer: "A2", proposedTags: [], sourceSpan: nil)
        ]
        let result = acc.update(partials)
        #expect(result.count == 2)
        #expect(result[0].question == "Q1")
        #expect(result[1].question == "Q2")
    }

    @Test("empty snapshot produces no output")
    func emptySnapshot() {
        var acc = SnapshotAccumulator()
        #expect(acc.update([]).isEmpty)
    }
}
