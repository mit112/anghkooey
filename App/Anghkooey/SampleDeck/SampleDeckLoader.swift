import Foundation
import AnghkooeyCore

/// Loads the bundled starter deck so first-run users have something to review immediately.
struct SampleDeckLoader {
    struct Entry: Decodable { let question: String; let answer: String; let tags: [String] }

    let store: any CardStoreProtocol

    // Production: reads SampleDeck.json from main bundle.
    // Tests: pass jsonData directly to avoid bundle dependency.
    private let jsonData: Data?

    init(store: any CardStoreProtocol, jsonData: Data? = nil) {
        self.store = store
        self.jsonData = jsonData
    }

    @discardableResult
    func load(now: Date) async throws -> Int {
        let data: Data
        if let injected = jsonData {
            data = injected
        } else {
            guard let url = Bundle.main.url(forResource: "SampleDeck", withExtension: "json") else { return 0 }
            data = try Data(contentsOf: url)
        }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        for e in entries {
            _ = try await store.create(question: e.question, answer: e.answer,
                                       sourceSpan: "sample", tags: e.tags, now: now)
        }
        return entries.count
    }
}
