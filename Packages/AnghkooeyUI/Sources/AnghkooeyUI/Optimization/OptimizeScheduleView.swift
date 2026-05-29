import SwiftUI
import AnghkooeyCore

// MARK: - ViewModel

@MainActor
@Observable
public final class OptimizeScheduleViewModel {
    public private(set) var eligibleSampleCount: Int = 0
    public private(set) var isRunning: Bool = false
    public private(set) var progress: Double = 0
    public private(set) var result: OptimizationResult?

    public let unlockThreshold: Int = OptimizedParametersStore.threshold
    public var isUnlocked: Bool { eligibleSampleCount >= unlockThreshold }

    private let store: any CardStoreProtocol
    private let optimizer: any FSRSOptimizer
    private let paramsStore: OptimizedParametersStore

    public init(
        store: any CardStoreProtocol,
        optimizer: any FSRSOptimizer = LiveFSRSOptimizer(),
        paramsStore: OptimizedParametersStore
    ) {
        self.store = store
        self.optimizer = optimizer
        self.paramsStore = paramsStore
    }

    public func refresh() async {
        let rows = (try? await store.optimizationReviewLogs()) ?? []
        eligibleSampleCount = OptimizationDataset(rows: rows).eligibleSampleCount
    }

    public func optimize() async {
        let rows = (try? await store.optimizationReviewLogs()) ?? []
        let dataset = OptimizationDataset(rows: rows)
        isRunning = true
        progress = 0
        let r = await optimizer.optimize(dataset, from: .default) { [weak self] p in
            Task { @MainActor [weak self] in self?.progress = p }
        }
        try? paramsStore.save(r.optimizedParameters)
        result = r
        isRunning = false
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
            if !vm.isUnlocked {
                lockedView
            } else {
                unlockedView
            }
        }
        .padding()
        .task { await vm.refresh() }
    }

    private var lockedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Not enough review history yet")
                .font(.headline)
            Text("Unlocks at \(vm.unlockThreshold) reviews (\(vm.eligibleSampleCount) so far)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var unlockedView: some View {
        VStack(spacing: 12) {
            if vm.isRunning {
                ProgressView(value: vm.progress)
                Text("Optimizing…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Button("Optimize my schedule") {
                    Task {
                        await vm.optimize()
                        await onOptimized()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isRunning)

                if let r = vm.result {
                    resultView(r)
                }
            }
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
