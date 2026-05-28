import AppIntents
import Foundation
import AnghkooeyCore

struct GradeCardIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Grade Card"
    nonisolated(unsafe) static var openAppWhenRun: Bool = false

    @Parameter(title: "Card ID")
    var cardID: String

    @Parameter(title: "Rating")
    var ratingRaw: Int

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: cardID),
              let rating = Rating(rawValue: ratingRaw) else {
            return .result()
        }
        let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: InboxConstants.appGroupID)
            ?? FileManager.default.temporaryDirectory
        let bridge = WidgetBridge(containerURL: containerURL)
        try? bridge.appendGrade(WidgetGradeDecision(id: UUID(), cardID: uuid, rating: rating, decidedAt: .now))
        return .result()
    }
}
