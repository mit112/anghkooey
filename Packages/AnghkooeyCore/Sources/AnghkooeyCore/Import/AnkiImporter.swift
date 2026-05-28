import Foundation

// MARK: - Public result types

public struct AnkiScanResult: Sendable {
    public let totalNotes: Int
    public let skippableNotes: Int
    public let deckNames: [String]

    public init(totalNotes: Int, skippableNotes: Int, deckNames: [String]) {
        self.totalNotes = totalNotes
        self.skippableNotes = skippableNotes
        self.deckNames = deckNames
    }
}

public enum AnkiImportProgress: Sendable {
    case importing(imported: Int, total: Int)
    case completed(AnkiImportResult)
}

public struct AnkiImportResult: Sendable {
    public let imported: Int
    public let skipped: Int
    public let duplicates: Int
    public let truncated: Bool

    public init(imported: Int, skipped: Int, duplicates: Int, truncated: Bool) {
        self.imported = imported
        self.skipped = skipped
        self.duplicates = duplicates
        self.truncated = truncated
    }
}

// MARK: - Protocol

public protocol AnkiImporterProtocol: Sendable {
    func scanPackage(at url: URL) async throws -> AnkiScanResult
    func importPackage(
        at url: URL,
        now: Date,
        maxCards: Int
    ) -> AsyncThrowingStream<AnkiImportProgress, any Error>
}

// MARK: - Live implementation

public actor LiveAnkiImporter: AnkiImporterProtocol {

    private let store: any CardStoreProtocol

    public init(store: any CardStoreProtocol) {
        self.store = store
    }

    public func scanPackage(at url: URL) async throws -> AnkiScanResult {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let collection = try AnkiPackageParser.parse(apkgURL: url)
        let importedAt = Date.now
        var total = 0
        var skippable = 0
        for note in collection.notes {
            total += 1
            if AnkiNoteMapper.map(note: note, collection: collection, importedAt: importedAt) == nil {
                skippable += 1
            }
        }
        let names = Array(Set(collection.deckNames.values)).sorted()
        return AnkiScanResult(totalNotes: total, skippableNotes: skippable, deckNames: names)
    }

    public nonisolated func importPackage(
        at url: URL,
        now: Date,
        maxCards: Int = 5_000
    ) -> AsyncThrowingStream<AnkiImportProgress, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }

                    let collection = try AnkiPackageParser.parse(apkgURL: url)
                    let mappable = collection.notes.compactMap {
                        AnkiNoteMapper.map(note: $0, collection: collection, importedAt: now)
                    }
                    let total = mappable.count
                    let skipped = collection.notes.count - total

                    var imported = 0
                    var duplicates = 0
                    var truncated = false

                    for card in mappable {
                        if imported >= maxCards { truncated = true; break }
                        if try await store.findBySourceSpan(card.sourceSpan) != nil {
                            duplicates += 1
                            continue
                        }
                        do {
                            _ = try await store.createImported(
                                question: card.question,
                                answer: card.answer,
                                sourceSpan: card.sourceSpan,
                                tags: card.tags,
                                dueAt: card.dueAt,
                                now: now
                            )
                        } catch {
                            throw AnkiImportError.storeFailed(underlying: error)
                        }
                        imported += 1
                        continuation.yield(.importing(imported: imported, total: total))
                    }

                    continuation.yield(.completed(AnkiImportResult(
                        imported: imported,
                        skipped: skipped,
                        duplicates: duplicates,
                        truncated: truncated
                    )))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Mock

public final class MockAnkiImporter: AnkiImporterProtocol, @unchecked Sendable {

    public var scanResult = AnkiScanResult(totalNotes: 0, skippableNotes: 0, deckNames: [])
    public var scanError: Error?
    public var importEvents: [AnkiImportProgress] = []
    public var importError: Error?

    public init() {}

    public func scanPackage(at url: URL) async throws -> AnkiScanResult {
        if let err = scanError { throw err }
        return scanResult
    }

    public func importPackage(
        at url: URL,
        now: Date,
        maxCards: Int
    ) -> AsyncThrowingStream<AnkiImportProgress, any Error> {
        let events = importEvents
        let error = importError
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            if let error { continuation.finish(throwing: error) } else { continuation.finish() }
        }
    }
}
