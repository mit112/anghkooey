import Foundation

/// Projects the next review interval for each `Rating` without mutating state.
/// Used to show "<1m / 10m / 1d / 4d" hints under the grade buttons.
public enum IntervalProjection {

    /// Returns, per rating, the seconds-from-`now` until the card would next be due.
    public static func project(card: SchedulingCard,
                               engine: any FSRS6Engine,
                               now: Date) -> [Rating: TimeInterval] {
        var out: [Rating: TimeInterval] = [:]
        for rating in Rating.allCases {
            guard let output = try? engine.next(card: card, rating: rating, now: now) else { continue }
            out[rating] = max(0, output.card.due.timeIntervalSince(now))
        }
        return out
    }

    /// Compact human label for an interval in seconds.
    public static func label(seconds: TimeInterval) -> String {
        let minute = 60.0, hour = 3_600.0, day = 86_400.0, month = 30 * day, year = 365 * day
        switch seconds {
        case ..<minute:        return "<1m"
        case ..<hour:          return "\(Int((seconds / minute).rounded()))m"
        case ..<day:           return "\(Int((seconds / hour).rounded()))h"
        case ..<month:         return "\(Int((seconds / day).rounded()))d"
        case ..<year:          return "\(trim(seconds / month))mo"
        default:               return "\(trim(seconds / year))y"
        }
    }

    private static func trim(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))" : "\(rounded)"
    }
}
