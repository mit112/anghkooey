import SwiftUI
import AnghkooeyCore
import AnghkooeyIntelligence
import AnghkooeyUI

struct ContentView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            NavigationStack {
                ReviewScreen(store: appState.cardStore)
            }
            .tabItem { Label("Review", systemImage: "rectangle.on.rectangle") }

            NavigationStack {
                CameraView(
                    captureSession: CameraCaptureSession(),
                    ocrService: LiveOCRServiceDataAdapter(),
                    onCapture: { text in
                        Task { await appState.enqueue(resolvedText: text) }
                    }
                )
                .navigationTitle("Capture")
            }
            .tabItem { Label("Capture", systemImage: "camera") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
