import UIKit
import AnghkooeyCore

/// Share Extension principal class.
///
/// Extracts the first plain-text or image payload from `extensionContext`,
/// writes it to the App Group inbox via `InboxWriter`, then dismisses.
/// Three UI states: saving → saved / error.
final class ShareViewController: UIViewController {

    // MARK: - UI

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        layoutSubviews()
        showSaving()
        Task { await processSharedContent() }
    }

    // MARK: - Layout

    private func layoutSubviews() {
        view.addSubview(activityIndicator)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),

            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    // MARK: - State

    private func showSaving() {
        activityIndicator.startAnimating()
        statusLabel.text = "Saving…"
    }

    private func showSaved() {
        activityIndicator.stopAnimating()
        statusLabel.text = "Saved to Anghkooey"
    }

    private func showError(_ message: String) {
        activityIndicator.stopAnimating()
        statusLabel.text = "Error: \(message)"
    }

    // MARK: - Processing

    private func processSharedContent() async {
        let signposter = CoreLog.poiSignposter
        let intervalState = signposter.beginInterval(
            "share-tap-to-inbox-write",
            id: signposter.makeSignpostID()
        )
        defer { signposter.endInterval("share-tap-to-inbox-write", intervalState) }

        guard let items = extensionContext?.inputItems as? [NSExtensionItem],
              let firstItem = items.first,
              let providers = firstItem.attachments else {
            showNothing()
            return
        }

        let sourceApp = Bundle.main.bundleIdentifier ?? "unknown"

        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: InboxConstants.appGroupID) else {
            showError("App Group unavailable")
            completeAfterDelay(success: false)
            return
        }

        let writer = InboxWriter(containerURL: containerURL)

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: "public.plain-text")
                    guard let text = item as? String else { continue }
                    try await writer.write(text: text, sourceApp: sourceApp)
                    showSaved()
                    completeAfterDelay(success: true)
                    return
                } catch {
                    showError(error.localizedDescription)
                    completeAfterDelay(success: false)
                    return
                }
            }

            if provider.hasItemConformingToTypeIdentifier("public.image") {
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: "public.image")
                    let data: Data?
                    if let url = item as? URL {
                        data = try Data(contentsOf: url)
                    } else if let image = item as? UIImage {
                        data = image.heicData() ?? image.jpegData(compressionQuality: 0.9)
                    } else {
                        data = nil
                    }
                    guard let imageData = data else { continue }
                    try await writer.write(imageData: imageData, sourceApp: sourceApp)
                    showSaved()
                    completeAfterDelay(success: true)
                    return
                } catch {
                    showError(error.localizedDescription)
                    completeAfterDelay(success: false)
                    return
                }
            }
        }

        showNothing()
    }

    private func showNothing() {
        activityIndicator.stopAnimating()
        statusLabel.text = "Nothing to capture"
        extensionContext?.cancelRequest(withError: NSError(
            domain: "com.mitsheth.anghkooey.share",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "No supported content found"]
        ))
    }

    private func completeAfterDelay(success: Bool) {
        Task {
            try? await Task.sleep(for: .seconds(success ? 1 : 2))
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
