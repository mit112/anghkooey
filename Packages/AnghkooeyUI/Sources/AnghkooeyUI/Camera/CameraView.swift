#if canImport(UIKit)
import AVFoundation
import SwiftUI
import AnghkooeyCore

/// Live camera preview with shutter capture.
///
/// Inject dependencies for testing:
/// ```swift
/// CameraView(captureSession: MockCaptureSession(), ocrService: MockOCR()) { text in ... }
/// ```
///
/// Codex implements the UIViewRepresentable preview layer (`CameraPreviewView`).
public struct CameraView: View {

    private let captureSession: any CaptureServiceProtocol
    private let ocrService: any OCRServiceProtocol
    private let onCapture: @MainActor @Sendable (String) -> Void

    @State private var isCapturing = false
    @State private var captureError: Error?

    public init(
        captureSession: any CaptureServiceProtocol,
        ocrService: any OCRServiceProtocol,
        onCapture: @escaping @MainActor @Sendable (String) -> Void
    ) {
        self.captureSession = captureSession
        self.ocrService = ocrService
        self.onCapture = onCapture
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewView(session: captureSession)
                .ignoresSafeArea()

            Button {
                Task { @MainActor in
                    await handleCapture()
                }
            } label: {
                Circle()
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle().fill(.white).frame(width: 58, height: 58)
                    )
                    .opacity(isCapturing ? 0.5 : 1.0)
            }
            .disabled(isCapturing)
            .padding(.bottom, 40)
        }
        .task {
            await captureSession.startSession()
        }
        .onDisappear {
            Task { await captureSession.stopSession() }
        }
    }

    @MainActor
    private func handleCapture() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        do {
            let data = try await captureSession.captureFrame()
            let text = try await ocrService.recognizeText(inImageData: data)
            onCapture(text)
        } catch {
            captureError = error
        }
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let session: any CaptureServiceProtocol

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        if let liveSession = session as? CameraCaptureSession {
            let layer = AVCaptureVideoPreviewLayer(session: liveSession.underlyingSession)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer }.forEach {
            $0.frame = uiView.bounds
        }
    }
}
#endif
