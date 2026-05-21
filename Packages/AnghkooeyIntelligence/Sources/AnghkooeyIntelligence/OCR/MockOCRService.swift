import CoreGraphics

/// Deterministic test double for `OCRService`.
public struct MockOCRService: OCRService {
    private let result: Result<String, Error>

    public init(result: Result<String, Error>) {
        self.result = result
    }

    public func recognizeText(in image: CGImage) async throws -> String {
        let raw = try result.get()
        return Self.cleanup(raw)
    }

    /// Remove soft hyphens at line breaks (e.g. "hyphen-\nated" → "hyphenated").
    static func cleanup(_ text: String) -> String {
        text.replacingOccurrences(of: "-\n", with: "")
            .replacingOccurrences(of: "-\r\n", with: "")
    }
}
