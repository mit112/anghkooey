import Foundation

public enum AnkiImportError: Error, @unchecked Sendable {
    case notAnApkgFile
    case fileAccessDenied
    case corruptedArchive
    case databaseCorrupted
    case storeFailed(underlying: any Error)
}

extension AnkiImportError: Equatable {
    public static func == (lhs: AnkiImportError, rhs: AnkiImportError) -> Bool {
        switch (lhs, rhs) {
        case (.notAnApkgFile, .notAnApkgFile),
             (.fileAccessDenied, .fileAccessDenied),
             (.corruptedArchive, .corruptedArchive),
             (.databaseCorrupted, .databaseCorrupted),
             (.storeFailed, .storeFailed):
            return true
        default:
            return false
        }
    }
}
