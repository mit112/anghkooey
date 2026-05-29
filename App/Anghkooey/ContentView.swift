import SwiftUI
import AnghkooeyCore
import AnghkooeyIntelligence
import AnghkooeyUI

struct ContentView: View {

    private enum CaptureMode { case qa, cloze }

    @Environment(AppState.self) private var appState
    @Environment(ClipboardCaptureCoordinator.self) private var clipboardCoordinator
    @State private var captureMode: CaptureMode = .qa

    var body: some View {
        TabView {
            NavigationStack {
                ReviewScreen(store: appState.cardStore)
            }
            .tabItem { Label("Review", systemImage: "rectangle.on.rectangle") }

            NavigationStack {
                VStack(spacing: 0) {
                    Picker("Mode", selection: $captureMode) {
                        Text("Q&A").tag(CaptureMode.qa)
                        Text("Cloze").tag(CaptureMode.cloze)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if captureMode == .qa {
                        CameraView(
                            captureSession: CameraCaptureSession(),
                            ocrService: LiveOCRServiceDataAdapter(),
                            onCapture: { text in
                                Task { await appState.enqueue(resolvedText: text) }
                            }
                        )
                    } else {
                        // TODO: Replace with LiveClozeAuthoringService() once FoundationModels device
                        // entitlement is provisioned. Mock returns empty drafts (stubbed = []).
                        ClozeAuthoringView(
                            store: appState.cardStore,
                            authoringService: MockClozeAuthoringService()
                        )
                    }
                }
                .navigationTitle("Capture")
            }
            .tabItem { Label("Capture", systemImage: "camera") }

            NavigationStack {
                LibraryView(store: appState.cardStore)
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .safeAreaInset(edge: .top) {
            ClipboardBanner(coordinator: clipboardCoordinator)
                .animation(.snappy, value: clipboardCoordinator.pendingOffer)
        }
    }
}
