import Foundation

/// Tunable parameters for the FSRS-6 scheduler.
///
/// The defaults are pinned verbatim to the `ts-fsrs v5.4.0` reference at
/// commit `80bab011a7f496b06c99924d54e772cf258244f2` — see
/// `docs/DECISIONS/0002-fsrs-reference.md`. Changing any default constant
/// here is a parity-harness breaker and requires a new ADR.
///
/// The 21-element `w` vector is the FSRS-6 weight set; older algorithm
/// versions (length 17 or 19) are not supported. Callers that need
/// personally-optimised parameters set them per-card by constructing a new
/// `FSRSParameters` value — `default` is intentionally immutable.
public struct FSRSParameters: Equatable, Sendable {
    /// 21-element weight vector. Length is invariant; see `Self.default`.
    public let w: [Double]

    /// Target retention probability used to invert the forgetting curve into
    /// the next interval. Range `(0, 1)`; `0.9` matches the upstream default.
    public let requestRetention: Double

    /// Hard cap on the integer-day interval, expressed in days. Mirrors the
    /// upstream maximum-interval setting.
    public let maximumInterval: Int

    /// When `true`, the scheduler perturbs the computed interval by a small
    /// random offset to spread review load. Disabled for parity / determinism.
    public let enableFuzz: Bool

    /// When `true`, the short-term learning/relearning step machine is active.
    /// Required by FSRS-6 default behavior; turning it off is for research only.
    public let enableShortTerm: Bool

    /// Learning-step durations in seconds. `[60, 600]` = `["1m", "10m"]`.
    public let learningStepsSeconds: [TimeInterval]

    /// Relearning-step durations in seconds. `[600]` = `["10m"]`.
    public let relearningStepsSeconds: [TimeInterval]

    /// Designated initializer. Does not validate `w.count == 21`; the engine
    /// is responsible for rejecting malformed parameter sets at construction
    /// time so unit tests can exercise the failure path explicitly.
    public init(
        w: [Double],
        requestRetention: Double,
        maximumInterval: Int,
        enableFuzz: Bool,
        enableShortTerm: Bool,
        learningStepsSeconds: [TimeInterval],
        relearningStepsSeconds: [TimeInterval]
    ) {
        self.w = w
        self.requestRetention = requestRetention
        self.maximumInterval = maximumInterval
        self.enableFuzz = enableFuzz
        self.enableShortTerm = enableShortTerm
        self.learningStepsSeconds = learningStepsSeconds
        self.relearningStepsSeconds = relearningStepsSeconds
    }

    /// Returns a copy of `self` with `w` replaced. Used to apply optimized
    /// weights onto the immutable `.default` configuration (retention,
    /// learning steps, etc. are preserved; only `w` is personalised).
    public func withWeights(_ newW: [Double]) -> FSRSParameters {
        FSRSParameters(
            w: newW,
            requestRetention: requestRetention,
            maximumInterval: maximumInterval,
            enableFuzz: enableFuzz,
            enableShortTerm: enableShortTerm,
            learningStepsSeconds: learningStepsSeconds,
            relearningStepsSeconds: relearningStepsSeconds
        )
    }

    /// FSRS-6 default parameters as pinned by ADR-0002.
    ///
    /// `w[20] = 0.1542` is the FSRS-6 default decay constant. Do not edit any
    /// value in this literal without bumping the ADR and regenerating the
    /// parity fixtures.
    public static let `default`: FSRSParameters = FSRSParameters(
        w: [
            0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001,
            1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014,
            1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
        ],
        requestRetention: 0.9,
        maximumInterval: 36_500,
        enableFuzz: false,
        enableShortTerm: true,
        learningStepsSeconds: [60, 600],
        relearningStepsSeconds: [600]
    )
}
