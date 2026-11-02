import Foundation
import PashtoCore

extension ProgressPersistenceError {
    /// The screen failure for this error.
    ///
    /// A newer schema, snapshot, or session payload asks the learner to
    /// update. The file is not a reason to start over. Every other error is.
    public var openFailure: ProgressOpenFailure {
        switch self {
        case .newerSchema, .newerSnapshot, .newerPayload:
            return .newerVersion
        case .unsupportedSnapshot, .unsupportedPayload, .unknownStoredValue,
             .invalidIdentifier, .invalidDayNumber, .duplicateStoredValue,
             .unreadableActiveSession, .failedToOpen:
            return .other
        }
    }
}

/// The screen failure for an error thrown while opening or loading progress.
///
/// Errors from outside this package are treated as a storage failure. A
/// newer store is never reported as one of those.
public func progressOpenFailure(for error: Error) -> ProgressOpenFailure {
    guard let error = error as? ProgressPersistenceError else {
        return .other
    }
    return error.openFailure
}
