import SwiftUI
import AnghkooeyCore

// MARK: - ViewModel

@MainActor
@Observable
public final class OptimizeScheduleViewModel {

    /// Explicit view states. Replaces the former ad-hoc
    /// `isUnlocked`/`isRunning`/`result` booleans so a store or save
    /// *failure* is its own case — never inferred as "genuinely locked" or
    /// silently coerced into "complete" (#27).
    public enum Phase: Equatable {
        case loading
        case locked(eligible: Int)
        case ready(eligible: Int)
        case running(progress: Double)
        case complete(OptimizationResult)
        case failed(String)
    }

    /// Which method produced the current `.failed` phase, so `retry()` can
    /// re-run the right one.
    private enum LastAction {
        case refresh
        case optimize
    }

    public private(set) var phase: Phase = .loading

    public let unlockThreshold: Int = OptimizedParametersStore.threshold

    /// Whether an `optimize()` run is currently in flight. Exposed so the
    /// view can disable the trigger buttons for the duration of a run —
    /// `phase` alone doesn't cover it, since `phase` is still `.ready`/
    /// `.failed` during the `await store.optimizationReviewLogs()`
    /// suspension at the top of `optimize()`, before it flips to `.running`
    /// (#27 fix 2).
    public private(set) var isOptimizing = false

    private let store: any CardStoreProtocol
    private let optimizer: any FSRSOptimizer
    private let paramsStore: any OptimizedParametersStoring
    private var lastAction: LastAction = .refresh

    /// Identifies the currently in-flight `optimize()` run so a progress
    /// tick from a *stale* run — one that hasn't been cancelled but whose
    /// `optimize()` call has already reached a terminal phase — can be
    /// told apart from a live one. See `optimize()` (#27 fix 1).
    private var currentRunID: UUID?

    public init(
        store: any CardStoreProtocol,
        optimizer: any FSRSOptimizer = LiveFSRSOptimizer(),
        paramsStore: any OptimizedParametersStoring
    ) {
        self.store = store
        self.optimizer = optimizer
        self.paramsStore = paramsStore
    }

    /// Loads the eligible review count and resolves locked vs ready.
    ///
    /// A store failure here becomes `.failed` — never `.locked`. Coercing an
    /// error to "not enough history" would lie to a heavy user (hundreds of
    /// reviews) who just hit a transient read failure (#27).
    public func refresh() async {
        lastAction = .refresh
        do {
            let rows = try await store.optimizationReviewLogs()
            let eligible = OptimizationDataset(rows: rows).eligibleSampleCount
            phase = eligible >= unlockThreshold ? .ready(eligible: eligible) : .locked(eligible: eligible)
        } catch {
            UILog.optimization.error("Failed to load review history: \(error)")
            phase = .failed("Couldn't load your review history. Try again.")
        }
    }

    /// Runs the optimizer against the current review history, then persists
    /// the fitted parameters.
    ///
    /// `.complete` is only reached once `paramsStore.save` has actually
    /// succeeded. A save failure after a perfectly good optimization run is
    /// surfaced as `.failed` — the "complete" copy must never be shown for
    /// params that were never written, or the next launch silently reverts
    /// to defaults with no indication anything went wrong (#27).
    ///
    /// Guarded against reentrancy (`isOptimizing`) and against a stale
    /// progress tick clobbering the terminal phase (`currentRunID`) — see
    /// the property docs for both (#27 fix 1 / fix 2).
    public func optimize() async {
        guard !isOptimizing else { return }
        isOptimizing = true
        defer { isOptimizing = false }

        lastAction = .optimize
        let runID = UUID()
        currentRunID = runID

        let rows: [OptimizationReviewLogRow]
        do {
            rows = try await store.optimizationReviewLogs()
        } catch {
            UILog.optimization.error("Failed to load review history for optimization: \(error)")
            currentRunID = nil
            phase = .failed("Couldn't load your review history. Try again.")
            return
        }
        let dataset = OptimizationDataset(rows: rows)
        phase = .running(progress: 0)
        let r = await optimizer.optimize(dataset, from: .default) { [weak self] p in
            Task { @MainActor [weak self] in
                // `LiveFSRSOptimizer`/`MockFSRSOptimizer` have no internal
                // suspension, so the whole run — including every progress
                // callback — executes synchronously on the MainActor before
                // this enqueued Task ever gets a chance to run. By the time
                // it does, `optimize()` has already reached its terminal
                // phase and invalidated `currentRunID`; without this check
                // the stale tick would overwrite `.complete`/`.failed` with
                // `.running(p)`, leaving the UI stuck on a progress bar with
                // no way to reach the results screen (#27 fix 1).
                guard let self, self.currentRunID == runID else { return }
                self.phase = .running(progress: p)
            }
        }
        do {
            try paramsStore.save(r.optimizedParameters)
        } catch {
            UILog.optimization.error("Failed to save optimized parameters: \(error)")
            currentRunID = nil
            phase = .failed("Optimization ran but couldn't be saved — try again.")
            return
        }
        currentRunID = nil
        phase = .complete(r)
    }

