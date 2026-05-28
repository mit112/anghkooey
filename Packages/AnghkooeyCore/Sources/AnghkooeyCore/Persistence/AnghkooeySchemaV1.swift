import Foundation
import SwiftData

/// V1 of the Anghkooey persistence schema.
///
/// Lists every `@Model` type that ships in the first release. Adding a new
/// model or changing an existing model's stored properties requires either
/// extending this schema (additive, no migration stage) or declaring a new
/// `AnghkooeySchemaV2` and a `MigrationStage` between them.
public enum AnghkooeySchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        // ReviewLog and Tag are unversioned; they only appear in the latest
        // schema (V3). Listing them in every version causes CoreData to see
        // duplicate checksums and throw NSInvalidArgumentException at init.
        [AnghkooeySchemaV1.Card.self]
    }
}

/// Migration plan for the Anghkooey persistence store.
///
/// V1 has no prior schema, so `stages` is empty. The scaffolding exists from
/// day one so the call-site shape never changes when V2 lands.
public enum AnghkooeyMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [AnghkooeySchemaV1.self, AnghkooeySchemaV2.self, AnghkooeySchemaV3.self]
    }

    public static var stages: [MigrationStage] {
        [
            // Step-machine fields are optional in V2 so V1-era rows get NULL
            // (not a validation error). Callers read through Card.Snapshot
            // which collapses nil → 0 via ?? 0.
            .lightweight(
                fromVersion: AnghkooeySchemaV1.self,
                toVersion: AnghkooeySchemaV2.self
            ),
            // mnemonic is Optional in V3 so V2-era rows get NULL — no copy logic needed.
            .lightweight(
                fromVersion: AnghkooeySchemaV2.self,
                toVersion: AnghkooeySchemaV3.self
            )
        ]
    }
}
