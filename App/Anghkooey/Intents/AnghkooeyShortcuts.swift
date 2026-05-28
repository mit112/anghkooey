import AppIntents

struct AnghkooeyShortcuts: AppShortcutsProvider {
    nonisolated(unsafe) static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddToAnghkooeyIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "Remember this in \(.applicationName)",
                "Save to \(.applicationName)",
                "Capture in \(.applicationName)"
            ],
            shortTitle: "Add to Anghkooey",
            systemImageName: "plus.rectangle.on.rectangle"
        )
    }
}
