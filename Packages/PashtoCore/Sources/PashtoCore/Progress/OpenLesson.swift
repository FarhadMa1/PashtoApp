import Foundation
import Observation

/// The lesson on screen, and the saves behind each answer.
///
/// `startLesson` opens a released lesson. When the store still has that lesson
/// and `canResume` allows it, the saved questions and answers are what open,
/// unless a remaining question is one VoiceOver would not ask. Then the lesson
/// starts fresh. A resumed session keeps the pronunciation setting it started
/// with. There is no second button for continuing.
///
/// Each answer is written on its own. A failed answer leaves the quiz where it
/// is. The next answer, and a retry while the app is in the background, writes
/// the whole session. A failed finish keeps that session too and can be retried.
/// Saves are ordered: a later answer cannot be overwritten by an earlier one,
/// including one that is already being written. A retry still waiting when the
/// finish commits is dropped, so the finished lesson is not saved again as the
/// one in progress.
///
/// `endLesson` closes the quiz. It does not discard a save that has not landed.
@MainActor
@Observable
public final class OpenLesson {
    public private(set) var attempt: LessonAttempt?
    public private(set) var launch = RootLessonSession()
    @ObservationIgnored
    private let saves = LessonSaveQueue()
    @ObservationIgnored
    private var tail: Task<Void, Never>?
    @ObservationIgnored
    private var latestGeneration = 0
    @ObservationIgnored
    private var unsavedAnswers = false
    @ObservationIgnored
    private var lastAnswerSnapshot: ActiveSessionSnapshot?
    @ObservationIgnored
    private var pendingFinish: PendingFinish?

    public init() {}

    /// The quiz on screen. Nil on the home.
    ///
    /// A finished lesson stays here until `endLesson`, so a failed save still
    /// has every answer. The home does not draw it once no question is left.
    public var session: LessonSession? { launch.session }

    public var items: [ContentItem] { launch.items }

    /// True when an answer is still only in memory.
    public var hasUnsavedAnswers: Bool { unsavedAnswers }

    /// True when finishing failed and Try again can write that lesson again.
    public var canRetryFailedFinish: Bool { pendingFinish != nil }

