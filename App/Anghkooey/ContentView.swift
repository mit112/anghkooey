import SwiftUI
import AnghkooeyCore
import AnghkooeyIntelligence
import AnghkooeyUI

struct ContentView: View {

    private enum CaptureMode { case type, camera, cloze }

    @Environment(AppState.self) private var appState
    @Environment(ClipboardCaptureCoordinator.self) private var clipboardCoordinator
    @State private var captureMode: CaptureMode = .type
    @State private var selectedTab: Int = 0
    @State private var onboardingState = OnboardingState()
    @State private var showingImportFromReview = false
    @State private var availabilityBannerDismissed = false

    @State private var sampleLoadErrorMessage: String?
    @State private var isLoadingSamples = false

    private func loadSamples() async {
        // Debounce concurrent loads (a rapid double-tap, or two different "Load
        // sample deck" buttons) so we never launch two overlapping inserts (#46).
        // The loader is also idempotent per-entry, but this stops racing tasks
        // before they reach the store's find-then-create TOCTOU window.
        guard !isLoadingSamples else { return }
        isLoadingSamples = true
        defer { isLoadingSamples = false }
        do {
            try await SampleDeckLoader(store: appState.cardStore).load(now: .now)
        } catch {
            sampleLoadErrorMessage = "Couldn't load the sample deck: \(error.localizedDescription)"
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ReviewScreen(
                    store: appState.cardStore,
                    scheduler: { appState.scheduler },
                    loadSampleCards: { await loadSamples() },
                    onImport: { showingImportFromReview = true }
                )
            }
            .tabItem { Label("Review", systemImage: "rectangle.on.rectangle") }
            .tag(0)

            NavigationStack {
                VStack(spacing: 0) {
                    Picker("Mode", selection: $captureMode) {
                        Text("Type").tag(CaptureMode.type)
                        Text("Camera").tag(CaptureMode.camera)
                        Text("Cloze").tag(CaptureMode.cloze)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Group {
                        if let availability = appState.authoringAvailability,
                           !availabilityBannerDismissed,
                           CaptureAvailabilityModel(availability: availability).bannerMessage != nil {
                            CaptureAvailabilityBanner(availability: availability) {
                                availabilityBannerDismissed = true
                            }
                        }
                    }
                    // Scope the banner's move/opacity transition to its own
                    // insert (availability resolving) and dismiss without
                    // animating the sibling Picker/camera content.
                    .animation(.snappy, value: appState.authoringAvailability)
                    .animation(.snappy, value: availabilityBannerDismissed)

                    if captureMode == .type {
                        TypedTextCaptureView(onDraft: { text in
                            Task { await appState.enqueue(resolvedText: text) }
                        })
                    } else if captureMode == .camera {
                        if selectedTab == 1 {
                            CameraView(
                                captureSession: CameraCaptureSession(),
                                ocrService: LiveOCRServiceDataAdapter(),
                                onCapture: { text in
                                    Task { await appState.enqueue(resolvedText: text) }
                                }
                            )
                        } else {
                            ContentUnavailableView(
                                "Camera",
                                systemImage: "camera",
                                description: Text("Switch to the Capture tab to use the camera.")
                            )
                        }
                    } else {
                        ClozeAuthoringView(
                            store: appState.cardStore,
                            authoringService: LiveClozeAuthoringService()
                        )
                    }
                }
                .navigationTitle("Capture")
                .onChange(of: appState.authoringAvailability) { _, _ in
                    availabilityBannerDismissed = false
                }
            }
            .tabItem { Label("Capture", systemImage: "camera") }
            .tag(1)

            NavigationStack {
                LibraryView(
                    store: appState.cardStore,
                    loadSampleCards: { await loadSamples() }
                )
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
            .tag(2)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(3)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingState.hasCompleted },
            // Real two-way binding: a system-initiated dismissal persists completion
            // instead of silently re-presenting the cover (#45).
            set: { presented in if !presented { onboardingState.complete() } }
        )) {
            OnboardingView(
                onLoadSample: {
                    Task { await loadSamples() }
                },
                onFinish: { onboardingState.complete() }
            )
        }
        .sheet(isPresented: $showingImportFromReview) {
            AnkiImportView(
                importer: LiveAnkiImporter(store: appState.cardStore),
                isPresented: $showingImportFromReview
            )
        }
        .safeAreaInset(edge: .top) {
            if appState.authoringCount > 0 {
                DraftingIndicator()
            } else {
                ClipboardBanner(coordinator: clipboardCoordinator)
                    .animation(.snappy, value: clipboardCoordinator.pendingOffer)
            }
        }
        .animation(.snappy, value: appState.authoringCount > 0)
        .onChange(of: appState.authoringCount) { old, new in
            // Announce only on the 0↔non-zero boundary, not on every count
            // change (e.g. a second concurrent capture starting while the
            // first is still authoring shouldn't re-announce "Drafting
            // cards") (#34).
            if old == 0 && new > 0 {
                AccessibilityNotification.Announcement("Drafting cards").post()
            } else if old > 0 && new == 0 {
                AccessibilityNotification.Announcement("Cards ready").post()
            }
        }
        .alert(
            "Sample deck",
            isPresented: Binding(
                get: { sampleLoadErrorMessage != nil },
                set: { if !$0 { sampleLoadErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sampleLoadErrorMessage ?? "")
        }
    }
}
