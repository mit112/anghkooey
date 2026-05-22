import MetricKit
import OSLog

final class MetricsReceiver: NSObject, MXMetricManagerSubscriber {

    private let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.unknown.anghkooey",
        category: "MetricKit"
    )

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            log.info("MetricKit payload: \(payload.jsonRepresentation(), privacy: .public)")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            log.info("MetricKit diagnostic: \(payload.jsonRepresentation(), privacy: .public)")
        }
    }
}
