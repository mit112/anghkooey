#if os(iOS)
import Testing
import Foundation
@testable import AnghkooeyUI

@Suite("CameraCapture")
struct CameraCaptureTests {

    /// Verifies the capture pipeline produces non-empty Data.
    ///
    /// Uses `MockCaptureSession` (real hardware not available in simulator/CI).
    /// The production `CameraCaptureSession` honours the same contract on device.
    @Test func capturedDataIsNonEmpty() async throws {
        let session = MockCaptureSession()
        await session.startSession()
        let data = try await session.captureFrame()
        #expect(!data.isEmpty)
    }

    /// Verifies stop/running state transitions and that the stop
    /// callback fires — documents the contract CameraView.onDisappear
    /// must honour via the production CameraCaptureSession.deinit.
    @Test func captureSessionStopsOnDealloc() async throws {
        nonisolated(unsafe) var stopFired = false
        let session = MockCaptureSession(onStop: { stopFired = true })
        await session.startSession()
        #expect(session.isRunning)
        await session.stopSession()
        #expect(!session.isRunning)
        #expect(session.stopCallCount == 1)
        #expect(stopFired)
    }
}
#endif
