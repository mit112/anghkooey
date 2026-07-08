import SwiftUI
import AnghkooeyCore
import AnghkooeyUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(FreezeController.self) private var freeze

    /// Live mirror of `SyncPreference.isEnabled`. Kept as view state (rather
    /// than reading the static directly in `body`) so toggling it re-renders
    /// the effective/pending status row below (#50). Seeded from the stored
    /// preference on appear.
    @State private var syncEnabled = SyncPreference.isEnabled
    @State private var showSyncRestartAlert = false

    /// How to force-quit + reopen on iOS — most users don't know "restart an
    /// app" means this.
    private static let restartInstructions =
        "Quit Anghkooey fully for this to take effect: swipe up from the bottom edge of the screen, swipe the Anghkooey card up and off, then tap its icon to reopen."

    /// True while the live toggle differs from the value the running container
    /// was built with — i.e. a restart is needed for the change to apply.
    private var syncChangePending: Bool {
        syncEnabled != appState.launchSyncPreferenceEnabled
    }

    /// Effective-vs-pending status shown in the always-visible status row.
    private var syncStatusText: String {
        switch (appState.launchSyncPreferenceEnabled, syncEnabled) {
        case (true, true): return "On"
        case (false, false): return "Off"
        case (false, true): return "On after you restart"
        case (true, false): return "Off after you restart"
        }
    }

    var body: some View {
        @Bindable var freeze = freeze

        NavigationStack {
            Form {
                Section("Review pacing") {
                    LabeledContent("Today's batch", value: "20 cards")
                    LabeledContent("Backlog veil at", value: "50+ due")
                    Text("When you have more than 50 cards due, the Review tab shows today's batch instead of the full count. Everything is still tracked.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Freeze") {
                    Toggle("I'm away", isOn: Binding(
                        get: { freeze.isFrozen },
                        set: { newValue in
                            if newValue {
                                freeze.freeze()
                            } else {
                                Task {
                                    do {
                                        try await freeze.unfreeze()
                                    } catch {
                                        // The toggle's get reads `freeze.isFrozen`; unfreeze()
                                        // only clears frozenSince AFTER a successful shift, so
                                        // on failure the toggle reverts to on by itself — we
                                        // just surface the error.
                                        appState.rootErrorPresenter.present(
                                            "Couldn't finish unfreezing your deck. Try again."
                                        )
                                    }
                                }
                            }
                        }
                    ))
                    if let since = freeze.frozenSince {
                        LabeledContent("Frozen since", value: since.formatted(date: .abbreviated, time: .shortened))
                    }
                    Text("Heading out? Freeze marks your away time. You can still review if you like — and when you turn this off, your deck slides forward by however many whole days you were away, so the days you were away don't pile onto what's already due.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Schedule optimization") {
                    NavigationLink("Optimize my schedule") {
                        OptimizeScheduleView(
                            store: appState.cardStore,
                            paramsStore: appState.optimizedParamsStore,
                            onOptimized: { await appState.refreshScheduler() }
                        )
                        .navigationTitle("Optimize Schedule")
                    }
                }

                Section("iCloud Sync") {
                    Toggle("Sync across my devices", isOn: $syncEnabled)
                        .onChange(of: syncEnabled) { _, newValue in
                            SyncPreference.isEnabled = newValue
                            // Alert only on the transition INTO a pending
                            // mismatch — re-toggling back to the launch state
                            // clears the pending banner and shows no alert.
                            if newValue != appState.launchSyncPreferenceEnabled {
                                showSyncRestartAlert = true
                            }
                        }
                    LabeledContent("Status", value: syncStatusText)
                    if syncChangePending {
                        Label(Self.restartInstructions, systemImage: "arrow.clockwise.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("Your cards stay on this device by default. Turn this on to sync to your private iCloud (only you can read it).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .alert("Restart to apply", isPresented: $showSyncRestartAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(Self.restartInstructions)
            }
        }
    }
}
