import Foundation

/// A next-up due card carried inside ``WidgetDueSnapshot/queue`` so the
/// widget extension can advance locally (Again/Good taps) between the app's
/// authoritative rewrites, without round-tripping to the store.
public struct WidgetCardRef: Codable, Equatable, Sendable {
    public let cardID: UUID
    public let question: String
    public let answer: String
    public init(cardID: UUID, question: String, answer: String) {
        self.cardID = cardID
        self.question = question
        self.answer = answer
    }
}

/// Decodes a single array element via `try?`, producing `nil` instead of
/// throwing when that one element is malformed. Used to make
/// `WidgetDueSnapshot.queue` decode "lossily": one corrupt queued card
/// degrades to "drop that card" rather than failing the whole snapshot
/// decode (which would otherwise also lose the current card + answer).
private struct FailableDecodable<Wrapped: Decodable>: Decodable {
    let value: Wrapped?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(Wrapped.self)
    }
}

/// Widget snapshot written by the app (authoritative) and read by the
/// widget extension. The widget never writes this directly except to
/// optimistically advance `cardID`/`question`/`answer`/`revealed`/`queue`
/// between app-driven rewrites (see `WidgetDueSnapshot.advancing` and
/// `.revealing` below) — the next `WidgetGradeReconciler.rewriteSnapshot()`
/// self-corrects any drift, so the widget is never a second source of truth.
///
/// Schema is additive-optional and carries NO version field: `answer`,
/// `revealed`, and `queue` are all optional so an old snapshot written by a
/// previous app build (or corrupted queue entries) still decodes — see the
/// custom `init(from:)` below.
public struct WidgetDueSnapshot: Codable, Equatable, Sendable {
    public let cardID: UUID
    public let question: String
    public let dueCount: Int
    /// The current card's answer, for the reveal step. `nil` for
    /// pre-M2-widget-reveal snapshots.
    public let answer: String?
    /// Whether the current card's answer has been revealed. `nil` is
    /// treated the same as `false` (not yet revealed).
    public let revealed: Bool?
    /// Up to ~5 upcoming due cards, in due order, for local widget advance.
    /// `nil`/empty means "no more locally-known cards" — NOT "no more due
    /// cards"; see `dueCount` for the true remaining total.
    public let queue: [WidgetCardRef]?

    public init(
        cardID: UUID,
        question: String,
        dueCount: Int,
        answer: String? = nil,
        revealed: Bool? = nil,
        queue: [WidgetCardRef]? = nil
    ) {
        self.cardID = cardID
        self.question = question
        self.dueCount = dueCount
        self.answer = answer
        self.revealed = revealed
        self.queue = queue
    }

    private enum CodingKeys: String, CodingKey {
        case cardID, question, dueCount, answer, revealed, queue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cardID = try container.decode(UUID.self, forKey: .cardID)
        question = try container.decode(String.self, forKey: .question)
        dueCount = try container.decode(Int.self, forKey: .dueCount)
        answer = try container.decodeIfPresent(String.self, forKey: .answer)
        revealed = try container.decodeIfPresent(Bool.self, forKey: .revealed)
        // Lossy: a malformed `queue` (bad element, or the wrong shape
        // entirely) degrades to `nil` rather than failing the whole decode.
        // `try?` flattens `decodeIfPresent`'s optional, so `wrapped` is
        // `[FailableDecodable<WidgetCardRef>]?`: `nil` if the key is
        // missing/null OR if the value isn't array-shaped at all (e.g. a
        // string). A present, array-shaped value with a malformed element
        // still decodes — that element's `.value` is `nil` and is dropped
        // by `compactMap`.
        let wrapped = try? container.decodeIfPresent([FailableDecodable<WidgetCardRef>].self, forKey: .queue)
        queue = wrapped?.compactMap(\.value)
    }
}

// MARK: - Local (widget-side) advance/reveal

/// Outcome of locally advancing a snapshot after a widget grade tap.
public enum WidgetAdvanceOutcome: Equatable, Sendable {
    /// `gradedCardID` didn't match the snapshot's current card — a
    /// stale/duplicate tap. The caller must NOT append a grade decision and
    /// must NOT write a snapshot.
    case staleTap
    /// No due cards remain locally or otherwise; the caller should
    /// `clearSnapshot()` ("All caught up").
    case allCaughtUp
    /// Advance succeeded; the caller should write this snapshot.
    case advanced(WidgetDueSnapshot)
}

public extension WidgetDueSnapshot {
    /// Sentinel `cardID` marking "queue exhausted, but the app's authoritative
    /// `dueCount` says more cards are due" — distinct from a `nil` snapshot
    /// (`readSnapshot() == nil`), which means genuinely nothing is due
    /// ("All caught up"). The widget renders this sentinel as
    /// "Open app to continue" rather than a (possibly stale) empty question.
    static let noLocalCardSentinel = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// True when this snapshot is the "queue exhausted, more due, waiting on
    /// the app to reconcile" sentinel state described above.
    var needsAppToContinue: Bool {
        cardID == Self.noLocalCardSentinel && dueCount > 0
    }

