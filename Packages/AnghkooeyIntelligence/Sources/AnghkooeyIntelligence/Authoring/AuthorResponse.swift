import FoundationModels

/// The top-level structured output requested from `LanguageModelSession`.
///
/// Wraps the array so `@Generable` can generate the full set atomically.
@Generable
public struct AuthorResponse: Sendable, Codable {
    /// All candidate cards for the submitted passage.
    public var drafts: [CardDraft]
}
