import Foundation

public enum ClozeMarkupParser {
    public static let maxDeletions = 20

    public static func parse(_ markup: String) throws -> ClozeTemplate {
        fatalError("Codex: implement")
    }

    public static func renderQuestion(_ template: ClozeTemplate, index: Int) -> String {
        fatalError("Codex: implement")
    }

    public static func renderAnswer(_ template: ClozeTemplate, index: Int) -> String {
        fatalError("Codex: implement")
    }
}
