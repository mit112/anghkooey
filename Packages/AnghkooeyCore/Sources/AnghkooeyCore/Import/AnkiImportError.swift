import Foundation

public enum AnkiImportError: Error, @unchecked Sendable {
    case notAnApkgFile
    case fileAccessDenied
    case corruptedArchive
    case databaseCorrupted
    case storeFailed(underlying: any Error)
}
