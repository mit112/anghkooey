import CoreGraphics

/// Deterministic test double for `OCRService`.
public struct MockOCRService: OCRService {
    private let result: Result<String, Error>

    public init(result: Result<String, Error>) {
        self.result = result
    }

    public func recognizeText(in image: CGImage) async throws -> String {
        let raw = try result.get()
        return ocrCleanup(raw)
    }
}
