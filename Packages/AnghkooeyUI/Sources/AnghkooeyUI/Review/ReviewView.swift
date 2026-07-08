import SwiftUI
import AnghkooeyCore

/// Symbolic + textual swipe cue rendered by `ReviewView`'s swipe overlay
/// (#53). Color alone fails WCAG 1.4.1 ("Use of Color"), so every direction
/// pairs its tint with a SF Symbol and a label matching the equivalent
/// grade button (`.again`/`.good`/`.easy` mirror the Again/Good/Easy button
/// icons; `.edit` mirrors the down-swipe-to-edit affordance).
enum ReviewSwipeCue: Equatable, Sendable {
    case again, good, easy, edit

    var symbolName: String {
        switch self {
        case .again: "arrow.counterclockwise"
        case .good: "checkmark"
        case .easy: "star.fill"
        case .edit: "pencil"
        }
    }

    var label: String {
        switch self {
        case .again: "Again"
        case .good: "Good"
        case .easy: "Easy"
        case .edit: "Edit"
        }
    }

    var tint: Color {
        switch self {
        case .again: .red
        case .good: .green
        case .easy: .blue
        case .edit: .secondary
        }
    }
}

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
    private let loadSampleCards: (() async -> Void)?
    private let onImport: (() -> Void)?
    @State private var againTrigger = false
    @State private var hardTrigger = false
    @State private var goodTrigger = false
    @State private var easyTrigger = false
    @State private var dragOffset: CGSize = .zero
    @State private var isEditSheetPresented: Bool = false
    @State private var showingCreate = false
    /// Tracks whether `dragOffset` is currently past `swipeCommitThreshold`
    /// for an eligible direction. Drives the overlay's "committed" look and
    /// flips `swipeCommitTrigger` exactly on threshold crossings (#53).
    @State private var isPastCommitThreshold: Bool = false
    @State private var swipeCommitTrigger: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(session: ReviewSession,
                loadSampleCards: (() async -> Void)? = nil,
                onImport: (() -> Void)? = nil) {
        self.session = session
        self.loadSampleCards = loadSampleCards
        self.onImport = onImport
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
                            Divider()
                            answerSection(card.answer)
                            mnemonicSection
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(swipeTintOverlay)
            }

            Divider()
            actionBar
        }
        .offset(x: dragOffset.width * 0.4, y: dragOffset.height * 0.4)
        .rotationEffect(.degrees(Double(dragOffset.width) / 25))
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    dragOffset = value.translation
                    let committed = Self.isSwipeCommitted(
                        translation: value.translation,
                        isAnswerRevealed: session.isAnswerRevealed
                    )
                    if committed != isPastCommitThreshold {
                        isPastCommitThreshold = committed
                        swipeCommitTrigger.toggle()
                    }
                }
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
        // Haptic fires exactly on threshold-crossing (#53); doesn't fire on
        // Simulator, but the trigger path is correct.
        .sensoryFeedback(.impact(weight: .medium), trigger: swipeCommitTrigger)
    }

    // MARK: - Swipe helpers

    /// The displacement (in points) past which a swipe commits, shared by
    /// the cue overlay and `handleSwipeEnd` so the two can't drift apart
    /// (#53 anti-drift requirement).
    private static let swipeCommitThreshold: CGFloat = 80

    /// Below this displacement, no cue is shown at all — avoids flickering
    /// a cue on incidental micro-movements at gesture start.
    private static let swipeCueDeadzone: CGFloat = 10

    /// Pure mapping of a drag translation to the cue it will trigger, gated
    /// the same way `handleSwipeEnd` gates commits: grade cues (again/good/
    /// easy) require `isAnswerRevealed`; edit does not, since
    /// `handleSwipeEnd` never reveal-guards the down swipe. Returns `nil` in
    /// the small activation deadzone, in the ambiguous near-45° diagonal
    /// zone (dominant-axis rule, matching `handleSwipeEnd`'s 1.5× guard),
    /// and for grade directions before the answer is revealed — showing a
    /// grade cue there would be a false affordance since `handleSwipeEnd`
    /// won't commit a grade in that state.
    ///
    /// This reflects *displacement + axis + reveal* eligibility only.
    /// Velocity and `startLocation` are release-only and unknowable
    /// mid-drag, so a rare low-velocity (or left-edge) release past the
    /// threshold that `handleSwipeEnd` still rejects is an inherent,
    /// acceptable mismatch between the mid-drag cue and the eventual commit
    /// decision.
    ///
    /// Explicitly `nonisolated`: `ReviewView` conforms to `View`, whose
    /// `body` requirement is `@MainActor`, and Swift infers main-actor
    /// isolation onto the whole conforming type by default — including
    /// static members. Without this annotation, calling `swipeCue` from a
    /// non-main-actor context (e.g. a Swift Testing test function, which
    /// runs off the main actor) trips a runtime actor-isolation assertion.
    nonisolated static func swipeCue(translation: CGSize, isAnswerRevealed: Bool) -> ReviewSwipeCue? {
        let dx = translation.width
        let dy = translation.height

        guard abs(dx) > swipeCueDeadzone || abs(dy) > swipeCueDeadzone else { return nil }

        // Diagonal dead zone: require clear axis dominance (1.5x) to avoid
        // misfiring on near-45 degree drags — mirrors handleSwipeEnd.
        guard abs(dx) > abs(dy) * 1.5 || abs(dy) > abs(dx) * 1.5 else { return nil }

        if abs(dx) >= abs(dy) {
            guard isAnswerRevealed else { return nil }
            return dx < 0 ? .again : .good
        } else if dy < 0 {
            guard isAnswerRevealed else { return nil }
            return .easy
        } else {
            return .edit
        }
    }

    /// Whether `translation` has crossed `swipeCommitThreshold` for a cue
    /// that is actually eligible right now (see `swipeCue`). Built on top of
    /// `swipeCue` rather than duplicating its gating, per the anti-drift
    /// requirement that direction/eligibility logic live in one place.
    nonisolated static func isSwipeCommitted(translation: CGSize, isAnswerRevealed: Bool) -> Bool {
        guard swipeCue(translation: translation, isAnswerRevealed: isAnswerRevealed) != nil else { return false }
        // Strict `>` matches handleSwipeEnd's commit comparisons exactly, so the
        // "committed" cue can't promise a grade the release then rejects at the
        // exact threshold value.
        return max(abs(translation.width), abs(translation.height)) > swipeCommitThreshold
    }

    @ViewBuilder
    private var swipeTintOverlay: some View {
        if let cue = Self.swipeCue(translation: dragOffset, isAnswerRevealed: session.isAnswerRevealed) {
            let displacement = max(abs(dragOffset.width), abs(dragOffset.height))
            let progress = min(displacement / Self.swipeCommitThreshold, 1.0)
            let tintOpacity = (cue == .again || cue == .good) ? 0.2 : 0.18
            let isCommitted = isPastCommitThreshold

            ZStack {
                Rectangle()
                    .fill(cue.tint)
                    .opacity(progress * tintOpacity)

                VStack(spacing: 8) {
                    Image(systemName: cue.symbolName)
                        .font(.system(size: 36, weight: .bold))
                    Text(cue.label)
                        .font(.headline)
                }
                .foregroundStyle(cue.tint)
                .opacity(progress)
                .scaleEffect(reduceMotion ? 1.0 : (isCommitted ? 1.15 : 1.0))
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.65), value: isCommitted)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            // Decorative reinforcement of the grade/edit buttons below, which
            // already carry accessible labels — avoid a redundant, transient
            // VoiceOver stop mid-gesture.
            .accessibilityHidden(true)
        }
    }

    private func handleSwipeEnd(_ value: DragGesture.Value) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dragOffset = .zero
        }
        isPastCommitThreshold = false
        let minVelocity: CGFloat = 100
        let dx = value.translation.width
        let dy = value.translation.height

        // Direction, axis-dominance, and reveal-gating are single-sourced in
        // `swipeCue` so the mid-drag cue can never drift from what actually
        // commits here (#53). This adds only the guards that aren't knowable
        // mid-drag: the per-axis velocity floor, the iOS left-edge back-swipe
        // exclusion, and the commit threshold.
        guard let cue = Self.swipeCue(translation: value.translation, isAnswerRevealed: session.isAnswerRevealed) else { return }

        switch cue {
        case .again, .good:
            // Exclude iOS system left-edge back-swipe (~20pt zone).
            guard value.startLocation.x > 20 else { return }
            // Velocity guard: distinguishes a deliberate swipe from a content scroll.
            guard abs(value.velocity.width) >= minVelocity else { return }
            guard abs(dx) > Self.swipeCommitThreshold else { return }
            if cue == .again {
                againTrigger.toggle()
                Task { await session.submit(grade: .again) }
            } else {
                goodTrigger.toggle()
                Task { await session.submit(grade: .good) }
            }
        case .easy:
            guard abs(value.velocity.height) >= minVelocity else { return }
            guard dy < -Self.swipeCommitThreshold else { return }
            easyTrigger.toggle()
            Task { await session.submit(grade: .easy) }
        case .edit:
            guard abs(value.velocity.height) >= minVelocity else { return }
            guard dy > Self.swipeCommitThreshold else { return }
            isEditSheetPresented = true
        }
    }

    private func questionSection(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Question")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(question)
                .font(.title2)
                .fontWeight(.semibold)
        }
    }

    private func answerSection(_ answer: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Answer")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(answer)
                .font(.title3)
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

    /// VoiceOver-friendly copy for "next card due at `date`" (#18). Rounds up
    /// to whole minutes so "due in 61 seconds" doesn't misleadingly read as
    /// "now" — a user who trusts the copy and returns 60s early should still
    /// find the card ready by the time they act on it.
    private func nextDueCopy(for date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else {
            return "Next card is due now."
        }
        guard seconds >= 60 else {
            return "Next card in under a minute."
        }
        let minutes = Int((seconds / 60).rounded(.up))
        return "Next card in ~\(minutes) minute\(minutes == 1 ? "" : "s")."
    }

    private var emptyBody: some View {
        VStack(spacing: 12) {
            if session.totalCardCount == 0 {
                ContentUnavailableView {
                    Label("No cards yet", systemImage: "rectangle.stack")
                } description: {
                    Text("Add a card, import your Anki deck, or try a sample.")
                } actions: {
                    Button("Add a card") { showingCreate = true }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Add a new card")
                    Button("Import from Anki") { onImport?() }
                    if let loader = loadSampleCards {
                        Button("Load sample deck") { Task { await loader(); await session.loadDueQueue() } }
                    }
                }
            } else {
                if session.summary.reviewed > 0 {
                    VStack(spacing: 6) {
                        Text("Session complete")
                            .font(.headline)
                        Text("You reviewed **\(session.summary.reviewed)** card\(session.summary.reviewed == 1 ? "" : "s") · **\(session.summary.accuracyPercent)%** remembered")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                ltmBanner
                if let nextDueDate = session.nextDueDate {
                    ContentUnavailableView {
                        Label("Next card coming up", systemImage: "clock.fill")
                    } description: {
                        Text(nextDueCopy(for: nextDueDate))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(nextDueCopy(for: nextDueDate))
                } else {
                    ContentUnavailableView(
                        "All caught up",
                        systemImage: "checkmark.circle.fill",
                        description: Text("Come back when your next review is due, or capture something new to grow your deck.")
                    )
                }
            }
        }
        .sheet(isPresented: $showingCreate) {
            LibraryCardEditView(mode: .create, store: session.store) {
                Task { await session.loadDueQueue() }
            }
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
    // Own presenter, not the screen's: a screen-level `.errorToast` would be
    // hidden behind this sheet, so the sheet surfaces its own failures.
    @State private var errorPresenter = ErrorPresenter()
    @State private var isPresentingDeleteConfirm = false

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
                Section {
                    Button("Delete Card", role: .destructive) {
                        isPresentingDeleteConfirm = true
                    }
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
                        Task { @MainActor in await saveEdit() }
                    }
                }
            }
            .confirmationDialog(
                "Delete this card?",
                isPresented: $isPresentingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Card", role: .destructive) {
                    Task { @MainActor in await deleteCard() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
        .errorToast(errorPresenter)
    }

    /// Submits the current edit fields. On success, closes the sheet. On
    /// failure, keeps the sheet open with the entered text intact and offers
    /// a retry that re-runs this same save (#23 — no silent swallow).
    @MainActor
    private func saveEdit() async {
        do {
            try await session.submitEdit(
                cardID: card.id,
                question: editedQuestion,
                answer: editedAnswer,
                tags: editedTags
            )
            isPresented = false
        } catch {
            UILog.review.error("Card edit save failed: \(error)")
            errorPresenter.present(
                "Couldn't save your edit — try again.",
                retry: { await self.saveEdit() }
            )
        }
    }

    /// Deletes the card. On success, closes the sheet — `ReviewSession` has
    /// already advanced past it. On failure, keeps the sheet open and offers
    /// a retry that re-runs this same delete (#23-style — no silent swallow).
    @MainActor
    private func deleteCard() async {
        do {
            try await session.deleteCurrentCard(cardID: card.id)
            isPresented = false
        } catch {
            UILog.review.error("Card delete failed: \(error)")
            errorPresenter.present(
                "Couldn't delete the card — try again.",
                retry: { await self.deleteCard() }
            )
        }
    }
}
