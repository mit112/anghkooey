/// A single eval fixture: one input passage and its expected golden cards.
///
/// Loaded from `eval-fixtures.json` via `Bundle.module` in test targets,
/// and from a file path in `EvalRunner`.
public struct EvalFixture: Codable, Sendable {
    /// Unique identifier, e.g. `"biology-001"`.
    public var id: String
    /// The input passage fed to the authoring service.
    public var passage: String
    /// The prompt template version that produced `goldenDrafts`.
    /// Commit a new `make eval` run alongside any template change.
    public var templateVersion: String
    /// Expected card output from the live model. Used as the oracle for CI rubric scoring.
    public var goldenDrafts: [CardDraft]

    public init(id: String, passage: String,
                templateVersion: String, goldenDrafts: [CardDraft]) {
        self.id = id
        self.passage = passage
        self.templateVersion = templateVersion
        self.goldenDrafts = goldenDrafts
    }
}
