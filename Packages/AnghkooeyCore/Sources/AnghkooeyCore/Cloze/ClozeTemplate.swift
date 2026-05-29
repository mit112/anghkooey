import Foundation

public struct ClozeDeletion: Equatable, Sendable {
    public let index: Int
    public let answer: String
    public let hint: String?
    public init(index: Int, answer: String, hint: String? = nil) {
        self.index = index; self.answer = answer; self.hint = hint
    }
}

public struct ClozeTemplate: Equatable, Sendable {
    public let markup: String
    public let deletions: [ClozeDeletion]
    public init(markup: String, deletions: [ClozeDeletion]) {
        self.markup = markup; self.deletions = deletions
    }
    public var indices: [Int] { deletions.map(\.index).sorted() }
}

public enum ClozeParseError: Error, Equatable, Sendable {
    case noDeletions
    case unclosedMarker
    case nestedMarker
    case duplicateIndex(Int)
    case nonPositiveIndex(Int)
    case tooManyDeletions(count: Int, max: Int)
    case emptyAnswer(index: Int)
}
