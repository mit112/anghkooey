import SwiftUI
import AnghkooeyCore
import AnghkooeyIntelligence
import AnghkooeyUI

@main
struct AnghkooeyApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.unknown.anghkooey"
        CoreLog.configure(subsystem: subsystem)
        IntelligenceLog.subsystem = subsystem
        UILog.subsystem = subsystem
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task { await appState.drain() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await appState.drain() }
                    }
                }
                .sheet(item: $appState.presentedCard) { draft in
                    CardReviewSheet(
                        draft: draft,
                        onAccept: { appState.acceptCard() },
                        onSkip: { appState.skipCard() }
                    )
                    .onAppear { appState.cardReviewSheetDidAppear() }
                }
        }
    }
}
