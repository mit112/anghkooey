/// User-facing review grade for the 2-button Got it / Missed it UI.
///
/// Maps to `Rating` for the FSRS-6 scheduler. Storing both values keeps the
/// UI layer ignorant of FSRS internals and allows a 4-button UI to compile
/// cleanly without the UI importing FSRS types directly.
public enum ReviewGrade: String, Codable, Sendable, CaseIterable {
    case missed
    case gotIt

    public var fsrsRating: Rating {
        switch self {
        case .missed: return .again
        case .gotIt:  return .good
        }
    }
}
