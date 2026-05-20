import Testing
@testable import AnghkooeyIntelligence

@Test func intelligenceLogSubsystemIsOverridable() {
    IntelligenceLog.subsystem = "com.test.anghkooey"
    #expect(IntelligenceLog.subsystem == "com.test.anghkooey")
    _ = IntelligenceLog.ai
    _ = IntelligenceLog.ocr
}
