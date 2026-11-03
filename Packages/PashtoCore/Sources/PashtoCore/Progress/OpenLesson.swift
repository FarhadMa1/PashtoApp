import Foundation

/// The lesson on screen, and the saves behind each answer.
///
/// `start` opens a released lesson. When the store still has that lesson and
/// `canResume` allows it, the saved questions and answers are what open.
/// There is no second button for that. `saveAnswer` writes the active-session
/// record after an answer. `saveFinished` commits a finished lesson. Leaving
/// the quiz does not discard those answers.
///
/// Saves run one at a time. A lesson opened while a finish is still being
/// written stays open: `leaveIfStill` closes only the session id that finished.
@MainActor
public final class OpenLesson {
    public private(set) var attempt: LessonAttempt?
    public private(set) var launch = RootLessonSession()
    private let saves = LessonSaveQueue()

    public init() {}

    /// The quiz on screen. Nil on the home, and nil when every question is answered.
    public var session: LessonSession? {
        launch.isActive ? launch.session : nil
    }

    public var items: [ContentItem] { launch.items }

    /// Opens `lessonID` from the home row.
    ///
    /// A stored unfinished lesson for this id is continued when `canResume`
    /// is true for `today` and `bundle`. The session id and the day it
    /// started stay the ones that were saved. Anything else starts a new
    /// session. An unreleased lesson, or a lesson with no questions, does not open.
    public func start(
        lessonID: LessonID,
        in bundle: ContentBundle,
        progress: ProgressSnapshot,
        releasedUnitIDs: [UnitID],
        showsPronunciation: Bool,
        voiceOver: Bool,
        on today: LocalDay,
        using rng: inout some RandomNumberGenerator
    ) {
        if let active = progress.activeSession,
           active.lessonID == lessonID,
           let stored = active.lesson,
           canResume(active, on: today, contentVersion: bundle.contentVersion) {
            var resumed = RootLessonSession()
            resumed.resume(stored, in: bundle, releasedUnitIDs: releasedUnitIDs)
            launch = resumed
            if resumed.isActive {
                attempt = LessonAttempt(
                    sessionID: active.sessionID,
                    lessonID: lessonID,
                    startedDay: active.startedDay,
                    contentVersion: active.contentVersion
                )
            } else {
                attempt = nil
            }
            return
        }

        var started = RootLessonSession()
        started.start(
            lessonID: lessonID,
            in: bundle,
            seenLessonIDs: progress.lessonProgress.map(\.lessonID),
            releasedUnitIDs: releasedUnitIDs,
            showsPronunciation: showsPronunciation,
            voiceOver: voiceOver,
            using: &rng
        )
        launch = started
        if started.isActive, let session = started.session {
            attempt = LessonAttempt(
                lessonID: session.lessonID,
                startedDay: today,
                contentVersion: bundle.contentVersion
            )
        } else {
            attempt = nil
        }
    }

    /// The record for this answer, and the session kept on screen.
    ///
    /// Nil when `session` is not the lesson that is open. The caller can
    /// persist the record after the quiz has already been closed: the
    /// snapshot does not read the screen again.
    public func answerToSave(_ session: LessonSession, on today: LocalDay) -> ActiveSessionSnapshot? {
        guard let attempt, session.lessonID == attempt.lessonID else { return nil }
        launch.replaceSession(session)
        let answeredOn = session.answers.isEmpty ? nil : today
        return attempt.activeSnapshot(session, answeredOn: answeredOn)
    }

    /// Writes one active-session record. Cards and the streak stay as they were.
    public func persist(_ session: ActiveSessionSnapshot, to store: any ProgressStore) async throws {
        try await saves.save(session, to: store)
    }

    /// Remembers `session` and writes it. Used when the lesson is still open.
    public func saveAnswer(
        _ session: LessonSession,
        on today: LocalDay,
        to store: any ProgressStore
    ) async throws {
        guard let snapshot = answerToSave(session, on: today) else { return }
        try await persist(snapshot, to: store)
    }

    /// Writes a finished lesson: the active session, then one commit.
    ///
    /// `attempt` is the lesson that finished, which may no longer be the one
    /// on screen. The commit removes the active session only when its id is
    /// this one, so a newer lesson is left in place. A thrown error writes
    /// nothing further. A commit that throws leaves the active session from
    /// the save that just succeeded, and leaves every earlier row alone.
    public func saveFinished(
        attempt: LessonAttempt,
        session: LessonSession,
        on today: LocalDay,
        in content: ContentBundle,
        to store: any ProgressStore
    ) async throws -> ProgressSnapshot {
        guard session.lessonID == attempt.lessonID else {
            return try await store.load()
        }
        let answeredOn = session.answers.isEmpty ? nil : today
        return try await saves.finish(
            attempt: attempt,
            session: session,
            answeredOn: answeredOn,
            in: content,
            to: store
        )
    }

    /// Returns after every answer save and finish already queued.
    public func waitUntilSavesFinish() async {
        await saves.waitUntilIdle()
    }

    /// Closes the quiz when `sessionID` is still the one on screen.
    ///
    /// A different lesson, including one opened while a finish was in flight,
    /// stays. Nil matches only when nothing is open, and closing that is a no-op.
    /// The stored answers are not discarded.
    public func leaveIfStill(_ sessionID: UUID?) {
        guard attempt?.sessionID == sessionID else { return }
        leave()
    }

    /// Closes the quiz. The active-session record stays so the lesson can be continued.
    public func leave() {
        attempt = nil
        launch.end()
    }
}

/// One lesson save at a time.
///
/// A later save waits until the earlier one has finished writing. That keeps
/// an older answer from replacing a newer one, and keeps a finish from
/// clearing a lesson that was saved after it.
private actor LessonSaveQueue {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func save(_ session: ActiveSessionSnapshot, to store: any ProgressStore) async throws {
        await acquire()
        defer { release() }
        try await store.saveActiveSession(session)
    }

    func finish(
        attempt: LessonAttempt,
        session: LessonSession,
        answeredOn: LocalDay?,
        in content: ContentBundle,
        to store: any ProgressStore
    ) async throws -> ProgressSnapshot {
        await acquire()
        defer { release() }
        try await store.saveActiveSession(attempt.activeSnapshot(session, answeredOn: answeredOn))
        return try await attempt.save(session, answeredOn: answeredOn, in: content, to: store)
    }

    func waitUntilIdle() async {
        await acquire()
        release()
    }

    private func acquire() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            locked = false
            return
        }
        let next = waiters.removeFirst()
        next.resume()
    }
}
