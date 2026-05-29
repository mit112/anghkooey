import Foundation

public enum ClozeMarkupParser {
    public static let maxDeletions = 20

    // MARK: - Parse

    public static func parse(_ markup: String) throws -> ClozeTemplate {
        var deletions: [ClozeDeletion] = []
        var seenIndices: Set<Int> = []

        let chars = Array(markup.unicodeScalars)
        let count = chars.count
        var i = 0
        var insideMarker = false

        while i < count {
            // Look for '{{'
            if chars[i] == "{" && i + 1 < count && chars[i + 1] == "{" {
                if insideMarker {
                    throw ClozeParseError.nestedMarker
                }
                insideMarker = true
                i += 2 // skip '{{'

                // Scan for '}}'
                var contentScalars: [Unicode.Scalar] = []
                var found = false
                while i < count {
                    if chars[i] == "}" && i + 1 < count && chars[i + 1] == "}" {
                        i += 2 // skip '}}'
                        found = true
                        break
                    }
                    // Check for nested '{{'
                    if chars[i] == "{" && i + 1 < count && chars[i + 1] == "{" {
                        throw ClozeParseError.nestedMarker
                    }
                    contentScalars.append(chars[i])
                    i += 1
                }
                if !found {
                    throw ClozeParseError.unclosedMarker
                }
                insideMarker = false

                let content = String(String.UnicodeScalarView(contentScalars))
                if let deletion = try parseMarkerContent(content) {
                    if deletion.index <= 0 {
                        throw ClozeParseError.nonPositiveIndex(deletion.index)
                    }
                    if seenIndices.contains(deletion.index) {
                        throw ClozeParseError.duplicateIndex(deletion.index)
                    }
                    seenIndices.insert(deletion.index)
                    deletions.append(deletion)
                }
            } else {
                i += 1
            }
        }

        if deletions.isEmpty {
            throw ClozeParseError.noDeletions
        }
        if deletions.count > maxDeletions {
            throw ClozeParseError.tooManyDeletions(count: deletions.count, max: maxDeletions)
        }

        // Sort deletions by index for consistent ordering
        let sorted = deletions.sorted { $0.index < $1.index }
        return ClozeTemplate(markup: markup, deletions: sorted)
    }

    // MARK: - Render

    public static func renderQuestion(_ template: ClozeTemplate, index: Int) -> String {
        renderMarkup(template.markup, targetIndex: index, showTarget: false)
    }

    public static func renderAnswer(_ template: ClozeTemplate, index: Int) -> String {
        guard let deletion = template.deletions.first(where: { $0.index == index }) else {
            return ""
        }
        return deletion.answer
    }

    // MARK: - Private helpers

    /// Returns `nil` if the marker doesn't match the `cN::answer` grammar (treat as plain text).
    /// Throws only for structurally invalid `cN` markers (empty answer, non-positive index, etc.).
    private static func parseMarkerContent(_ content: String) throws -> ClozeDeletion? {
        // Split on '::' — first: cN, second: answer, optional third: hint
        var parts: [String] = []
        var current = ""
        let chars = Array(content)
        var i = 0
        while i < chars.count {
            if chars[i] == ":" && i + 1 < chars.count && chars[i + 1] == ":" {
                parts.append(current)
                current = ""
                i += 2
            } else {
                current.append(chars[i])
                i += 1
            }
        }
        parts.append(current)

        // Not enough parts — not a cN marker; skip silently.
        guard parts.count >= 2 else { return nil }

        let label = parts[0] // e.g. "c1"
        let answer = parts[1]
        let hint: String? = parts.count >= 3 ? parts[2] : nil

        // Label doesn't start with 'c' or has non-integer suffix — skip silently (plain text).
        guard label.hasPrefix("c") else { return nil }
        let indexStr = String(label.dropFirst())
        guard let index = Int(indexStr) else { return nil }

        if index <= 0 {
            throw ClozeParseError.nonPositiveIndex(index)
        }

        if answer.isEmpty {
            throw ClozeParseError.emptyAnswer(index: index)
        }

        return ClozeDeletion(index: index, answer: answer, hint: hint)
    }

    private static func renderMarkup(_ markup: String, targetIndex: Int, showTarget: Bool) -> String {
        var result = ""
        let chars = Array(markup.unicodeScalars)
        let count = chars.count
        var i = 0

        while i < count {
            if chars[i] == "{" && i + 1 < count && chars[i + 1] == "{" {
                i += 2 // skip '{{'
                // Scan for '}}'
                var contentScalars: [Unicode.Scalar] = []
                while i < count {
                    if chars[i] == "}" && i + 1 < count && chars[i + 1] == "}" {
                        i += 2
                        break
                    }
                    contentScalars.append(chars[i])
                    i += 1
                }
                let content = String(String.UnicodeScalarView(contentScalars))
                // Parse label and answer
                if let (index, answer) = extractIndexAndAnswer(from: content) {
                    if index == targetIndex {
                        result += "[…]"
                    } else {
                        result += answer
                    }
                }
            } else {
                result.unicodeScalars.append(chars[i])
                i += 1
            }
        }

        return result
    }

    private static func extractIndexAndAnswer(from content: String) -> (Int, String)? {
        var parts: [String] = []
        var current = ""
        let chars = Array(content)
        var i = 0
        while i < chars.count {
            if chars[i] == ":" && i + 1 < chars.count && chars[i + 1] == ":" {
                parts.append(current)
                current = ""
                i += 2
            } else {
                current.append(chars[i])
                i += 1
            }
        }
        parts.append(current)

        guard parts.count >= 2 else { return nil }
        let label = parts[0]
        let answer = parts[1]
        guard label.hasPrefix("c"), let index = Int(label.dropFirst()) else { return nil }
        return (index, answer)
    }
}
