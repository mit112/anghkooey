import Foundation

/// Minimal seam over "persist an optimized FSRS-6 weight set" so callers
/// (e.g. `OptimizeScheduleViewModel`) can inject a mock and exercise the
/// save-failure path without touching the filesystem (#27).
public protocol OptimizedParametersStoring: Sendable {
    func save(_ parameters: FSRSParameters) throws
}

/// Failure modes for `OptimizedParametersStore.readValidatedParameters()`.
///
/// Distinct from "no file present yet" (the normal, silent case) — this
/// error only fires when a file exists but is unusable, so callers can log
/// diagnostics instead of silently reverting to defaults (#85).
public enum OptimizedParametersLoadError: Error, Equatable {
    case invalidWeightCount(Int)
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

    /// Reads, decodes, and validates the persisted weight blob.
    ///
    /// Throws (rather than swallowing) so `loadOptimized()` can distinguish
    /// "no file yet" (expected) from "file present but corrupt/wrong-shape"
    /// (worth logging) — see #85.
    internal func readValidatedParameters() throws -> FSRSParameters {
        let data = try Data(contentsOf: fileURL)
        let blob = try JSONDecoder().decode(Blob.self, from: data)
        guard blob.w.count == 21 else {
            throw OptimizedParametersLoadError.invalidWeightCount(blob.w.count)
        }
        return FSRSParameters.default.withWeights(blob.w)
    }

    /// The stored optimized set, or `nil` if none persisted / unreadable.
    ///
    /// A missing file is the normal "no optimization run yet" state and
    /// returns `nil` silently. A present-but-unusable file is logged before
    /// falling back to `nil` so a corrupt store doesn't silently discard the
    /// user's optimization with zero diagnostic (#85).
    public func loadOptimized() -> FSRSParameters? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try readValidatedParameters()
        } catch {
            CoreLog.scheduling.error("Optimized FSRS params present but unusable (\(error.localizedDescription, privacy: .public)); reverting to defaults")
            return nil
        }
    }

    /// Returns optimized params at or above threshold, `.default` otherwise.
    public func resolveParameters(eligibleSampleCount: Int) -> FSRSParameters {
        guard eligibleSampleCount >= Self.threshold, let optimized = loadOptimized() else {
            return .default
        }
        return optimized
    }
}
