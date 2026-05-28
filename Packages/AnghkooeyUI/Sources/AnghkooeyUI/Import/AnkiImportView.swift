import SwiftUI
import UniformTypeIdentifiers
import AnghkooeyCore

public struct AnkiImportView: View {

    private enum ImportState {
        case idle
        case scanning
        case confirm(AnkiScanResult)
        case importing(imported: Int, total: Int)
        case done(AnkiImportResult)
        case error(AnkiImportError)
    }

    let importer: any AnkiImporterProtocol
    @Binding var isPresented: Bool

    @State private var state: ImportState = .idle
    @State private var showingFilePicker = false
    @State private var pendingURL: URL?
    @State private var importTask: Task<Void, Never>?

    public init(importer: any AnkiImporterProtocol, isPresented: Binding<Bool>) {
        self.importer = importer
        self._isPresented = isPresented
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import from Anki")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if case .done = state { } else {
                            Button("Cancel") { cancelAndDismiss() }
                        }
                    }
                }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [UTType(importedAs: "com.ankimobile.apkg")],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                pendingURL = url
                Task { await beginScan(url: url) }
            case .failure:
                state = .error(.notAnApkgFile)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            idleView
        case .scanning:
            VStack(spacing: 16) {
                ProgressView()
                Text("Reading package…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .confirm(let scan):
            confirmView(scan: scan)
        case .importing(let imported, let total):
            importingView(imported: imported, total: total)
        case .done(let result):
            doneView(result: result)
        case .error(let error):
            errorView(error: error)
        }
    }

    private var idleView: some View {
        VStack(spacing: 24) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Import an Anki .apkg file.\nOnly Basic (Front/Back) cards are imported. Images are removed.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Choose File") { showingFilePicker = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func confirmView(scan: AnkiScanResult) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Found **\(scan.totalNotes)** cards")
            if scan.skippableNotes > 0 {
                Text("\(scan.skippableNotes) unsupported cards will be skipped.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            Text("Import up to 5,000 cards?")
            HStack(spacing: 16) {
                Button("Cancel") { state = .idle }
                    .buttonStyle(.bordered)
                Button("Import") {
                    guard let url = pendingURL else { return }
                    beginImport(url: url)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func importingView(imported: Int, total: Int) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(imported), total: Double(max(total, 1)))
                .padding(.horizontal)
            Text("Importing… \(imported) of \(total) cards")
                .foregroundStyle(.secondary)
            Button("Cancel") { importTask?.cancel(); state = .idle }
                .foregroundStyle(.red)
            Text("Already imported cards are kept. Re-importing this file will skip duplicates.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func doneView(result: AnkiImportResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Imported \(result.imported) cards")
                .font(.headline)
            Group {
                if result.skipped > 0 { Text("Skipped \(result.skipped) (unsupported type)") }
                if result.duplicates > 0 { Text("\(result.duplicates) duplicates skipped") }
                if result.truncated { Text("Truncated at 5,000 cards") }
            }
            .foregroundStyle(.secondary)
            .font(.subheadline)
            Button("Done") { isPresented = false }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(error: AnkiImportError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(errorMessage(for: error))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try Again") { state = .idle }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func beginScan(url: URL) async {
        state = .scanning
        do {
            let result = try await importer.scanPackage(at: url)
            state = .confirm(result)
        } catch let e as AnkiImportError {
            state = .error(e)
        } catch {
            state = .error(.corruptedArchive)
        }
    }

    private func beginImport(url: URL) {
        importTask = Task {
            do {
                for try await event in importer.importPackage(at: url, now: .now, maxCards: 5_000) {
                    switch event {
                    case .importing(let i, let t):
                        state = .importing(imported: i, total: t)
                    case .completed(let result):
                        state = .done(result)
                    }
                }
            } catch let e as AnkiImportError {
                state = .error(e)
            } catch {
                if !Task.isCancelled { state = .error(.corruptedArchive) }
            }
        }
    }

    private func cancelAndDismiss() {
        importTask?.cancel()
        isPresented = false
    }

    private func errorMessage(for error: AnkiImportError) -> String {
        switch error {
        case .notAnApkgFile:
            return "This file doesn't appear to be an Anki package (.apkg)."
        case .fileAccessDenied:
            return "Anghkooey couldn't access this file. Try moving it to a local folder first."
        case .corruptedArchive:
            return "The package file is corrupted or uses a newer format. In Anki, tap Export and choose '.apkg (legacy)' to create a compatible file."
        case .databaseCorrupted:
            return "The deck database inside this package couldn't be read."
        case .storeFailed:
            return "Something went wrong saving cards. Your existing cards are safe."
        }
    }
}
