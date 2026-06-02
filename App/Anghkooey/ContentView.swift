import SwiftUI
import AnghkooeyCore
import AnghkooeyIntelligence
import AnghkooeyUI

struct ContentView: View {

    private enum CaptureMode { case qa, cloze }

    @Environment(AppState.self) private var appState
    @Environment(ClipboardCaptureCoordinator.self) private var clipboardCoordinator
    @State private var captureMode: CaptureMode = .qa
    @State private var selectedTab: Int = 0
    @State private var onboardingState = OnboardingState()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ReviewScreen(store: appState.cardStore, scheduler: appState.scheduler)
            }
            .tabItem { Label("Review", systemImage: "rectangle.on.rectangle") }
            .tag(0)

            NavigationStack {
                VStack(spacing: 0) {
                    Picker("Mode", selection: $captureMode) {
                        Text("Q&A").tag(CaptureMode.qa)
                        Text("Cloze").tag(CaptureMode.cloze)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if selectedTab == 1 && captureMode == .qa {
                        CameraView(
                            captureSession: CameraCaptureSession(),
                            ocrService: LiveOCRServiceDataAdapter(),
                            onCapture: { text in
                                Task { await appState.enqueue(resolvedText: text) }
                            }
                        )
                    } else if captureMode == .qa {
                        ContentUnavailableView(
                            "Camera",
                            systemImage: "camera",
                            description: Text("Switch to the Capture tab to use the camera.")
                        )
                    } else {
                        ClozeAuthoringView(
                            store: appState.cardStore,
                            authoringService: LiveClozeAuthoringService()
                        )
                    }
                }
                .navigationTitle("Capture")
            }
            .tabItem { Label("Capture", systemImage: "camera") }
            .tag(1)

            NavigationStack {
                LibraryView(store: appState.cardStore)
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
            .tag(2)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(3)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingState.hasCompleted },
            set: { _ in }
        )) {
            OnboardingView(
                onLoadSample: { /* SampleDeckLoader wired in T11 */ },
                onFinish: { onboardingState.complete() }
            )
        }
        .safeAreaInset(edge: .top) {
            ClipboardBanner(coordinator: clipboardCoordinator)
                .animation(.snappy, value: clipboardCoordinator.pendingOffer)
        }
    }
}
