import SwiftUI

struct SettingsView: View {
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
                                Task { try? await freeze.unfreeze() }
                            }
                        }
                    ))
                    if let since = freeze.frozenSince {
                        LabeledContent("Frozen since", value: since.formatted(date: .abbreviated, time: .shortened))
                    }
                    Text("While frozen, no cards become due. When you turn this off, your deck slides forward by however many days you were away — no overdue debt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
