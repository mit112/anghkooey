import Foundation

/// Protocol used by `InboxDrainer` to run OCR on image inbox items.
///
/// Input is raw image data (typically HEIC written by the Share Extension).
/// Using `Data` rather than `CGImage` keeps `AnghkooeyCore` free of
/// `CoreGraphics` and avoids a circular dependency with `AnghkooeyIntelligence`
/// (which already depends on `AnghkooeyCore`).
///
/// For production, wire `AnghkooeyIntelligence.LiveOCRService` via a thin
/// adapter that converts `Data → CGImage` before forwarding to the Vision stack.
public protocol OCRServiceProtocol: Sendable {
    /// Recognise text in `imageData` and return cleaned-up plain text.
    ///
    /// - Throws: Any error from the underlying OCR implementation.
    func recognizeText(inImageData data: Data) async throws -> String
}
