import Testing
@testable import AnghkooeyUI

@Test func uiLogSubsystemIsOverridable() {
    UILog.subsystem = "com.test.anghkooey"
    #expect(UILog.subsystem == "com.test.anghkooey")
    _ = UILog.review
    _ = UILog.library
    _ = UILog.capture
}
