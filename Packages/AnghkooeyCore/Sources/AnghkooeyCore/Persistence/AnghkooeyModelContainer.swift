import Foundation
import SwiftData

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
}
