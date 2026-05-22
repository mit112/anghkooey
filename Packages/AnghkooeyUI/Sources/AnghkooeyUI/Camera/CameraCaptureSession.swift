#if os(iOS)
import AVFoundation
import CoreMedia
import CoreGraphics
import ImageIO
import Foundation
import OSLog

// MARK: - CameraCaptureSession

/// Manages an AVCaptureSession for still-frame capture.
public final class CameraCaptureSession: CaptureServiceProtocol, @unchecked Sendable {

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.mitsheth.anghkooey.camera.capture-session")
    private let stateLock = NSLock()
    private let logger = Logger(subsystem: "com.mitsheth.anghkooey.ui", category: "CameraCaptureSession")

    private var _isRunning = false
    private var isConfigured = false
    private var photoDelegates: [Int64: PhotoCaptureDelegate] = [:]

    public var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isRunning
    }

    public var underlyingSession: AVCaptureSession {
        session
    }

    public init() {}

    public func startSession() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                guard configureSessionIfNeeded() else {
                    setIsRunning(false)
                    continuation.resume()
                    return
                }

                if !session.isRunning {
                    session.startRunning()
                }
                setIsRunning(true)
                continuation.resume()
            }
        }
    }

    public func stopSession() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                if session.isRunning {
                    session.stopRunning()
                }
                setIsRunning(false)
                continuation.resume()
            }
        }
    }

    /// Captures a still frame as HEIC-encoded Data.
    public func captureFrame() async throws -> Data {
        guard isRunning else { throw CaptureError.notRunning }

        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                guard isRunning else {
                    continuation.resume(throwing: CaptureError.notRunning)
                    return
                }

                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                let settingsID = settings.uniqueID
                let delegate = PhotoCaptureDelegate(continuation: continuation) { [weak self] in
                    self?.sessionQueue.async { [weak self] in
                        self?.photoDelegates[settingsID] = nil
                    }
                }

                photoDelegates[settingsID] = delegate
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    deinit {
        session.stopRunning()
    }

    private func setIsRunning(_ isRunning: Bool) {
        stateLock.lock()
        _isRunning = isRunning
        stateLock.unlock()
    }

    private func configureSessionIfNeeded() -> Bool {
        guard !isConfigured else { return true }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            logger.error("Back camera unavailable")
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else {
                logger.error("Unable to add back camera input")
                return false
            }
            session.addInput(input)
        } catch {
            logger.error("Unable to create camera input: \(error.localizedDescription, privacy: .public)")
            return false
        }

        guard session.canAddOutput(photoOutput) else {
            logger.error("Unable to add photo output")
            return false
        }
        session.addOutput(photoOutput)

        isConfigured = true
        return true
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {

    private let continuation: CheckedContinuation<Data, any Error>
    private let cleanup: @Sendable () -> Void
    private let stateLock = NSLock()
    private var didResume = false

    init(
        continuation: CheckedContinuation<Data, any Error>,
        cleanup: @escaping @Sendable () -> Void
    ) {
        self.continuation = continuation
        self.cleanup = cleanup
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        if let error {
            finish(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            finish(.failure(CaptureError.encodingFailed))
            return
        }

        finish(.success(data))
    }

    private func finish(_ result: Result<Data, any Error>) {
        stateLock.lock()
        guard !didResume else {
            stateLock.unlock()
            return
        }
        didResume = true
        stateLock.unlock()

        cleanup()

        switch result {
        case .success(let data):
            continuation.resume(returning: data)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

// MARK: - MockCaptureSession

/// Deterministic test double: returns a synthetic 1×1 JPEG image on captureFrame().
///
/// Uses @unchecked Sendable because stopCallCount is written from async contexts
/// in tests; production code never touches MockCaptureSession.
public final class MockCaptureSession: CaptureServiceProtocol, @unchecked Sendable {

    public private(set) var isRunning: Bool = false
    public private(set) var stopCallCount: Int = 0
    private let onStop: (@Sendable () -> Void)?

    public init(onStop: (@Sendable () -> Void)? = nil) {
        self.onStop = onStop
    }

    public func startSession() async {
        isRunning = true
    }

    public func stopSession() async {
        isRunning = false
        stopCallCount += 1
        onStop?()
    }

    public func captureFrame() async throws -> Data {
        guard isRunning else { throw CaptureError.notRunning }
        return makeSyntheticImageData()
    }

    /// Returns a minimal 1×1 white JPEG via CoreGraphics + ImageIO (no UIKit dependency).
    private func makeSyntheticImageData() -> Data {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard
            let ctx = CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 1, space: colorSpace, bitmapInfo: 0
            ),
            let image = ctx.makeImage()
        else { return Data() }

        let mutableData = NSMutableData()
        guard
            let dest = CGImageDestinationCreateWithData(
                mutableData, "public.jpeg" as CFString, 1, nil
            )
        else { return Data() }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return Data() }
        return mutableData as Data
    }
}
#endif
