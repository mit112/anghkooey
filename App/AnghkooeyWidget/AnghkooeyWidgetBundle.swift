import WidgetKit
import SwiftUI
import AppIntents
import AnghkooeyCore

// MARK: - Timeline Entry

struct DueCardEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetDueSnapshot?
}

// MARK: - Timeline Provider

struct DueCardProvider: TimelineProvider {
    func placeholder(in context: Context) -> DueCardEntry {
        DueCardEntry(date: .now, snapshot: WidgetDueSnapshot(
            cardID: UUID(), question: "What is the capital of France?", dueCount: 3))
    }

    func getSnapshot(in context: Context, completion: @escaping (DueCardEntry) -> Void) {
        completion(DueCardEntry(date: .now, snapshot: bridgeSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DueCardEntry>) -> Void) {
        let entry = DueCardEntry(date: .now, snapshot: bridgeSnapshot())
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func bridgeSnapshot() -> WidgetDueSnapshot? {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: InboxConstants.appGroupID)
        else { return nil }
        return WidgetBridge(containerURL: containerURL).readSnapshot()
    }
}

// MARK: - Widget View

/// Two-stage widget: an unrevealed card shows only the question and a
/// "Show answer" button; once `revealed`, the answer and the Again/Good
/// grade buttons appear. A snapshot's `needsAppToContinue` sentinel (queue
/// exhausted locally, but more cards are due per the app) renders distinctly
/// from the genuinely-empty "All caught up" state (`entry.snapshot == nil`).
struct AnghkooeyWidgetView: View {
    let entry: DueCardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snap = entry.snapshot {
            if snap.needsAppToContinue {
                openAppToContinueView(snap: snap)
            } else if snap.revealed == true {
                revealedView(snap: snap)
            } else {
                questionOnlyView(snap: snap)
            }
        } else {
            allCaughtUpView
        }
    }

    /// Stage 1: question only, no grade buttons yet.
    private func questionOnlyView(snap: WidgetDueSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snap.question)
                .font(.footnote)
                .lineLimit(family == .systemSmall ? 3 : 5)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
            Button(intent: revealIntent(snap: snap)) {
                Text("Show answer")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            dueCountFooter(snap: snap)
        }
        .padding(12)
    }

    /// Stage 2: question + answer + Again/Good.
    private func revealedView(snap: WidgetDueSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snap.question)
                .font(.footnote)
                .lineLimit(family == .systemSmall ? 2 : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let answer = snap.answer {
                Text(answer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(family == .systemSmall ? 2 : 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                Button(intent: gradeIntent(snap: snap, rating: .again)) {
                    Text("Again")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                Button(intent: gradeIntent(snap: snap, rating: .good)) {
                    Text("Good")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            dueCountFooter(snap: snap)
        }
        .padding(12)
    }

    @ViewBuilder
    private func dueCountFooter(snap: WidgetDueSnapshot) -> some View {
        if snap.dueCount > 1 {
            Text("\(snap.dueCount - 1) more due")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var allCaughtUpView: some View {
        VStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            Text("All caught up")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Queue exhausted locally but `dueCount > 0` per the app: distinct from
    /// "All caught up" so the user knows there's more to review, just not
    /// locally cached for the widget to advance through.
    private func openAppToContinueView(snap: WidgetDueSnapshot) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.up.forward.app.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            Text("Open app to continue")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("\(snap.dueCount) due")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func gradeIntent(snap: WidgetDueSnapshot, rating: Rating) -> GradeCardIntent {
        let intent = GradeCardIntent()
        intent.cardID = snap.cardID.uuidString
        intent.ratingRaw = rating.rawValue
        return intent
    }

    private func revealIntent(snap: WidgetDueSnapshot) -> RevealAnswerIntent {
        let intent = RevealAnswerIntent()
        intent.cardID = snap.cardID.uuidString
        return intent
    }
}

// MARK: - Widget + Bundle

struct AnghkooeyReviewWidget: Widget {
    nonisolated static let kind: String = "AnghkooeyReviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: DueCardProvider()) { entry in
            AnghkooeyWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Review Cards")
        .description("Review your most due card right from your home screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct AnghkooeyWidgetBundle: WidgetBundle {
    var body: some Widget {
        AnghkooeyReviewWidget()
    }
}
