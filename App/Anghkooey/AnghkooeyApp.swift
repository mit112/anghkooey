import SwiftUI
import AnghkooeyCore
import AnghkooeyIntelligence
import AnghkooeyUI

@main
struct AnghkooeyApp: App {
    init() {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.unknown.anghkooey"
        CoreLog.configure(subsystem: subsystem)
        IntelligenceLog.subsystem = subsystem
        UILog.subsystem = subsystem
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
