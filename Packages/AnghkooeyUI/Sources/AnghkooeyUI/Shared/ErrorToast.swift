import Foundation

/// A transient error banner rendered by `.errorToast(_:)`.
///
/// `retry` isn't modeled here because a closure can't be `Equatable`/trivially
/// `Sendable`; `ErrorPresenter` keeps the actual retry closure privately and
/// exposes only whether one exists via `hasRetry`, which is all the view needs
/// to decide whether to show a Retry button.
public struct ErrorToast: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let message: String
    public let hasRetry: Bool

    public init(id: UUID = UUID(), message: String, hasRetry: Bool) {
        self.id = id
        self.message = message
        self.hasRetry = hasRetry
    }
}
