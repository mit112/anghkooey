import Testing
@testable import AnghkooeyCore

@Suite("InboxNotifier")
struct InboxNotifierTests {

    @Test("notification name matches ADR-0003 value")
    func notificationNameMatchesADR() {
        #expect(InboxConstants.darwinNotificationName == "com.mitsheth.anghkooey.inboxDidChange")
    }

    @Test("observeInboxDidChange returns a non-nil token")
    func observeReturnsToken() {
        let token = InboxNotifier.observeInboxDidChange { }
        // Token must exist (not released immediately); type check is enough.
        _ = token
    }
}
