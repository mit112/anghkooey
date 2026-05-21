import CoreGraphics
import Foundation
import ImageIO
import AnghkooeyCore

/// Adapts `LiveOCRService` (which takes `CGImage`) to `OCRServiceProtocol` (which takes `Data`).
///
/// Lives in AnghkooeyIntelligence to avoid inverting the module dependency DAG:
/// AnghkooeyCore must not import AnghkooeyIntelligence.
public struct LiveOCRServiceDataAdapter: OCRServiceProtocol {

    private let inner: LiveOCRService

    public init(inner: LiveOCRService = LiveOCRService()) {
        self.inner = inner
    }

    public func recognizeText(inImageData data: Data) async throws -> String {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw OCRError.recognitionFailed(
                underlying: AdapterError.invalidImageData
            )
        }
        return try await inner.recognizeText(in: cgImage)
    }
}

private enum AdapterError: Error {
    case invalidImageData
}
