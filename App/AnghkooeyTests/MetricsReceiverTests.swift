import Testing
import MetricKit
@testable import Anghkooey

@Suite("MetricsReceiver")
struct MetricsReceiverTests {

    @Test("init does not crash")
    func init_doesNotCrash() {
        _ = MetricsReceiver()
    }

    @Test("didReceive empty MXMetricPayload array does not crash")
    func didReceive_emptyMetricPayloads_doesNotCrash() {
        let receiver = MetricsReceiver()
        receiver.didReceive([] as [MXMetricPayload])
    }

    @Test("didReceive empty MXDiagnosticPayload array does not crash")
    func didReceive_emptyDiagnosticPayloads_doesNotCrash() {
        let receiver = MetricsReceiver()
        receiver.didReceive([] as [MXDiagnosticPayload])
    }
}
