import SwiftUI

/// Renders `presenter.toast` as a transient top banner, matching
/// `ClipboardBanner`'s visual language.
struct ErrorToastModifier: ViewModifier {
    let presenter: ErrorPresenter

    public func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top) {
                if let toast = presenter.toast {
                    ErrorToastBanner(toast: toast, presenter: presenter)
                }
            }
            .animation(.default, value: presenter.toast?.id)
    }
}

public extension View {
    /// Presents error toasts from `presenter` as a transient top banner.
    ///
    /// ```
    /// // In a screen: @State private var errorPresenter = ErrorPresenter()
    /// // Apply once at content root: .errorToast(errorPresenter)
    /// // On failure (view or view-model): errorPresenter.present("Couldn't save.", retry: { await vm.retrySave() })
    /// ```
    ///
    /// For sheet contexts, give the sheet its own presenter so the toast
    /// renders above the sheet.
    func errorToast(_ presenter: ErrorPresenter) -> some View {
        modifier(ErrorToastModifier(presenter: presenter))
    }
}

private struct ErrorToastBanner: View {
    let toast: ErrorToast
    let presenter: ErrorPresenter

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(toast.message)
                .font(.subheadline.weight(.semibold))
            Spacer()
            if toast.hasRetry {
                Button("Retry") {
                    Task { await presenter.retry() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Button {
                presenter.dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityIdentifier("error-toast")
    }
}