    /// Opens `lessonID` from the home row.
    ///
    /// A stored unfinished lesson for this id is continued when `canResume`
    /// is true for `today` and `bundle`, and VoiceOver still allows every
    /// question that is left. The session id, the day it started, and the
    /// pronunciation setting stay the ones that were saved. A question VoiceOver
    /// would not ask starts a new session instead. An answer the store does not
    /// have yet is still here, and it is what opens. An unreleased lesson, or a
    /// lesson with no questions, does not open.
    public func startLesson(
        lessonID: LessonID,
        in bundle: ContentBundle,
        progress: ProgressSnapshot,
        releasedUnitIDs: [UnitID],
        showsPronunciation: Bool,
        voiceOver: Bool,
        on today: LocalDay,
        using rng: inout some RandomNumberGenerator
    ) {
        if let pending = lastAnswerSnapshot,
           unsavedAnswers,
           pending.lessonID == lessonID,
           let stored = pending.lesson,
           canResume(pending, on: today, contentVersion: bundle.contentVersion),
           !resumeConflictsWithVoiceOver(stored, voiceOver: voiceOver) {
            resumeStored(
                stored,
                sessionID: pending.sessionID,
                startedDay: pending.startedDay,
                contentVersion: pending.contentVersion,
                in: bundle,
                releasedUnitIDs: releasedUnitIDs
            )
            return
        }

        if let active = progress.activeSession,
           active.lessonID == lessonID,
           let stored = active.lesson,
           canResume(active, on: today, contentVersion: bundle.contentVersion),
           !resumeConflictsWithVoiceOver(stored, voiceOver: voiceOver) {
            resumeStored(
                stored,
                sessionID: active.sessionID,
                startedDay: active.startedDay,
                contentVersion: active.contentVersion,
                in: bundle,
                releasedUnitIDs: releasedUnitIDs
            )
            return
        }

        if lastAnswerSnapshot?.lessonID == lessonID {
            dropUnsavedAnswer()
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

    /// Remembers `session` and writes it. The quiz stays on this session either way.
    ///
    /// A failed write is not shown. The next answer and `retryUnsavedAnswers`
    /// write the whole session, including this answer. An older write is dropped
    /// once a newer answer has been queued.
    public func saveAnswer(
        _ session: LessonSession,
        on today: LocalDay,
        to store: any ProgressStore
    ) {
        guard let snapshot = answerToSave(session, on: today) else { return }
        enqueue(snapshot, to: store)
    }

    /// Writes the newest unsaved session again. Used when the app backgrounds.
    ///
    /// Does nothing when the last answer is already stored. A failure leaves
    /// the session on screen and keeps the retry for the next attempt.
    public func retryUnsavedAnswers(to store: any ProgressStore) {
        guard unsavedAnswers, let snapshot = lastAnswerSnapshot else { return }
        enqueue(snapshot, to: store)
    }

    /// Writes a finished lesson: the active session, then one commit.
    ///
    /// The quiz stays open when the write throws, with the same answers.
    /// `retryFailedFinish` writes that same lesson again. A thrown error does
    /// not remove progress the store already kept.
    public func finishLesson(
        _ session: LessonSession,
        on today: LocalDay,
        in content: ContentBundle,
        to store: any ProgressStore
    ) async throws -> ProgressSnapshot {
        guard let attempt, session.lessonID == attempt.lessonID else {
            return try await store.load()
        }
        launch.replaceSession(session)
        let pending = PendingFinish(attempt: attempt, session: session, day: today)
        return try await chainThrowing {
            do {
                let saved = try await self.writeFinished(pending, in: content, to: store)
                self.noteFinishSaved()
                return saved
            } catch {
                self.pendingFinish = pending
                throw error
            }
        }
    }

    /// Writes the finish that failed. The in-memory answers stay either way.
    public func retryFailedFinish(
        in content: ContentBundle,
        to store: any ProgressStore
    ) async throws -> ProgressSnapshot {
        guard let pendingFinish else { throw LessonSaveError.nothingToRetry }
        return try await chainThrowing {
            do {
                let saved = try await self.writeFinished(pendingFinish, in: content, to: store)
                self.noteFinishSaved()
                return saved
            } catch {
                throw error
            }
        }
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
        await tail?.value
        await saves.waitUntilIdle()
    }

    /// Closes the quiz. A save that has not landed is kept for a later retry.
    public func endLesson() {
        attempt = nil
        launch.end()
    }

    /// Closes the quiz when `sessionID` is still the one on screen.
    ///
    /// A different lesson, including one opened while a finish was in flight,
    /// stays. Nil matches only when nothing is open, and closing that is a no-op.
    /// The stored answers are not discarded.
    public func endLessonIfStill(_ sessionID: UUID?) {
        guard attempt?.sessionID == sessionID else { return }
        endLesson()
    }

    /// Drops a save that has not landed. Used when the learner starts over.
    ///
    /// An answer queued before this returns without writing, so it cannot
    /// recreate the lesson in the fresh store.
    public func discardPendingSaves() {
        dropUnsavedAnswer()
        pendingFinish = nil
    }

    private func resumeStored(
        _ stored: LessonSession,
        sessionID: UUID,
        startedDay: LocalDay,
        contentVersion: String,
        in bundle: ContentBundle,
        releasedUnitIDs: [UnitID]
    ) {
        var resumed = RootLessonSession()
        resumed.resume(stored, in: bundle, releasedUnitIDs: releasedUnitIDs)
        launch = resumed
        if resumed.isActive {
            attempt = LessonAttempt(
                sessionID: sessionID,
                lessonID: stored.lessonID,
                startedDay: startedDay,
                contentVersion: contentVersion
            )
        } else {
            attempt = nil
        }
    }

    private func enqueue(_ snapshot: ActiveSessionSnapshot, to store: any ProgressStore) {
        latestGeneration += 1
        let generation = latestGeneration
        unsavedAnswers = true
        lastAnswerSnapshot = snapshot
        chain {
            guard generation == self.latestGeneration else { return }
            do {
                try await self.saves.save(snapshot, to: store)
                if generation == self.latestGeneration {
                    self.unsavedAnswers = false
                }
            } catch {
                if generation == self.latestGeneration {
                    self.unsavedAnswers = true
                }
            }
        }
    }

    private func writeFinished(
        _ pending: PendingFinish,
        in content: ContentBundle,
        to store: any ProgressStore
    ) async throws -> ProgressSnapshot {
        try await saves.finish(
            attempt: pending.attempt,
            session: pending.session,
            answeredOn: pending.session.answers.isEmpty ? nil : pending.day,
            in: content,
            to: store
        )
    }

    private func noteFinishSaved() {
        pendingFinish = nil
        // The retry queued while this finish was writing still holds the old
        // session. Dropping it here means that write does not land after the
        // commit and put the finished lesson back in progress.
        dropUnsavedAnswer()
    }

    private func dropUnsavedAnswer() {
        latestGeneration += 1
        unsavedAnswers = false
        lastAnswerSnapshot = nil
    }

    private func chain(_ body: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await body()
        }
    }

    private func chainThrowing<T: Sendable>(
        _ body: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        let previous = tail
        return try await withCheckedThrowingContinuation { continuation in
            self.tail = Task { @MainActor in
                await previous?.value
                do {
                    continuation.resume(returning: try await body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// No finished lesson is waiting to be written again.
public enum LessonSaveError: Error, Equatable {
    case nothingToRetry
}

private struct PendingFinish: Sendable {
    var attempt: LessonAttempt
    var session: LessonSession
    var day: LocalDay
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
