import Testing
import CoreGraphics
@testable import AnghkooeyIntelligence

@Suite("MockOCRService")
struct MockOCRServiceTests {

    private func blankImage() -> CGImage {
        let ctx = CGContext(data: nil, width: 1, height: 1,
                            bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    @Test("returns configured text")
    func returnsText() async throws {
        let svc = MockOCRService(result: .success("Hello world"))
        let text = try await svc.recognizeText(in: blankImage())
        #expect(text == "Hello world")
    }

    @Test("throws configured error")
    func throwsError() async {
        struct OCRFail: Error {}
        let svc = MockOCRService(result: .failure(OCRFail()))
        await #expect(throws: OCRFail.self) {
            _ = try await svc.recognizeText(in: blankImage())
        }
    }

    @Test("cleans up hyphens at line breaks")
    func hyphenCleanup() async throws {
        let svc = MockOCRService(result: .success("hyphen-\nated word"))
        let text = try await svc.recognizeText(in: blankImage())
        #expect(text == "hyphenated word")
    }
}
