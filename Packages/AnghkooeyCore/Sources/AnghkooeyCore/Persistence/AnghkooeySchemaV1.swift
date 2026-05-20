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
        [Card.self, ReviewLog.self, Tag.self]
    }
}

/// Migration plan for the Anghkooey persistence store.
///
/// V1 has no prior schema, so `stages` is empty. The scaffolding exists from
/// day one so the call-site shape never changes when V2 lands.
public enum AnghkooeyMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [AnghkooeySchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
