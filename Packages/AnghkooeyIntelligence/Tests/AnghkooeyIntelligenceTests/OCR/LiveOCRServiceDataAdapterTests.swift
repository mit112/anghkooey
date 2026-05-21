import Foundation
import Testing
import AnghkooeyCore
@testable import AnghkooeyIntelligence

@Suite("LiveOCRServiceDataAdapter")
struct LiveOCRServiceDataAdapterTests {

    @Test("throws recognitionFailed for empty data")
    func throwsOnEmptyData() async throws {
        let adapter = LiveOCRServiceDataAdapter()
        await #expect(throws: (any Error).self) {
            try await adapter.recognizeText(inImageData: Data())
        }
    }

    @Test("throws recognitionFailed for non-image bytes")
    func throwsOnGarbageData() async throws {
        let garbage = Data([0xFF, 0xFE, 0x00, 0x01, 0xAB, 0xCD])
        let adapter = LiveOCRServiceDataAdapter()
        await #expect(throws: (any Error).self) {
            try await adapter.recognizeText(inImageData: garbage)
        }
    }

    @Test("thrown error is OCRError.recognitionFailed for invalid data")
    func errorTypeIsRecognitionFailed() async {
        let adapter = LiveOCRServiceDataAdapter()
        do {
            _ = try await adapter.recognizeText(inImageData: Data([0x00]))
            Issue.record("expected throw, got success")
        } catch let error as OCRError {
            guard case .recognitionFailed = error else {
                Issue.record("expected recognitionFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
