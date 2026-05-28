import Foundation

public enum LTMConfig {

    public static let defaultThresholdDays: Double = 21

    public static func count(
        _ cards: [Card.Snapshot],
        thresholdDays: Double = defaultThresholdDays
    ) -> Int {
        cards.lazy.filter { $0.stability >= thresholdDays }.count
    }
}
