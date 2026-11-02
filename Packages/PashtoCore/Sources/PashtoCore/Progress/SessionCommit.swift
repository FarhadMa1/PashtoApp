import Foundation

/// What one finished session writes. The store saves it and does not compute it.
///
/// `sessionID` matches `completed.sessionID`. A second commit with the same
/// id changes nothing, including `completedDay`.
public struct SessionCommit: Hashable, Sendable {
    public let sessionID: UUID
    /// Cards that are new or changed. The store upserts them by `itemID`.
    public let cards: [ReviewCard]
    /// The lesson row to upsert. Nil for a review session.
    public let lessonProgress: LessonProgress?
    public let streak: StreakState
    public let completed: CompletedSession

    public init(
        sessionID: UUID,
        cards: [ReviewCard],
        lessonProgress: LessonProgress?,
        streak: StreakState,
        completed: CompletedSession
    ) {
        self.sessionID = sessionID
        self.cards = cards
        self.lessonProgress = lessonProgress
        self.streak = streak
        self.completed = completed
    }
}

/// The commit for a finished lesson in `content`.
///
/// Returns nil unless `mustCommit(active)` is true. The lesson is the one
/// with `active.lessonID` in `content`. When that lesson has been removed,
/// the commit still records the streak, the lesson row, and the completed
/// session, and it creates no cards. The day is `lastAnswerDay`, or
/// `startedDay` when no answer was stored. The function does not take the
/// day the commit runs, so a lesson finished on day N and committed on day
/// N+1 still counts on day N.
public func sessionCommit(
    for active: ActiveSessionSnapshot,
    in content: ContentBundle,
    cards existingCards: [ReviewCard],
    lessonProgress rows: [LessonProgress],
    streak state: StreakState
) -> SessionCommit? {
    guard mustCommit(active), let lessonID = active.lessonID, let session = active.lesson else {
        return nil
    }
    let existing = rows.first { $0.lessonID == lessonID }
    if let lesson = lesson(lessonID, in: content) {
        return sessionCommit(
            for: active,
            lesson: lesson,
            cards: existingCards,
            lessonProgress: existing,
            streak: state
        )
    }
    let day = active.lastAnswerDay ?? active.startedDay
    let scored = firstTryScore(session)
    return SessionCommit(
        sessionID: active.sessionID,
        cards: [],
        lessonProgress: mergedProgress(
            lessonID: lessonID,
            day: day,
            percent: scored.percent,
            existing: existing
        ),
        streak: streak(state, after: .completedSession, on: day),
        completed: CompletedSession(
            sessionID: active.sessionID,
            kind: .lesson,
            lessonID: lessonID,
            completedDay: day,
            questionCount: scored.questions,
            firstTryCorrect: scored.correct
        )
    )
}

/// The commit for a finished lesson.
///
/// Returns nil unless `active` is a complete lesson for `lesson`. The day is
/// `lastAnswerDay`, or `startedDay` when no answer was stored. The function
/// does not take the day the commit runs, so a lesson finished on day N and
/// committed on day N+1 still counts on day N.
///
/// Cards are created here, not while the lesson is in progress. An item that
/// already has a card is left out, so a placement card is not replaced.
/// A `soundExample` reference creates no card. Each new card is then reviewed
/// from the lesson's answers. `createdDay` is the completion day.
///
/// An existing lesson row keeps its source and its first day. The score
/// becomes the higher of the stored score and this session. The percent is
/// the integer ratio of first-try correct answers to answers that are not
/// repeats.
public func sessionCommit(
    for active: ActiveSessionSnapshot,
    lesson: Lesson,
    cards existingCards: [ReviewCard],
    lessonProgress existingProgress: LessonProgress?,
    streak state: StreakState
) -> SessionCommit? {
    guard active.kind == .lesson, active.lessonID == lesson.id else { return nil }
    guard let session = active.lesson, session.isComplete, session.lessonID == lesson.id else { return nil }

    let day = active.lastAnswerDay ?? active.startedDay
    let existingIDs = Set(existingCards.map(\.itemID))
    let introduced = reviewCards(introducedIn: lesson, on: day)
        .filter { !existingIDs.contains($0.itemID) }
    let reviewed = applyLessonReviews(
        introduced,
        introducedIn: lesson,
        answers: session.answers,
        on: day
    )

    let scored = firstTryScore(session)
    let progress = mergedProgress(
        lessonID: lesson.id,
        day: day,
        percent: scored.percent,
        existing: existingProgress
    )
    let completed = CompletedSession(
        sessionID: active.sessionID,
        kind: .lesson,
        lessonID: lesson.id,
        completedDay: day,
        questionCount: scored.questions,
        firstTryCorrect: scored.correct
    )
    return SessionCommit(
        sessionID: active.sessionID,
        cards: reviewed,
        lessonProgress: progress,
        streak: streak(state, after: .completedSession, on: day),
        completed: completed
    )
}

private struct FirstTryScore {
    var questions: Int
    var correct: Int
    var percent: Int
}

/// First-try answers only. A question asked again after a miss is not counted.
private func firstTryScore(_ session: LessonSession) -> FirstTryScore {
    let firstTries = session.answers.filter { !$0.task.isRepeat }
    let correct = firstTries.filter { $0.result == .correct }.count
    let questions = firstTries.count
    let percent = questions == 0 ? 0 : (correct * 100) / questions
    return FirstTryScore(questions: questions, correct: correct, percent: percent)
}

private func lesson(_ id: LessonID, in content: ContentBundle) -> Lesson? {
    for unit in content.units {
        if let lesson = unit.lessons.first(where: { $0.id == id }) {
            return lesson
        }
    }
    return nil
}

private func mergedProgress(
    lessonID: LessonID,
    day: LocalDay,
    percent: Int,
    existing: LessonProgress?
) -> LessonProgress {
    guard let existing, existing.lessonID == lessonID else {
        return LessonProgress(
            lessonID: lessonID,
            source: .completed,
            firstCompletedDay: day,
            bestScorePercent: percent
        )
    }
    return LessonProgress(
        lessonID: lessonID,
        source: existing.source,
        firstCompletedDay: existing.firstCompletedDay,
        bestScorePercent: max(existing.bestScorePercent, percent)
    )
}
