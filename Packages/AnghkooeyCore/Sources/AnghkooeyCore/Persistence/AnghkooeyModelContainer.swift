import Foundation
import SwiftData

/// Where and how the persistent store is backed.
public enum SyncMode: Sendable, Equatable {
    /// On-device only. No iCloud. Default.
    case local
    /// SwiftData + CloudKit private database. `containerID` must match the
    /// provisioned iCloud container identifier.
    case cloudKit(containerID: String)
}

/// Factory for the package's `ModelContainer`.
///
/// Downstream packages and tests should create containers through this type
/// rather than constructing `ModelContainer` directly — keeping schema and
/// migration plan wiring in one place.
public enum AnghkooeyModelContainer {
    /// Builds an in-memory `ModelContainer` for tests and SwiftUI previews.
    ///
    /// - Throws: `PersistenceError.containerCreationFailed` if the container
    ///   cannot be created from the V1 schema + in-memory configuration.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: AnghkooeySchemaV3.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: AnghkooeyMigrationPlan.self,
                configurations: [configuration]
            )
            CoreLog.persistence.debug("In-memory ModelContainer created (v3 schema)")
            return container
        } catch {
            CoreLog.persistence.error(
                "ModelContainer init failed: \(error.localizedDescription, privacy: .public)"
            )
            throw PersistenceError.containerCreationFailed(underlying: error)
        }
    }

    /// The production CloudKit container identifier. See ADR-0011.
    public static let cloudKitContainerID = "iCloud.com.mitsheth.anghkooey"

    /// Builds the on-disk production container for the given sync mode.
    ///
    /// Both `.local` and `.cloudKit` use `AnghkooeySchemaV3` + `AnghkooeyMigrationPlan`
    /// so flipping the toggle never changes the schema — only the storage backend.
    ///
    /// - Parameter url: Explicit store URL (for tests). When `nil`, SwiftData uses
    ///   its default Application Support location.
    public static func makeContainer(syncMode: SyncMode, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: AnghkooeySchemaV3.self)
        let configuration: ModelConfiguration
        switch syncMode {
        case .local:
            configuration = url.map { ModelConfiguration(schema: schema, url: $0) }
                ?? ModelConfiguration(schema: schema)
        case .cloudKit(let containerID):
            configuration = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private(containerID)
            )
        }
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: AnghkooeyMigrationPlan.self,
                configurations: [configuration]
            )
            CoreLog.persistence.debug("ModelContainer created (syncMode: \(String(describing: syncMode), privacy: .public))")
            return container
        } catch {
            CoreLog.persistence.error("ModelContainer init failed: \(error.localizedDescription, privacy: .public)")
            throw PersistenceError.containerCreationFailed(underlying: error)
        }
    }
}
