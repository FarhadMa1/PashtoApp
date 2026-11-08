import Foundation

/// A lesson session or a review session.
public enum SessionKind: String, Codable, Hashable, Sendable {
    case lesson
    case review
}

/// One finished session. The id makes a commit idempotent.
public struct CompletedSession: Codable, Hashable, Sendable {
    public let sessionID: UUID
    public let kind: SessionKind
    public let lessonID: LessonID?
    /// The civil day of the last answer. A commit that runs again uses this day.
    public let completedDay: LocalDay
    public let questionCount: Int
    public let firstTryCorrect: Int

    public init(
        sessionID: UUID,
        kind: SessionKind,
        lessonID: LessonID?,
        completedDay: LocalDay,
        questionCount: Int,
        firstTryCorrect: Int
    ) {
        self.sessionID = sessionID
        self.kind = kind
        self.lessonID = lessonID
        self.completedDay = completedDay
        self.questionCount = questionCount
        self.firstTryCorrect = firstTryCorrect
    }
}

/// The lesson in progress, saved after each answer.
///
/// There is at most one. Saving it does not create cards and does not change
/// the streak. Cards are written when the lesson is committed.
///
/// An unfinished lesson can be continued on the day it started, the next
/// day, or the day before, when the content version and the payload version
/// match. `canResume` is that check. The day before covers a clock set back
/// by one day. A finished lesson is not continued: `mustCommit` is true,
/// and startup commits it on the day of the last answer. A newer payload is
/// left stored. Discarding an unfinished session creates no cards.
public struct ActiveSessionSnapshot: Codable, Hashable, Sendable {
    /// The only payload this build can read.
    public static let currentPayloadVersion = 1

    public let sessionID: UUID
    public let kind: SessionKind
    public let lessonID: LessonID?
    /// The civil day the session was started. The resume window uses this day.
    public let startedDay: LocalDay
    /// The civil day of the latest answer. Nil until the first answer.
    ///
    /// A commit uses this day for the streak and for `createdDay`. It does
    /// not use the day the app happens to be opened.
    public let lastAnswerDay: LocalDay?
    public let contentVersion: String
    public let payloadVersion: Int
    /// The questions still to answer, and the answers already given.
    ///
    /// Nil when `kind` is `review`. A review session value is a later step.
    public let lesson: LessonSession?

    public init(
        sessionID: UUID,
        kind: SessionKind,
        lessonID: LessonID?,
        startedDay: LocalDay,
        lastAnswerDay: LocalDay?,
        contentVersion: String,
        payloadVersion: Int = currentPayloadVersion,
        lesson: LessonSession?
    ) {
        self.sessionID = sessionID
        self.kind = kind
        self.lessonID = lessonID
        self.startedDay = startedDay
        self.lastAnswerDay = lastAnswerDay
        self.contentVersion = contentVersion
        self.payloadVersion = payloadVersion
        self.lesson = lesson
    }
}

/// True when a saved lesson still has a question VoiceOver does not ask.
///
/// Find-the-letter, letter contrast, and first-letter tasks are not built
/// while VoiceOver is on. If one of those is still waiting, the lesson starts
/// over instead of continuing. Other questions, including meaning questions,
/// stay. Pronunciation is not part of this check: a lesson that does continue
/// keeps the pronunciation setting it was started with.
public func resumeConflictsWithVoiceOver(_ session: LessonSession, voiceOver: Bool) -> Bool {
    guard voiceOver else { return false }
    return session.tasks.contains { task in
        switch task.kind {
        case .findLetter, .letterContrast, .firstLetter:
            return true
        default:
            return false
        }
    }
}

/// True when a saved lesson still has a question the playable quiz does not ask.
///
/// Find-the-letter, letter contrast, first-letter, and pronunciation-choice
/// tasks are not built anymore. If one is still waiting, the lesson starts
/// over instead of continuing. Meaning questions, word order, and matching
/// stay. A finished lesson is not this check: `mustCommit` still records it.
public func resumeContainsUnplayableTask(_ session: LessonSession) -> Bool {
    session.tasks.contains { PlayableCourse.retiredQuizKinds.contains($0.kind) }
}

/// Whether an unfinished `session` can be continued on `today` for `contentVersion`.
///
/// True when it is an unfinished lesson, the payload version is the one this
/// build reads, `contentVersion` matches, and the age of `startedDay` on
/// `today` is 0, 1, or -1. Age 0 is the day it started. Age 1 is the next
/// day. Age -1 is a clock set back by one day, so `startedDay` is tomorrow.
/// A session started two or more days earlier (age 2 or more) is not
/// continued. A clock set back by two or more days (age -2 or less) is not
/// continued either. A finished lesson is not continued: every question is
/// already answered, and `mustCommit` is how startup handles it. Check
/// `mustCommit` before treating a false result as a session to drop. This
/// function does not delete the session, and it does not read a clock.
public func canResume(
    _ session: ActiveSessionSnapshot,
    on today: LocalDay,
    contentVersion: String
) -> Bool {
    guard session.kind == .lesson, let lesson = session.lesson, !lesson.isComplete else { return false }
    guard lesson.lessonID == session.lessonID else { return false }
    guard session.payloadVersion == ActiveSessionSnapshot.currentPayloadVersion else { return false }
    guard session.contentVersion == contentVersion else { return false }
    let age = today.days(from: session.startedDay)
    return age == 0 || age == 1 || age == -1
}

/// Whether startup must commit `session` instead of resuming or dropping it.
///
/// True when it is a lesson this build can read, every question is answered,
/// and the lesson id on the session matches the payload. How many days ago
/// it started does not matter. The content version does not matter. The
/// commit uses `lastAnswerDay` when an answer was stored, not the day the
/// app starts. A newer payload is never committed, because committing would
/// replace it. A review session is not committed: this build does not store
/// its questions, so an interrupted review starts over.
public func mustCommit(_ session: ActiveSessionSnapshot) -> Bool {
    guard session.payloadVersion <= ActiveSessionSnapshot.currentPayloadVersion else { return false }
    guard session.kind == .lesson, let lesson = session.lesson else { return false }
    guard lesson.lessonID == session.lessonID else { return false }
    return lesson.isComplete
}
