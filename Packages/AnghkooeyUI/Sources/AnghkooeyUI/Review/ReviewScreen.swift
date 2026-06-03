import SwiftUI
import AnghkooeyCore

/// Screen-level container for the card review loop.
///
/// Creates and owns a `ReviewSession` for its lifetime. Loads due cards on
/// appear, on foreground resume (`scenePhase == .active`), and whenever
/// `Notification.Name.anghkooeyCardAccepted` fires (a draft was accepted and
/// persisted as a new card).
public struct ReviewScreen: View {

    @Environment(\.scenePhase) private var scenePhase

    @State private var session: ReviewSession
    private let loadSampleCards: (() async -> Void)?
    private let onImport: (() -> Void)?

    public init(store: any CardStoreProtocol,
                scheduler: any FSRS6Engine = LiveFSRS6Engine(),
                loadSampleCards: (() async -> Void)? = nil,
                onImport: (() -> Void)? = nil) {
        _session = State(initialValue: ReviewSession(store: store, scheduler: scheduler))
        self.loadSampleCards = loadSampleCards
        self.onImport = onImport
    }

    public var body: some View {
        ReviewView(session: session, loadSampleCards: loadSampleCards, onImport: onImport)
            .navigationTitle("Review")
            .task { await session.loadDueQueue() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await session.loadDueQueue() }
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .anghkooeyCardAccepted)
            ) { _ in
                Task { await session.loadDueQueue() }
            }
    }
}
