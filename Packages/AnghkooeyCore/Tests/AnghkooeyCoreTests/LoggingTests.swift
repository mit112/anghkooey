import Testing
@testable import AnghkooeyCore

@Test func coreLogConfigureIsWriteOnce() {
    // configure() accepts the first call and ignores subsequent ones.
    // The subsystem may already be set by an earlier test; either way the
    // loggers must resolve without crashing — that is the observable contract.
    CoreLog.configure(subsystem: "com.test.anghkooey")
    let current = CoreLog.subsystem
    #expect(current == "com.test.anghkooey" || current == "com.unknown.anghkooey")
    // A second call must be silently ignored (write-once).
    CoreLog.configure(subsystem: "com.other.anghkooey")
    #expect(CoreLog.subsystem == current)
    // Verify all loggers resolve without crashing.
    _ = CoreLog.scheduling
    _ = CoreLog.persistence
    _ = CoreLog.captureInbox
}
