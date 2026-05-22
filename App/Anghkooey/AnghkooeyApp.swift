import SwiftUI
import SwiftData
import MetricKit
import AnghkooeyCore
import AnghkooeyIntelligence
import AnghkooeyUI

@main
struct AnghkooeyApp: App {
    @State private var appState: AppState
    @State private var freezeController: FreezeController
    @Environment(\.scenePhase) private var scenePhase
    private let metricsReceiver = MetricsReceiver()

    init() {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.unknown.anghkooey"
        CoreLog.configure(subsystem: subsystem)
        IntelligenceLog.subsystem = subsystem
        UILog.subsystem = subsystem

        // `try!` is intentional: a corrupt SwiftData store on launch is
        // unrecoverable in v1. Log + crash beats a silent broken state.
        let container = try! ModelContainer(
            for: Schema(AnghkooeySchemaV1.models),
            configurations: ModelConfiguration()
        )
        let store = CardStore(container: container)
        _appState = State(initialValue: AppState(
            cardAuthor: LiveCardAuthoringService(),
            cardStore: store
        ))
        _freezeController = State(initialValue: FreezeController(
            cardStore: store,
            storage: UserDefaultsFreezeStorage()
        ))

        MXMetricManager.shared.add(metricsReceiver)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(freezeController)
                .task { await appState.drain() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await appState.drain() }
                    }
                }
                .sheet(item: $appState.presentedDraft) { identified in
                    CardReviewSheet(
                        draft: identified,
                        onAccept: { appState.acceptDraft() },
                        onSkip: { appState.skipDraft() }
                    )
                    .onAppear { appState.cardReviewSheetDidAppear() }
                }
        }
    }
}
