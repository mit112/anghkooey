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

struct AnghkooeyWidgetView: View {
    let entry: DueCardEntry

    var body: some View {
        if let snap = entry.snapshot {
            VStack(alignment: .leading, spacing: 8) {
                Text(snap.question)
                    .font(.footnote)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                if snap.dueCount > 1 {
                    Text("\(snap.dueCount - 1) more due")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        } else {
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
    }

    private func gradeIntent(snap: WidgetDueSnapshot, rating: Rating) -> GradeCardIntent {
        var intent = GradeCardIntent()
        intent.cardID = snap.cardID.uuidString
        intent.ratingRaw = rating.rawValue
        return intent
    }
}

// MARK: - Widget + Bundle

struct AnghkooeyReviewWidget: Widget {
    nonisolated(unsafe) static let kind: String = "AnghkooeyReviewWidget"

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
