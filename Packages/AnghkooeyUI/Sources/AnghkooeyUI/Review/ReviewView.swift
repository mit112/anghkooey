import SwiftUI
import AnghkooeyCore

/// Flashcard review UI driven by a `ReviewSession`.
///
/// State machine:
///   `.loading` → `.reviewing` (question shown, "Show Answer" button)
///              → answer revealed + Got it / Missed it buttons
///              → next card or `.empty`
///
/// `ReviewView` imports only `AnghkooeyCore` for `ReviewGrade` — it has no
/// direct FSRS or SwiftData imports.
public struct ReviewView: View {

    @Bindable var session: ReviewSession
    @State private var gotItTrigger = false
    @State private var missedItTrigger = false

    public init(session: ReviewSession) {
        self.session = session
    }

    public var body: some View {
        switch session.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .reviewing:
            reviewingBody

        case .empty:
            emptyBody

        case .error(let msg):
            ContentUnavailableView(
                "Error",
                systemImage: "exclamationmark.triangle",
                description: Text(msg)
            )
        }
    }

    // MARK: - Reviewing

    private var reviewingBody: some View {
        VStack(spacing: 0) {
            if let card = session.currentCard {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        questionSection(card.question)
                        if session.isAnswerRevealed {
                            answerSection(card.answer)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()
            actionBar
        }
        .animation(.easeInOut(duration: 0.2), value: session.isAnswerRevealed)
    }

    private func questionSection(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Question")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(question)
                .font(.title3)
                .fontWeight(.medium)
        }
    }

    private func answerSection(_ answer: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Answer")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(answer)
                .font(.body)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var actionBar: some View {
        Group {
            if session.isAnswerRevealed {
                gradeButtons
            } else {
                showAnswerButton
            }
        }
        .padding()
    }

    private var showAnswerButton: some View {
        Button("Show Answer") {
            session.revealAnswer()
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
    }

    private var gradeButtons: some View {
        HStack(spacing: 12) {
            Button {
                missedItTrigger.toggle()
                Task { await session.submit(grade: .missed) }
            } label: {
                Label("Missed it", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.large)

            Button {
                gotItTrigger.toggle()
                Task { await session.submit(grade: .gotIt) }
            } label: {
                Label("Got it", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .sensoryFeedback(.success, trigger: gotItTrigger)
        .sensoryFeedback(.error, trigger: missedItTrigger)
    }

    // MARK: - Empty

    private var emptyBody: some View {
        ContentUnavailableView(
            "All caught up",
            systemImage: "checkmark.circle.fill",
            description: Text("Come back when your next review is due, or capture something new to grow your deck.")
        )
    }
}
