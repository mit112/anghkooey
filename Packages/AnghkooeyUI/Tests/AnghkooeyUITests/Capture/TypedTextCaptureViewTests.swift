import Testing
@testable import AnghkooeyUI

// MARK: - #31 typed-text capture gate
//
// `TypedTextCaptureView.isDraftable` is the pure decision behind the "Draft
// cards" button's `.disabled` state — it decides whether typed/pasted text
// is worth sending into the AI authoring pipeline. Pulled into a static func
// so it's testable without a running view hierarchy (house style, matches
// `CameraCaptureHandler`/`CaptureAvailabilityModel`).
@Suite("TypedTextCaptureView.isDraftable")
struct TypedTextCaptureViewTests {

    @Test func emptyTextIsNotDraftable() {
        #expect(!TypedTextCaptureView.isDraftable(""))
    }

    @Test func whitespaceAndNewlinesOnlyIsNotDraftable() {
        #expect(!TypedTextCaptureView.isDraftable("   \n\t  \n"))
    }

    @Test func nonEmptyTextIsDraftable() {
        #expect(TypedTextCaptureView.isDraftable("hello"))
    }

    @Test func textWithSurroundingWhitespaceIsDraftable() {
        #expect(TypedTextCaptureView.isDraftable(" hello "))
    }
}
