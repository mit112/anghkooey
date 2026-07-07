#if os(iOS)
import Testing
import Foundation
@testable import AnghkooeyUI
import AnghkooeyCore

/// Regression coverage for #24: camera capture failures showed nothing (a
/// write-only `captureError` state nobody rendered) and whitespace-only OCR
/// output opened a blank draft.
///
/// `CameraCaptureHandler.run` is the capture → OCR → validate decision logic
/// extracted out of `CameraView.handleCapture()` so it's unit-testable
/// without a running view hierarchy — the camera itself can't run in the
/// simulator/CI, so these tests drive `MockCaptureSession` and a stub OCR
/// service instead.
@Suite("CameraCaptureHandler — #24 camera capture errors")
@MainActor
struct CameraCaptureHandlerTests {

    // MARK: - Test doubles

    private struct StubOCRService: OCRServiceProtocol {
        let result: Result<String, Error>

        init(returning text: String) { result = .success(text) }
        init(throwing error: Error) { result = .failure(error) }

        func recognizeText(inImageData data: Data) async throws -> String {
            try result.get()
        }
    }

    private enum StubError: Error { case boom }

    @MainActor
    private final class CaptureSpy {
        private(set) var captured: [String] = []
        func record(_ text: String) { captured.append(text) }
    }

    // MARK: - captureFrame() throws

    @Test("a thrown captureFrame() surfaces an error toast and does not call onCapture")
    func throwingCaptureFrameSurfacesErrorAndSkipsCapture() async {
        let session = MockCaptureSession() // never started -> captureFrame() throws .notRunning
        let ocr = StubOCRService(returning: "irrelevant")
        let presenter = ErrorPresenter()
        let spy = CaptureSpy()

        let succeeded = await CameraCaptureHandler.run(
            captureSession: session,
            ocrService: ocr,
            errorPresenter: presenter,
            onCapture: { spy.record($0) }
        )

        #expect(!succeeded)
        #expect(presenter.toast != nil)
        #expect(spy.captured.isEmpty)
    }

    // MARK: - recognizeText() throws

    @Test("a thrown recognizeText() surfaces an error toast and does not call onCapture")
    func throwingRecognizeTextSurfacesErrorAndSkipsCapture() async {
        let session = MockCaptureSession()
        await session.startSession()
        let ocr = StubOCRService(throwing: StubError.boom)
        let presenter = ErrorPresenter()
        let spy = CaptureSpy()

        let succeeded = await CameraCaptureHandler.run(
            captureSession: session,
            ocrService: ocr,
            errorPresenter: presenter,
            onCapture: { spy.record($0) }
        )

        #expect(!succeeded)
        #expect(presenter.toast?.message == "Couldn't capture — try again.")
        #expect(spy.captured.isEmpty)
    }

    // MARK: - empty / whitespace-only OCR text

    @Test("whitespace-only OCR text does not call onCapture and shows a 'no text found' message")
    func whitespaceOnlyTextSkipsCapture() async {
        let session = MockCaptureSession()
        await session.startSession()
        let ocr = StubOCRService(returning: "   \n\t  ")
        let presenter = ErrorPresenter()
        let spy = CaptureSpy()

        let succeeded = await CameraCaptureHandler.run(
            captureSession: session,
            ocrService: ocr,
            errorPresenter: presenter,
            onCapture: { spy.record($0) }
        )

        #expect(!succeeded)
        #expect(spy.captured.isEmpty)
        #expect(presenter.toast?.message == "No text found — try getting closer.")
    }

    @Test("empty-string OCR text does not call onCapture")
    func emptyStringTextSkipsCapture() async {
        let session = MockCaptureSession()
        await session.startSession()
        let ocr = StubOCRService(returning: "")
        let presenter = ErrorPresenter()
        let spy = CaptureSpy()

        let succeeded = await CameraCaptureHandler.run(
            captureSession: session,
            ocrService: ocr,
            errorPresenter: presenter,
            onCapture: { spy.record($0) }
        )

        #expect(!succeeded)
        #expect(spy.captured.isEmpty)
    }

    // MARK: - success

    @Test("non-empty OCR text calls onCapture with the recognized text")
    func nonEmptyTextCallsOnCapture() async {
        let session = MockCaptureSession()
        await session.startSession()
        let ocr = StubOCRService(returning: "Photosynthesis converts light to energy.")
        let presenter = ErrorPresenter()
        let spy = CaptureSpy()

        let succeeded = await CameraCaptureHandler.run(
            captureSession: session,
            ocrService: ocr,
            errorPresenter: presenter,
            onCapture: { spy.record($0) }
        )

        #expect(succeeded)
        #expect(spy.captured == ["Photosynthesis converts light to energy."])
        #expect(presenter.toast == nil)
    }

    @Test("success dismisses a stale error toast from a previous failed attempt")
    func successDismissesStaleToast() async {
        let session = MockCaptureSession() // not started yet -> first attempt fails
        let ocr = StubOCRService(returning: "Recovered text.")
        let presenter = ErrorPresenter()
        let spy = CaptureSpy()

        _ = await CameraCaptureHandler.run(
            captureSession: session,
            ocrService: ocr,
            errorPresenter: presenter,
            onCapture: { spy.record($0) }
        )
        #expect(presenter.toast != nil)

        await session.startSession()
        let succeeded = await CameraCaptureHandler.run(
            captureSession: session,
            ocrService: ocr,
            errorPresenter: presenter,
            onCapture: { spy.record($0) }
        )

        #expect(succeeded)
        #expect(presenter.toast == nil)
    }
}
#endif
