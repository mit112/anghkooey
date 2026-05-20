import Testing
@testable import AnghkooeyCore

@Test func coreLogSubsystemIsOverridable() {
    CoreLog.subsystem = "com.test.anghkooey"
    #expect(CoreLog.subsystem == "com.test.anghkooey")
    // Verify loggers resolve without crashing
    _ = CoreLog.scheduling
    _ = CoreLog.persistence
    _ = CoreLog.captureInbox
}
