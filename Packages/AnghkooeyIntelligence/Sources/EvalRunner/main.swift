import ArgumentParser
import AnghkooeyIntelligence
import Foundation

struct EvalRunner: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "EvalRunner",
        abstract: "Run the AnghkooeyIntelligence eval harness against live model output."
    )

    @Flag(name: .long, help: "Overwrite eval-fixtures.json with new golden output.")
    var updateGoldens = false

    @Option(name: .long, help: "Path to eval-fixtures.json. Defaults to repo-relative path.")
    var fixtures: String = "Packages/AnghkooeyIntelligence/Tests/AnghkooeyIntelligenceTests/Fixtures/eval-fixtures.json"

    mutating func run() async throws {
        let fixturesURL = URL(fileURLWithPath: fixtures,
                              relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let data = try Data(contentsOf: fixturesURL)
        let evalFixtures = try JSONDecoder().decode([EvalFixture].self, from: data)

        let service = LiveCardAuthoringService()
        let avail = await service.availability
        guard case .available = avail else {
            print("❌ Model unavailable: \(avail). Run on macOS 26 with Apple Intelligence enabled.")
            throw ExitCode.failure
        }

        var passCount = 0
        var updatedFixtures: [EvalFixture] = []

        for fixture in evalFixtures {
            print("\n[\(fixture.id)] passage: \(fixture.passage.prefix(60))…")
            var collectedDrafts: [CardDraft] = []
            let stream = try await service.generateDrafts(from: fixture.passage)
            for try await draft in stream { collectedDrafts.append(draft) }

            let passes = RubricScorer.inputPasses(drafts: collectedDrafts, passage: fixture.passage)
            print("  Generated \(collectedDrafts.count) card(s). Input pass: \(passes ? "✓" : "✗")")

            for (i, draft) in collectedDrafts.enumerated() {
                let r = RubricScorer.score(draft: draft, passage: fixture.passage)
                let mark = r.cardPasses ? "✓" : "✗"
                print("  [\(i+1)] \(mark) atomic:\(r.atomic) specific:\(r.specific) grounded:\(r.groundednessPass) Q≠A:\(r.qNotA)")
                print("       Q: \(draft.question)")
            }

            if passes { passCount += 1 }
            var updated = fixture
            updated.goldenDrafts = collectedDrafts
            updatedFixtures.append(updated)
        }

        let total = evalFixtures.count
        let rate = Double(passCount) / Double(total) * 100
        print("\n=== Eval complete: \(passCount)/\(total) inputs passed (\(String(format: "%.1f", rate))%) ===")

        if updateGoldens {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let newData = try encoder.encode(updatedFixtures)
            try newData.write(to: fixturesURL)
            print("✓ Updated \(fixturesURL.path)")
        }

        if rate < 80.0 {
            print("❌ Pass rate \(String(format: "%.1f", rate))% is below 80% threshold.")
            throw ExitCode.failure
        }
    }
}

// Entry point — required in main.swift; @main attribute is only used in non-main.swift files.
EvalRunner.main()
