import SwiftUI
import AnghkooeyCore

/// Flashcard review UI driven by a `ReviewSession`.
///
/// State machine:
///   `.loading` → `.reviewing` (question shown, "Show Answer" button)
///              → answer revealed + Again / Hard / Good / Easy buttons
///              → next card or `.empty`
///
/// `ReviewView` imports only `AnghkooeyCore` for `ReviewGrade` — it has no
/// direct FSRS or SwiftData imports.
public struct ReviewView: View {

    @Bindable var session: ReviewSession
    @State private var againTrigger = false
    @State private var hardTrigger = false
    @State private var goodTrigger = false
    @State private var easyTrigger = false
    @State private var dragOffset: CGSize = .zero
    @State private var isEditSheetPresented: Bool = false

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

    // MARK: - LTM banner (shared across reviewing + empty states)

    @ViewBuilder
    private var ltmBanner: some View {
        if session.ltmCount > 0 {
            Label("\(session.ltmCount) committed to long-term memory", systemImage: "brain.head.profile")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ltm-count-label")
        }
    }

    // MARK: - Reviewing

    private var reviewingBody: some View {
        VStack(spacing: 0) {
            HStack {
                ltmBanner
                Spacer()
                Text("\(session.remainingCount) left")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(session.remainingCount) cards remaining")
            }
            .padding(.top, 8)
            .padding(.horizontal)

            if session.isCushionActive {
                HStack(spacing: 8) {
                    Image(systemName: "cup.and.saucer.fill")
                        .foregroundStyle(.secondary)
                    Text("Showing today's batch — \(session.dailyBatchCap) of \(session.backlogTotal) due")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 8)
                .accessibilityElement(children: .combine)
            }

            if let card = session.currentCard {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        questionSection(card.question)
                        if session.isAnswerRevealed {
                            answerSection(card.answer)
                            mnemonicSection
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .overlay(swipeTintOverlay)
            }

            Divider()
            actionBar
        }
        .offset(x: dragOffset.width * 0.4, y: dragOffset.height * 0.4)
        .rotationEffect(.degrees(Double(dragOffset.width) / 25))
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { dragOffset = $0.translation }
                .onEnded { handleSwipeEnd($0) }
        )
        .sheet(isPresented: $isEditSheetPresented) {
            if let card = session.currentCard {
                CardEditSheet(
                    isPresented: $isEditSheetPresented,
                    card: card,
                    session: session
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.isAnswerRevealed)
    }

    // MARK: - Swipe helpers

    @ViewBuilder
    private var swipeTintOverlay: some View {
        let dx = dragOffset.width
        let dy = dragOffset.height
        let threshold: CGFloat = 80
        if abs(dx) > 10 || abs(dy) > 10 {
            if abs(dx) >= abs(dy) {
                Rectangle()
                    .fill(dx < 0 ? Color.red : Color.green)
                    .opacity(min(abs(dx) / threshold, 1.0) * 0.2)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            } else {
                Rectangle()
                    .fill(dy < 0 ? Color.blue : Color.secondary)
                    .opacity(min(abs(dy) / threshold, 1.0) * 0.18)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }

    private func handleSwipeEnd(_ value: DragGesture.Value) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dragOffset = .zero
        }
        let threshold: CGFloat = 80
        let minVelocity: CGFloat = 100
        let dx = value.translation.width
        let dy = value.translation.height

        // Diagonal dead zone: require clear axis dominance (1.5×) to
        // avoid misfiring on near-45° drags.
        guard abs(dx) > abs(dy) * 1.5 || abs(dy) > abs(dx) * 1.5 else { return }

        if abs(dx) >= abs(dy) {
            // Exclude iOS system left-edge back-swipe (~20pt zone).
            guard value.startLocation.x > 20 else { return }
            // Velocity guard: distinguishes deliberate swipe from content scroll.
            guard abs(value.velocity.width) >= minVelocity else { return }
            guard session.isAnswerRevealed else { return }
            if dx < -threshold {
                againTrigger.toggle()
                Task { await session.submit(grade: .again) }
            } else if dx > threshold {
                goodTrigger.toggle()
                Task { await session.submit(grade: .good) }
            }
        } else {
            guard abs(value.velocity.height) >= minVelocity else { return }
            if dy < -threshold {
                guard session.isAnswerRevealed else { return }
                easyTrigger.toggle()
                Task { await session.submit(grade: .easy) }
            } else if dy > threshold {
                isEditSheetPresented = true
            }
        }
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

    @ViewBuilder
    private var mnemonicSection: some View {
        if let mnemonic = session.currentMnemonic {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mnemonic")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(mnemonic)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if session.isMnemonicLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Generating mnemonic…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if session.isMnemonicAvailable {
            Button("Generate Mnemonic") {
                Task { await session.generateMnemonic() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.purple)
        }
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

    private func gradeButton(_ grade: ReviewGrade, title: String, systemImage: String, onTap: @escaping () -> Void) -> some View {
        let secs = session.currentIntervals[grade.fsrsRating]
        let intervalLabel = secs.map { IntervalProjection.label(seconds: $0) }
        return Button {
            onTap()
            Task { await session.submit(grade: grade) }
        } label: {
            VStack(spacing: 2) {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity)
                if let l = intervalLabel {
                    Text(l)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("next review in \(l)")
                }
            }
        }
        .controlSize(.large)
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
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                gradeButton(.again, title: "Again", systemImage: "arrow.counterclockwise") { againTrigger.toggle() }
                    .buttonStyle(.bordered).tint(.red)
                gradeButton(.hard, title: "Hard", systemImage: "minus.circle") { hardTrigger.toggle() }
                    .buttonStyle(.bordered).tint(.orange)
            }
            HStack(spacing: 8) {
                gradeButton(.good, title: "Good", systemImage: "checkmark") { goodTrigger.toggle() }
                    .buttonStyle(.borderedProminent)
                gradeButton(.easy, title: "Easy", systemImage: "star.fill") { easyTrigger.toggle() }
                    .buttonStyle(.borderedProminent).tint(.blue)
            }
        }
        .sensoryFeedback(.error, trigger: againTrigger)
        .sensoryFeedback(.impact(weight: .medium), trigger: hardTrigger)
        .sensoryFeedback(.success, trigger: goodTrigger)
        .sensoryFeedback(.success, trigger: easyTrigger)
    }

    // MARK: - Empty

    private var emptyBody: some View {
        VStack(spacing: 12) {
            ltmBanner
            ContentUnavailableView(
                "All caught up",
                systemImage: "checkmark.circle.fill",
                description: Text("Come back when your next review is due, or capture something new to grow your deck.")
            )
        }
    }
}

// MARK: - CardEditSheet

private struct CardEditSheet: View {
    @Binding var isPresented: Bool
    let card: Card.Snapshot
    let session: ReviewSession

    @State private var editedQuestion: String
    @State private var editedAnswer: String
    @State private var editedTags: [String]

    init(isPresented: Binding<Bool>, card: Card.Snapshot, session: ReviewSession) {
        _isPresented = isPresented
        self.card = card
        self.session = session
        _editedQuestion = State(initialValue: card.question)
        _editedAnswer = State(initialValue: card.answer)
        _editedTags = State(initialValue: card.tags)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextEditor(text: $editedQuestion)
                        .frame(minHeight: 80)
                }
                Section("Answer") {
                    TextEditor(text: $editedAnswer)
                        .frame(minHeight: 80)
                }
                Section("Tags") {
                    TagEditorView(tags: $editedTags)
                }
            }
            .navigationTitle("Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { @MainActor in
                            await session.submitEdit(
                                question: editedQuestion,
                                answer: editedAnswer,
                                tags: editedTags
                            )
                            isPresented = false
                        }
                    }
                }
            }
        }
    }
}