    /// Re-runs whichever of `refresh()`/`optimize()` produced the current
    /// `.failed` phase, so the error view's single Retry button does the
    /// right thing regardless of which path failed (#27).
    public func retry() async {
        switch lastAction {
        case .refresh: await refresh()
        case .optimize: await optimize()
        }
    }
}

// MARK: - View

/// Trigger, progress, before/after summary, and locked empty state for the
/// personal FSRS optimization feature. Host the view in a settings/profile
/// screen and pass `onOptimized` to call `appState.refreshScheduler()` after a
/// successful run so new scheduling picks up the saved params.
public struct OptimizeScheduleView: View {
    @State private var vm: OptimizeScheduleViewModel
    let onOptimized: () async -> Void

    public init(
        store: any CardStoreProtocol,
        paramsStore: OptimizedParametersStore,
        optimizer: any FSRSOptimizer = LiveFSRSOptimizer(),
        onOptimized: @escaping () async -> Void = {}
    ) {
        _vm = State(initialValue: OptimizeScheduleViewModel(
            store: store, optimizer: optimizer, paramsStore: paramsStore))
        self.onOptimized = onOptimized
    }

    public var body: some View {
        VStack(spacing: 16) {
            switch vm.phase {
            case .loading:
                ProgressView()
            case let .locked(eligible):
                lockedView(eligible: eligible)
            case .ready:
                readyView
            case let .running(progress):
                runningView(progress: progress)
            case let .complete(result):
                completeView(result)
            case let .failed(message):
                errorView(message: message)
            }
        }
        .padding()
        .task { await vm.refresh() }
    }

    private func lockedView(eligible: Int) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Not enough review history yet")
                .font(.headline)
            Text("Unlocks at \(vm.unlockThreshold) reviews (\(eligible) so far)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var readyView: some View {
        Button("Optimize my schedule") {
            Task {
                await vm.optimize()
                await onOptimized()
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(vm.isOptimizing)
    }

    private func runningView(progress: Double) -> some View {
        VStack(spacing: 12) {
            ProgressView(value: progress)
            Text("Optimizing…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func completeView(_ r: OptimizationResult) -> some View {
        VStack(spacing: 12) {
            Button("Optimize again") {
                Task {
                    await vm.optimize()
                    await onOptimized()
                }
            }
            .buttonStyle(.borderedProminent)

            resultView(r)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await vm.retry() }
            }
            .buttonStyle(.bordered)
            .disabled(vm.isOptimizing)
        }
    }

    private func resultView(_ r: OptimizationResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Optimization complete")
                .font(.headline)
            resultRow("Baseline loss", value: r.baselineLoss)
            resultRow("Optimized loss", value: r.optimizedLoss)
            resultRow("Achieved retention", value: r.achievedRetention)
            let changed = r.weightDeltas.filter { abs($0) > 1e-6 }.count
            Text("\(changed) of 21 weights updated")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func resultRow(_ label: String, value: Double) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.4f", value))
        }
        .font(.caption)
    }
}
