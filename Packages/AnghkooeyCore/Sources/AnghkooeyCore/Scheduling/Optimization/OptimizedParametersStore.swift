import Foundation

/// Minimal seam over "persist an optimized FSRS-6 weight set" so callers
/// (e.g. `OptimizeScheduleViewModel`) can inject a mock and exercise the
/// save-failure path without touching the filesystem (#27).
public protocol OptimizedParametersStoring: Sendable {
    func save(_ parameters: FSRSParameters) throws
}

/// Persists one global optimized FSRS-6 weight set and resolves
/// optimized-or-default at the scheduling call site.
///
/// Stored as JSON in the app-group container so the widget extension reads the
/// same file. Only `w` is persisted; everything else is rebuilt onto
/// `FSRSParameters.default` (which stays ADR-0002-immutable).
public struct OptimizedParametersStore: Sendable, OptimizedParametersStoring {
    /// Eligible-sample count below which `.default` is always used.
    public static let threshold = 512

    private let fileURL: URL

    public init(containerURL: URL) {
        self.fileURL = containerURL.appendingPathComponent("optimized-fsrs-params.json")
    }

    private struct Blob: Codable { let w: [Double] }

    public func save(_ parameters: FSRSParameters) throws {
        let data = try JSONEncoder().encode(Blob(w: parameters.w))
        try data.write(to: fileURL, options: .atomic)
    }

    /// The stored optimized set, or `nil` if none persisted / unreadable.
    public func loadOptimized() -> FSRSParameters? {
        guard let data = try? Data(contentsOf: fileURL),
              let blob = try? JSONDecoder().decode(Blob.self, from: data),
              blob.w.count == 21 else { return nil }
        return FSRSParameters.default.withWeights(blob.w)
    }

    /// Returns optimized params at or above threshold, `.default` otherwise.
    public func resolveParameters(eligibleSampleCount: Int) -> FSRSParameters {
        guard eligibleSampleCount >= Self.threshold, let optimized = loadOptimized() else {
            return .default
        }
        return optimized
    }
}
