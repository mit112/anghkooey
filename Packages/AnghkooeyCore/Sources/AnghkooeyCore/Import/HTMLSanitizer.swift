import Foundation

enum HTMLSanitizer {

    // Process order: entities → audio tokens → HTML tags.
    static func process(_ input: String) -> String {
        var s = input
        s = decodeEntities(s)
        s = stripAudioTokens(s)
        s = stripTags(s)
        return s
    }

    // MARK: - Stages

    private static func decodeEntities(_ s: String) -> String {
        var result = s
        let named: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " ")
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        result = result.replacing(
            /&#(\d+);/,
            with: { match in
                let value = Int(match.output.1)!
                return String(Unicode.Scalar(value)!).description
            }
        )
        return result
    }

    private static func stripAudioTokens(_ s: String) -> String {
        s.replacing(/\[sound:[^\]]+\]/, with: { _ in "" })
    }

    private static func stripTags(_ s: String) -> String {
        s.replacing(/<[^>]*>/, with: { _ in "" })
    }
}
