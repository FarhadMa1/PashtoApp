import Foundation

/// A progress file could not be read, or it is from a newer build.
///
/// A newer schema, snapshot, or session payload is never written over.
/// Opening a store does not delete it when this is thrown.
public enum ProgressPersistenceError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The SwiftData file was written by a schema this build does not know.
    case newerSchema(String)
    /// `snapshotVersion` is newer than `ProgressSnapshot.currentVersion`.
    case newerSnapshot(Int)
    /// The active session's payload version is newer than this build.
    case newerPayload(Int)
    /// The snapshot version is older than this build, and nothing migrates it yet.
    case unsupportedSnapshot(Int)
    /// The session payload version is older than this build. The row is left in place.
    case unsupportedPayload(Int)
    /// A stored enum string is not one this build knows.
    case unknownStoredValue(field: String, value: String)
    /// A stored id is not a content id.
    case invalidIdentifier(field: String, value: String)
    /// A stored day number is outside the range `LocalDay` can represent.
    case invalidDayNumber(Int)
    /// Two rows share a key that is supposed to be unique.
    case duplicateStoredValue(field: String, value: String)
    /// The active-session JSON could not be decoded. The row is left in place.
    case unreadableActiveSession
    /// `ModelContainer` could not open the file. The file was not deleted.
    case failedToOpen(String)

    public var description: String {
        switch self {
        case .newerSchema(let detail):
            return "The progress store was written by a newer version of the app. It was not changed. \(detail)"
        case .newerSnapshot(let version):
            return "The progress store uses snapshot version \(version), which is newer than this version of the app. It was not changed."
        case .newerPayload(let version):
            return "The lesson in progress uses payload version \(version), which is newer than this version of the app. It was not changed."
        case .unsupportedSnapshot(let version):
            return "The progress store uses snapshot version \(version), which this version of the app cannot read. It was not changed."
        case .unsupportedPayload(let version):
            return "The lesson in progress uses payload version \(version), which this version of the app cannot read. It was not changed."
        case .unknownStoredValue(let field, let value):
            return "The progress store has an unknown value \(value) for \(field). It was not changed."
        case .invalidIdentifier(let field, let value):
            return "The progress store has an invalid id \(value) for \(field). It was not changed."
        case .invalidDayNumber(let number):
            return "The progress store has a day number \(number) this version of the app cannot read. It was not changed."
        case .duplicateStoredValue(let field, let value):
            return "The progress store has more than one row for \(field) \(value). It was not changed."
        case .unreadableActiveSession:
            return "The lesson in progress could not be read. It was not changed."
        case .failedToOpen(let detail):
            return "The progress store could not be opened. It was not changed. \(detail)"
        }
    }
}
