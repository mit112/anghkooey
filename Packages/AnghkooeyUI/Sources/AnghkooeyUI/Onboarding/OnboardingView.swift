import SwiftUI

@MainActor @Observable
public final class OnboardingState {
    private let defaults: UserDefaults
    private let key = "hasCompletedOnboarding"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var hasCompleted: Bool { defaults.bool(forKey: key) }
    public func complete() { defaults.set(true, forKey: key) }
}

public struct OnboardingView: View {
    let onLoadSample: () -> Void
    let onFinish: () -> Void

    public init(onLoadSample: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.onLoadSample = onLoadSample
        self.onFinish = onFinish
    }

    public var body: some View {
        TabView {
            page("Remember everything",
                 "Snap a photo, paste text, or type — Anghkooey turns it into flashcards.",
                 "camera.viewfinder")
            page("Fall behind, guilt-free",
                 "Miss a few days? Anghkooey waits for you — no overwhelming overdue pile.",
                 "calendar.badge.clock")
            VStack(spacing: 24) {
                page("Start in seconds",
                     "Load a sample deck to try a review right now, or add your own card.",
                     "sparkles")
                VStack(spacing: 12) {
                    Button("Load a sample deck") {
                        onLoadSample(); onFinish()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Load a sample deck and finish onboarding")
                    Button("I'll add my own") { onFinish() }
                        .accessibilityLabel("Skip sample deck and finish onboarding")
                }
            }
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Button("Skip") { onFinish() }
                .padding(.top, 64)
                .padding(.trailing, 24)
                .accessibilityLabel("Skip onboarding")
        }
    }

    private func page(_ title: String, _ body: String, _ symbol: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.bold())
            Text(body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(body)")
    }
}
