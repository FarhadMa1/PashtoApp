import Foundation

/// One lesson the learner started.
///
/// `saveActive` writes the lesson in progress after an answer. That write
/// does not create cards and does not change the streak. `save` commits a
/// finished lesson through `sessionCommit`. Cards, the lesson row, and the
/// streak follow those rules. This type does not add a rule of its own.
/// An unfinished session is not committed: leaving it creates no cards.
public struct LessonAttempt: Hashable, Sendable {
    public let sessionID: UUID
    public let lessonID: LessonID
    public let startedDay: LocalDay
    public let contentVersion: String

    public init(
        sessionID: UUID = UUID(),
        lessonID: LessonID,
        startedDay: LocalDay,
        contentVersion: String
    ) {
        self.sessionID = sessionID
        self.lessonID = lessonID
        self.startedDay = startedDay
        self.contentVersion = contentVersion
    }

    /// The commit for a finished `session`, or nil when it should not be saved.
    ///
    /// Nil when `session` is a different lesson, or when it is not finished.
    /// `progress` supplies the cards, the lesson row, and the streak that
    /// `sessionCommit` already merges. Other lessons and other cards are not
    /// part of the commit, so the store keeps them.
    public func commit(
        for session: LessonSession,
        answeredOn lastAnswerDay: LocalDay?,
        in content: ContentBundle,
        progress: ProgressSnapshot
    ) -> SessionCommit? {
        guard session.lessonID == lessonID else { return nil }
        let active = ActiveSessionSnapshot(
            sessionID: sessionID,
            kind: .lesson,
            lessonID: lessonID,
            startedDay: startedDay,
            lastAnswerDay: lastAnswerDay,
            contentVersion: contentVersion,
            lesson: session
        )
        return sessionCommit(
            for: active,
            in: content,
            cards: progress.cards,
            lessonProgress: progress.lessonProgress,
            streak: progress.streak
        )
    }

    /// The active-session record for `session`.
    ///
    /// `lastAnswerDay` is stored only when `session` has an answer. The day
    /// is the civil day of the latest answer, which the caller supplies.
    /// A lesson that has not been answered yet keeps a nil day.
    public func activeSnapshot(
        _ session: LessonSession,
        answeredOn lastAnswerDay: LocalDay?
    ) -> ActiveSessionSnapshot {
        ActiveSessionSnapshot(
            sessionID: sessionID,
            kind: .lesson,
            lessonID: lessonID,
            startedDay: startedDay,
            lastAnswerDay: session.answers.isEmpty ? nil : lastAnswerDay,
            contentVersion: contentVersion,
            lesson: session
        )
    }

    /// Writes the lesson in progress. Does not create cards or change the streak.
    ///
    /// A session for another lesson writes nothing. A thrown error also writes
    /// nothing: the store replaces the active session in one save.
    public func saveActive(
        _ session: LessonSession,
        answeredOn lastAnswerDay: LocalDay?,
        to store: any ProgressStore
    ) async throws {
        guard session.lessonID == lessonID else { return }
        try await store.saveActiveSession(activeSnapshot(session, answeredOn: lastAnswerDay))
    }

    /// Writes a finished lesson with one `commit`, then reads the store back.
    ///
    /// The commit is built from a fresh `load`, not from an older copy the
    /// caller might still be holding. An unfinished session, or a session for
    /// another lesson, returns that snapshot and writes nothing. A thrown
    /// error also writes nothing: `ProgressStore.commit` is one save, and a
    /// failure leaves the stored progress as it was.
    public func save(
        _ session: LessonSession,
        answeredOn lastAnswerDay: LocalDay?,
        in content: ContentBundle,
        to store: any ProgressStore
    ) async throws -> ProgressSnapshot {
        let progress = try await store.load()
        guard let commit = commit(
            for: session,
            answeredOn: lastAnswerDay,
            in: content,
            progress: progress
        ) else {
            return progress
        }
        try await store.commit(commit)
        return try await store.load()
    }
}
