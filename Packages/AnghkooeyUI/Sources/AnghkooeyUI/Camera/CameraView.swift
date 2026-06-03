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
    @State private var authorizationDenied = false

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
            if authorizationDenied {
                deniedView
            } else {
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
        }
        .task {
            guard await requestCameraAccess() else {
                authorizationDenied = true
                return
            }
            await captureSession.startSession()
        }
        .onDisappear {
            Task { await captureSession.stopSession() }
        }
    }

    private var deniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Camera access is required to capture text.")
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
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

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        if let liveSession = session as? CameraCaptureSession {
            view.previewLayer.session = liveSession.underlyingSession
        }
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

/// UIView subclass that owns the AVCaptureVideoPreviewLayer as its backing layer,
/// so the layer always fills the view without needing manual frame updates.
private final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) { fatalError() }
}
#endif
