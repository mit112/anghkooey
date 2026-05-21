import Foundation

/// Abstracts AVCaptureSession for testability.
///
/// Concrete iOS implementation: `CameraCaptureSession`.
/// Test double: `MockCaptureSession` (defined in the same iOS-only file).
public protocol CaptureServiceProtocol: AnyObject, Sendable {
    var isRunning: Bool { get }
    func startSession() async
    func stopSession() async
    /// Capture a still frame encoded as HEIC Data.
    func captureFrame() async throws -> Data
}

/// Errors thrown by `CaptureServiceProtocol.captureFrame()`.
public enum CaptureError: Error, Sendable {
    case notRunning
    case encodingFailed
    case permissionDenied
}
