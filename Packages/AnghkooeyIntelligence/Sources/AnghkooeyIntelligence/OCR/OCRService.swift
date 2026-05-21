import CoreGraphics

/// Contract for on-device optical character recognition.
///
/// Takes `CGImage` (not `UIImage`) to avoid importing UIKit.
/// The UI layer extracts `uiImage.cgImage` before calling.
public protocol OCRService: Sendable {
    /// Recognise text in `image` and return cleaned-up plain text.
    ///
    /// - Throws: `OCRError` on recognition failure.
    func recognizeText(in image: CGImage) async throws -> String
}

/// Errors thrown by `OCRService.recognizeText(in:)`.
public enum OCRError: Error, Sendable {
    case recognitionFailed(underlying: Error)
    case noTextFound
}
