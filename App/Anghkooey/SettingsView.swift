import SwiftUI
import AnghkooeyCore
import AnghkooeyUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(FreezeController.self) private var freeze

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
                    Text("Heading out? Freeze marks your away time. You can still review if you like — and when you turn this off, your deck slides forward by however many whole days you were away, so you come back with no overdue pile-up.")
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
                    Toggle("Sync across my devices", isOn: Binding(
                        get: { SyncPreference.isEnabled },
                        set: { SyncPreference.isEnabled = $0 }
                    ))
                    Text("Your cards stay on this device by default. Turn this on to sync to your private iCloud (only you can read it). Restart Anghkooey for the change to take effect.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
