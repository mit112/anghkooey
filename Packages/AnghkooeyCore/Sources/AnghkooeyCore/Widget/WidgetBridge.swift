import Foundation

public struct WidgetDueSnapshot: Codable, Equatable, Sendable {
    public let cardID: UUID
    public let question: String
    public let dueCount: Int
    public init(cardID: UUID, question: String, dueCount: Int) {
        self.cardID = cardID
        self.question = question
        self.dueCount = dueCount
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
        let line = try Self.encoder.encode(decision)
        if let handle = try? FileHandle(forWritingTo: gradesURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.write(contentsOf: Data("\n".utf8))
        } else {
            var blob = line; blob.append(Data("\n".utf8))
            try blob.write(to: gradesURL)
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
