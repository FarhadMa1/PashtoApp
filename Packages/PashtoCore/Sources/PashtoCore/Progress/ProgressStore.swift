import Foundation

/// The learner's progress on one device.
///
/// Every method is `async` so a SwiftData store can use the same protocol.
/// `load` returns the clamped snapshot. The other methods write. A failed
/// `commit` must leave the active session and the cards as they were.
public protocol ProgressStore: Sendable {
    func load() async throws -> ProgressSnapshot
    /// Replaces the one active session. Does not create cards.
    func saveActiveSession(_ session: ActiveSessionSnapshot) async throws
    func discardActiveSession() async throws
    /// Writes cards, lesson progress, the streak, and the completed session.
    ///
    /// Removes the active session when its id is the commit's id. A commit
    /// whose id was already completed changes nothing.
    func commit(_ commit: SessionCommit) async throws
    /// Upserts cards by `itemID`. Does not remove a card that is absent here.
    func applyReconciliation(_ changes: [ReviewCard]) async throws
    func updateSettings(_ settings: UserSettings) async throws
    /// Clears cards, lesson progress, the streak, and sessions.
    ///
    /// Settings stay. `contentVersion` stays because it describes the installed
    /// content, not the learner's progress.
    func resetAll() async throws
}

public enum ProgressStoreError: Error, Equatable, Sendable {
    /// `sessionID` and `completed.sessionID` disagree. Nothing was written.
    case mismatchedSessionID
}
