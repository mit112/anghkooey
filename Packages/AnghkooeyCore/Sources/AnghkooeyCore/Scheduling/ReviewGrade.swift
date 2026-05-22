/// User-facing review grade for the 4-button Again / Hard / Good / Easy UI.
///
/// Maps to `Rating` for the FSRS-6 scheduler. Storing both values keeps the
/// UI layer ignorant of FSRS internals and allows the grade to be passed
/// through `ReviewSession.submit` without the UI importing FSRS types.
public enum ReviewGrade: String, Codable, Sendable, CaseIterable {
    case again
    case hard
    case good
    case easy

    // MARK: Migration shims (removed at M5.5G lane close)

    /// Deprecated — use `.again`.
    @available(*, deprecated, renamed: "again")
    public static var missed: ReviewGrade { .again }

    /// Deprecated — use `.good`.
    @available(*, deprecated, renamed: "good")
    public static var gotIt: ReviewGrade { .good }

    // MARK: FSRS mapping

    public var fsrsRating: Rating {
        switch self {
        case .again: return .again
        case .hard: return .hard
        case .good: return .good
        case .easy: return .easy
        }
    }
}
