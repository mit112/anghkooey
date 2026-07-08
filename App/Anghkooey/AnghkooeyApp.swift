import SwiftUI
import MetricKit
import UIKit
import AnghkooeyCore
import AnghkooeyIntelligence
import AnghkooeyUI

// URL is not Identifiable by default; this conformance lets .sheet(item:) accept a URL.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

@main
struct AnghkooeyApp: App {
    @State private var appState: AppState
    @State private var freezeController: FreezeController
    @State private var clipboardCoordinator = ClipboardCaptureCoordinator()
    @State private var pendingImportURL: URL?
    @Environment(\.scenePhase) private var scenePhase
    private let metricsReceiver = MetricsReceiver()

    init() {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.unknown.anghkooey"
        CoreLog.configure(subsystem: subsystem)
        IntelligenceLog.subsystem = subsystem
        UILog.subsystem = subsystem

        // `try!` is intentional: a corrupt SwiftData store on launch is
        // unrecoverable in v1. Log + crash beats a silent broken state.
        let container = try! AnghkooeyModelContainer.makeContainer(syncMode: SyncPreference.syncMode)
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
                .environment(clipboardCoordinator)
                .errorToast(appState.rootErrorPresenter)
                .task { await appState.drain() }
                .task { await appState.refreshAuthoringAvailability() }
                .task {
                    clipboardCoordinator.onRoute = { text in
                        Task { await appState.enqueue(resolvedText: text) }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await appState.drain() }
                        Task { await appState.refreshAuthoringAvailability() }
                        clipboardCoordinator.refreshOffer()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .anghkooeyDeckDidChange)) { _ in
                    Task { await appState.rewriteWidgetSnapshot() }
                }
                .onOpenURL { url in
                    if url.pathExtension.lowercased() == "apkg" {
                        pendingImportURL = url
                    }
                }
                .sheet(item: $pendingImportURL) { url in
                    AnkiImportView(
                        importer: LiveAnkiImporter(store: appState.cardStore),
                        isPresented: Binding(
                            get: { pendingImportURL != nil },
                            set: { if !$0 { pendingImportURL = nil } }
                        )
                    )
                }
                .sheet(item: $appState.presentedDraft, onDismiss: { appState.handleSheetDismiss() }) { identified in
                    CardReviewSheet(
                        draft: identified,
                        onAccept: { q, a in Task { await appState.acceptDraft(question: q, answer: a) } },
                        onSkip: { appState.skipDraft() },
                        progress: appState.presentedDraftProgress
                    )
                    .errorToast(appState.errorPresenter)
                    .onAppear { appState.cardReviewSheetDidAppear() }
                }
        }
    }
}
