import Testing
import Foundation
@testable import AnghkooeyCore

// Reproducible benchmark behind PERFORMANCE.md §M8. Disabled in the suite;
// run manually with: swift test --filter OptimizerPerfMeasurement
// (after temporarily removing the .disabled trait, or via `swift test --enable-...`).
@Suite("Optimizer perf measurement", .disabled("benchmark — run manually for PERFORMANCE.md"))
struct OptimizerPerfMeasurement {
    private func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.resident_size : 0
    }

    @Test("measure optimize() wall-clock + memory on a seeded collection")
    func measure() async {
        for cards in [200, 400] {
            let dataset = SyntheticReviews.dataset(under: .default, cards: cards, seed: 7)
            let opt = LiveFSRSOptimizer()

            let memBefore = residentBytes()
            let start = Date()
            let result = await opt.optimize(dataset, from: .default, progress: { _ in })
            let elapsed = Date().timeIntervalSince(start)
            let memAfter = residentBytes()

            let deltaMB = memAfter >= memBefore ? Double(memAfter - memBefore) / 1_048_576.0 : 0
            let residentMB = Double(memAfter) / 1_048_576.0
            print("PERF cards=\(cards) eligible=\(dataset.eligibleSampleCount) " +
                  "wall=\(String(format: "%.2f", elapsed))s memΔ=\(String(format: "%.1f", deltaMB))MB " +
                  "resident=\(String(format: "%.0f", residentMB))MB " +
                  "baseline=\(String(format: "%.5f", result.baselineLoss)) " +
                  "optimized=\(String(format: "%.5f", result.optimizedLoss))")
        }
    }
}
