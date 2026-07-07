import Testing
import SwiftUI
import AnghkooeyUI

/// Compiles only against `ErrorPresenter`'s public surface (no `@testable`).
/// If any symbol referenced here loses its `public` modifier, this file fails
/// to *compile* — that's the point: it gives "usable from an app target"
/// acceptance criteria real teeth instead of relying on convention.
@Suite("ErrorPresenter — public API smoke test")
@MainActor
struct ErrorPresenterPublicAPITests {

    @Test("ErrorPresenter's public surface is usable from outside the module")
    func publicSurfaceIsUsable() {
        let presenter = ErrorPresenter()

        presenter.present("x")
        #expect(presenter.toast != nil)

        presenter.dismiss()
        #expect(presenter.toast == nil)
    }

    private struct _SmokeView: View {
        let p = ErrorPresenter()
        var body: some View {
            Color.clear.errorToast(p)
        }
    }
}
