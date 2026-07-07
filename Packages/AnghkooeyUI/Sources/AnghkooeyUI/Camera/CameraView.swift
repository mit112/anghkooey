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
    @State private var errorPresenter = ErrorPresenter()
    @State private var authorizationDenied = false
    /// Bumped on every successful capture; drives `.sensoryFeedback` below so
    /// the user gets an acknowledgement before the draft sheet arrives (#24).
    @State private var captureSuccessCount = 0

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
                .sensoryFeedback(.success, trigger: captureSuccessCount)
            }
        }
        .errorToast(errorPresenter)
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
        let succeeded = await CameraCaptureHandler.run(
            captureSession: captureSession,
            ocrService: ocrService,
            errorPresenter: errorPresenter,
            onCapture: onCapture
        )
        if succeeded {
            captureSuccessCount += 1
        }
    }
}

/// The capture → OCR → validate decision logic behind `CameraView.handleCapture()`,
/// pulled out into a standalone function so it's unit-testable without a
/// running view hierarchy (the camera can't run in the simulator/CI, so
/// tests drive this with mock `captureSession`/`ocrService` values instead).
///
/// Failure modes are surfaced via `errorPresenter` rather than thrown:
/// - A thrown `captureFrame()`/`recognizeText()` presents an error toast
///   and does not call `onCapture` (#24 — `captureError` used to be written
///   but never rendered, so this used to fail silently). No retry closure is
///   attached: the shutter button is the retry affordance, and it already
///   re-enters this pipeline through the guarded `handleCapture()` — a
///   separate retry here would bypass the `isCapturing` guard.
/// - Whitespace-only OCR output presents a "no text found" message and does
///   not call `onCapture` — never opens a blank draft (#24).
enum CameraCaptureHandler {

    /// Runs the pipeline once. Returns `true` only when `onCapture` was
    /// actually invoked with usable text, so the caller can gate success
    /// feedback (haptic/flash) on a real delivered capture.
    @MainActor
    @discardableResult
    static func run(
        captureSession: any CaptureServiceProtocol,
        ocrService: any OCRServiceProtocol,
        errorPresenter: ErrorPresenter,
        onCapture: @escaping @MainActor @Sendable (String) -> Void
    ) async -> Bool {
        do {
            let data = try await captureSession.captureFrame()
            let text = try await ocrService.recognizeText(inImageData: data)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                UILog.capture.error("handleCapture: OCR produced empty/whitespace-only text")
                errorPresenter.present("No text found — try getting closer.")
                return false
            }
            errorPresenter.dismiss()
            onCapture(text)
            return true
        } catch {
            UILog.capture.error("handleCapture failed: \(error)")
            errorPresenter.present("Couldn't capture — try again.")
            return false
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
