import Testing
@testable import AnghkooeyCore

struct SanitizerCase {
    let input: String
    let expected: String
}

extension SanitizerCase: CustomTestStringConvertible {
    var testDescription: String { "'\(input)' → '\(expected)'" }
}

let sanitizerCases: [SanitizerCase] = [
    // Entity decoded before tag stripped
    .init(input: "&lt;b&gt;bold&lt;/b&gt;", expected: "bold"),
    // Nested tags stripped
    .init(input: "<div><b>text</b></div>", expected: "text"),
    // Self-closing tag stripped
    .init(input: "line1<br/>line2", expected: "line1line2"),
    // Audio token stripped
    .init(input: "hello [sound:beep.mp3] world", expected: "hello  world"),
    // LaTeX passthrough — not stripped
    .init(input: "\\(x^2\\)", expected: "\\(x^2\\)"),
    // Ampersand entity
    .init(input: "A &amp; B", expected: "A & B"),
    // nbsp becomes space
    .init(input: "foo&nbsp;bar", expected: "foo bar"),
    // Numeric entity
    .init(input: "&#65;", expected: "A"),
]

@Suite("HTMLSanitizer")
struct HTMLSanitizerTests {

    @Test("strips and decodes", arguments: sanitizerCases)
    func sanitize(tc: SanitizerCase) {
        #expect(HTMLSanitizer.process(tc.input) == tc.expected)
    }
}
