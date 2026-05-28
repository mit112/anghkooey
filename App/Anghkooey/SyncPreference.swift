import Foundation
import AnghkooeyCore

/// UserDefaults-backed iCloud-sync toggle. Read once at launch to choose the
/// `SyncMode`. Changing the preference requires an app relaunch because
/// `ModelContainer` is constructed once in `AnghkooeyApp.init()`.
enum SyncPreference {
    private static let key = "anghkooey.iCloudSyncEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var syncMode: SyncMode {
        // Simulator never has a provisioned CloudKit container, so always use
        // local mode regardless of the preference flag. CloudKit sync only
        // activates on a physically signed device build.
        #if targetEnvironment(simulator)
        return .local
        #else
        return isEnabled
            ? .cloudKit(containerID: AnghkooeyModelContainer.cloudKitContainerID)
            : .local
        #endif
    }
}
