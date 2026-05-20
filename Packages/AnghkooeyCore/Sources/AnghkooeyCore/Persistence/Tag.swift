import Foundation
import SwiftData

/// A persisted label for grouping and filtering cards.
///
/// Tag names are user-visible mixed case (`name`), but uniqueness is enforced
/// on a lowercased `normalizedName` so "Swift" and "swift" collapse to one tag.
/// `@Attribute(.unique)` on a Swift `String` cannot model case-insensitive
/// equality directly, so the normalized form lives in its own pinned column.
@Model
public final class Tag {
    /// Stable identifier; primary key.
    @Attribute(.unique) public var id: UUID

    /// User-visible tag name with original casing preserved.
    public var name: String

    /// Lowercased form of `name` used to enforce case-insensitive uniqueness
    /// at insert time. Always derived from `name` via `Tag.normalize(_:)`.
    @Attribute(.unique) public var normalizedName: String

    /// Wall-clock time the tag was first persisted.
    public var createdAt: Date

    /// Cards labeled with this tag. Many-to-many; inverse of `Card.tags`.
    @Relationship(inverse: \Card.tags) public var cards: [Card]

    /// Creates a tag, deriving `normalizedName` from the supplied display name.
    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        cards: [Card] = []
    ) {
        self.id = id
        self.name = name
        self.normalizedName = Tag.normalize(name)
        self.createdAt = createdAt
        self.cards = cards
    }

    /// Canonical normalization used to compare tag names for uniqueness.
    /// Lowercase + trim — Unicode case folding is acceptable for v1.
    public static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