    /// Locally advances `current` after grading `gradedCardID`, without
    /// touching the store. The widget is never authoritative — the app's
    /// `WidgetGradeReconciler.rewriteSnapshot()` overwrites this on the next
    /// foreground/reconcile pass and self-corrects any drift — so this only
    /// exists to keep the widget responsive between taps.
    static func advancing(from current: WidgetDueSnapshot?, gradedCardID: UUID) -> WidgetAdvanceOutcome {
        guard let current, current.cardID == gradedCardID else { return .staleTap }
        let newDueCount = max(current.dueCount - 1, 0)
        var remainingQueue = current.queue ?? []
        if remainingQueue.isEmpty {
            if newDueCount == 0 {
                return .allCaughtUp
            } else {
                return .advanced(WidgetDueSnapshot(
                    cardID: Self.noLocalCardSentinel, question: "", dueCount: newDueCount
                ))
            }
        }
        let next = remainingQueue.removeFirst()
        return .advanced(WidgetDueSnapshot(
            cardID: next.cardID,
            question: next.question,
            dueCount: newDueCount,
            answer: next.answer,
            revealed: false,
            queue: remainingQueue
        ))
    }

    /// Locally marks `current`'s card as revealed, guarding against a
    /// stale/duplicate tap (the widget already advanced to a different card
    /// since this button was rendered).
    /// - Returns: `nil` if `current` is `nil` or its `cardID` doesn't match
    ///   `cardID` — the caller must no-op (no write, no reload) in that case.
    static func revealing(current: WidgetDueSnapshot?, cardID: UUID) -> WidgetDueSnapshot? {
        guard let current, current.cardID == cardID else { return nil }
        return WidgetDueSnapshot(
            cardID: current.cardID,
            question: current.question,
            dueCount: current.dueCount,
            answer: current.answer,
            revealed: true,
            queue: current.queue
        )
    }
}

public struct WidgetGradeDecision: Codable, Equatable, Sendable {
    public let id: UUID
    public let cardID: UUID
    public let rating: Rating
    public let decidedAt: Date
    public init(id: UUID, cardID: UUID, rating: Rating, decidedAt: Date) {
        self.id = id
        self.cardID = cardID
        self.rating = rating
        self.decidedAt = decidedAt
    }
}

/// Errors thrown by `WidgetBridge`'s atomic grade append.
public enum WidgetBridgeError: Error, Sendable, Equatable {
    /// `open(O_WRONLY|O_APPEND|O_CREAT)` on `grades.jsonl` failed.
    case appendOpenFailed(errno: Int32)
    /// The append `write()` returned an error or a short write.
    case appendWriteFailed(errno: Int32)
}

public struct WidgetBridge: Sendable {

    private let containerURL: URL
    public init(containerURL: URL) { self.containerURL = containerURL }

    private var widgetDir: URL { containerURL.appendingPathComponent("widget", isDirectory: true) }
    private var snapshotURL: URL { widgetDir.appendingPathComponent("due-snapshot.json") }
    private var gradesURL: URL { widgetDir.appendingPathComponent("grades.jsonl") }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    private func ensureDir() throws {
        try FileManager.default.createDirectory(at: widgetDir, withIntermediateDirectories: true)
    }

    public func writeSnapshot(_ snapshot: WidgetDueSnapshot) throws {
        try ensureDir()
        let data = try Self.encoder.encode(snapshot)
        let tmp = snapshotURL.appendingPathExtension("tmp")
        try data.write(to: tmp)
        _ = try? FileManager.default.removeItem(at: snapshotURL)
        try FileManager.default.moveItem(at: tmp, to: snapshotURL)
    }

    public func readSnapshot() -> WidgetDueSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? Self.decoder.decode(WidgetDueSnapshot.self, from: data)
    }

    public func clearSnapshot() throws {
        _ = try? FileManager.default.removeItem(at: snapshotURL)
    }

    public func appendGrade(_ decision: WidgetGradeDecision) throws {
        try ensureDir()
        var line = try Self.encoder.encode(decision)
        line.append(0x0A) // "\n"
        // Atomic append via O_APPEND: the kernel positions each write() at the
        // current end-of-file as part of the same operation, so two widget-
        // process grade taps racing on grades.jsonl append two *whole* lines
        // rather than interleaving bytes into one corrupt line (which
        // `readGrades`'s per-line `try? decode` would then silently drop — a
        // lost grade). The prior `seekToEnd()`-then-`write()` left a window
        // between the seek and the write for exactly that clobber. O_CREAT
        // replaces the old "FileHandle open failed → write whole file"
        // fallback. The single write() of a small one-line payload is itself
        // atomic; a short write is treated as a failure rather than retried
        // (a retry would re-append at EOF and could interleave).
        let fd = open(gradesURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw WidgetBridgeError.appendOpenFailed(errno: errno) }
        defer { close(fd) }
        let written = line.withUnsafeBytes { raw in
            write(fd, raw.baseAddress, raw.count)
        }
        guard written == line.count else {
            throw WidgetBridgeError.appendWriteFailed(errno: errno)
        }
    }

    public func readGrades() -> [WidgetGradeDecision] {
        guard let data = try? Data(contentsOf: gradesURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let lineData = line.data(using: .utf8) else { return nil }
            return try? Self.decoder.decode(WidgetGradeDecision.self, from: lineData)
        }
    }

    public func clearGrades() throws {
        _ = try? FileManager.default.removeItem(at: gradesURL)
    }
}
