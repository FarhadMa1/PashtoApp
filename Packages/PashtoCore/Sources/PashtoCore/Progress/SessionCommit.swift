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

    let firstTries = session.answers.filter { !$0.task.isRepeat }
    let correct = firstTries.filter { $0.result == .correct }.count
    let questions = firstTries.count
    let percent = questions == 0 ? 0 : (correct * 100) / questions
    let progress = mergedProgress(
        lessonID: lesson.id,
        day: day,
        percent: percent,
        existing: existingProgress
    )
    let completed = CompletedSession(
        sessionID: active.sessionID,
        kind: .lesson,
        lessonID: lesson.id,
        completedDay: day,
        questionCount: questions,
        firstTryCorrect: correct
    )
    return SessionCommit(
        sessionID: active.sessionID,
        cards: reviewed,
        lessonProgress: progress,
        streak: streak(state, after: .completedSession, on: day),
        completed: completed
    )
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
