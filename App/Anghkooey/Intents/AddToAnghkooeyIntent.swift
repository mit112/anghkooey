import AppIntents
import Foundation
import AnghkooeyCore

struct AddToAnghkooeyIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Add to Anghkooey"
    nonisolated(unsafe) static var description = IntentDescription(
        "Capture text into Anghkooey. On-device AI drafts flashcards from it next time you open the app."
    )
    nonisolated(unsafe) static var openAppWhenRun: Bool = false

    @Parameter(title: "Text", requestValueDialog: "What would you like to remember?")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: InboxConstants.appGroupID)
            ?? FileManager.default.temporaryDirectory
        let writer = InboxWriter(containerURL: containerURL)
        try await Self.write(text: text, using: writer)
        return .result(dialog: "Saved to Anghkooey. I'll draft cards next time you open the app.")
    }

    static func write(text: String, using writer: InboxWriter) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AddToAnghkooeyError.emptyText }
        try await writer.write(text: trimmed, sourceApp: "siri")
    }
}

enum AddToAnghkooeyError: Error, CustomLocalizedStringResourceConvertible {
    case emptyText
    var localizedStringResource: LocalizedStringResource {
        switch self { case .emptyText: "There was no text to save." }
    }
}
