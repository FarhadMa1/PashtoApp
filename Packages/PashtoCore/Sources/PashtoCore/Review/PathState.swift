/// What the lesson path shows for one civil day.
///
/// The app displays this value. It does not choose the path. `pathState`
/// builds it from the daily plan and the course order.
public enum PathState: Sendable, Equatable {
    /// Due cards remain, including placement cards due today.
    ///
    /// No new lesson is offered, and Learn more stays hidden. `dueCount` is
    /// the number of cards still due before the review cap of 50, so a
    /// backlog of 51 is reported as 51.
    case review(dueCount: Int)

    /// The next lesson. Today's new-item cap is not reached.
    ///
    /// The lesson may introduce more items than the number still allowed.
    /// A lesson is not cut to fit the cap.
    case lesson(LessonID)

    /// The new-item cap is reached.
    ///
    /// `learnMore` is the next lesson. Nil hides Learn more. More than 50
    /// due cards do not use this case: the path is `review` instead, so
    /// Learn more stays hidden. When no lesson remains, the path is
    /// `courseFinished`.
    case doneForToday(learnMore: LessonID?)

    /// No lesson remains, and nothing is due.
    case courseFinished
}

/// Learner state for one call to `pathState`.
///
/// `pathProgress(_:on:)` builds this from a `ProgressSnapshot` for one civil
/// day. This value is not saved on its own. `dailyPlan` counts the due cards
/// and the new items. The lesson ids are the lessons already finished or
/// skipped by the placement test. The path does not store a position in the
/// course.
public struct PathProgress: Hashable, Sendable {
    /// Review cards, including placement cards. Paused cards may be included.
    ///
    /// `dailyPlan` decides which of them are due. A card whose item is not
    /// in the bundle passed to `pathState` is not due, and it is not removed
    /// from this array.
    public let cards: [ReviewCard]

    /// Lessons finished, or skipped by the placement test.
    ///
    /// The next lesson is the first lesson in the bundle that is not in this
    /// set. Membership is all that is used. A lesson added earlier in the
    /// course does not lock one that is already here.
    public let finishedLessonIDs: Set<LessonID>

    /// Items introduced on the day passed to `pathState`.
    ///
    /// The same count `dailyPlan` subtracts from the goal. Changing the goal
    /// does not change this number, and a negative value counts as zero.
    /// `pathProgress(_:on:)` counts lesson cards whose `createdDay` is that
    /// day and skips placement cards. A review does not change `createdDay`,
    /// so a new civil day is a new count.
    public let newItemsShownToday: Int

    public init(cards: [ReviewCard], finishedLessonIDs: Set<LessonID>, newItemsShownToday: Int) {
        self.cards = cards
        self.finishedLessonIDs = finishedLessonIDs
        self.newItemsShownToday = newItemsShownToday
    }
}

/// What the lesson path shows on `today`.
///
/// The result is review, the next lesson, done for today, or the end of the
/// course. The function has no stored state. `today` is an argument, and the
/// function does not read a clock.
///
/// The due count and the new-item cap come from `dailyPlan`, so those rules
/// live in one place. A card is due only when its item is in `content`.
///
/// The checks run in this order:
///
/// 1. More than 50 cards are due. The path is review. There is no new lesson
///    and no Learn more.
/// 2. Today's queue still has due cards, including placement cards due today.
///    The path is review.
/// 3. Items introduced on `today` are still under the goal, and a lesson
///    remains. The path is that lesson. A lesson may be started while any
///    new item remains, even when it introduces more items than that.
/// 4. The cap is reached and a lesson remains. The path is done for today,
///    and Learn more is that lesson. Finishing the extra lesson adds its
///    introduced items to the shown count. The next call is done for today
///    again, with the lesson after it.
/// 5. No lesson remains and nothing is due. The path is course finished.
///
/// The next lesson is the first practice lesson of `content.units`, in that
/// order, whose id is not in `progress.finishedLessonIDs`. Learn and phrases
/// stay available and do not take that place.
///
/// `progress.newItemsShownToday` is how many items were introduced on
/// `today`. A new civil day is a new `today` and the count for that day.
/// Changing `goal` uses the new limit minus that count. The count is not
/// reduced, so nothing already shown is taken back.
public func pathState(
    progress: PathProgress,
    content: ContentBundle,
    goal: DailyGoal,
    today: LocalDay
) -> PathState {
    let plan = dailyPlan(
        cards: progress.cards,
        knownItemIDs: Set(content.items.map(\.id)),
        goal: goal,
        newItemsShownToday: progress.newItemsShownToday,
        on: today
    )
    let next = nextLesson(in: content, finished: progress.finishedLessonIDs)

    if plan.dueCount > DailyPlan.maximumReviews {
        return .review(dueCount: plan.dueCount)
    }
    if !plan.reviews.isEmpty {
        return .review(dueCount: plan.dueCount)
    }
    if plan.canStartLesson, let next {
        return .lesson(next)
    }
    if !plan.canStartLesson, let next {
        return .doneForToday(learnMore: next)
    }
    return .courseFinished
}

/// The first lesson in course order that is not finished.
///
/// Units and lessons stay in the order stored on the bundle. Ids are not
/// sorted. The finished set is only a membership test.
/// The next practice lesson. Learn and phrases stay on the path and do not block it.
private func nextLesson(in content: ContentBundle, finished: Set<LessonID>) -> LessonID? {
    for unit in content.units {
        for lesson in unit.lessons where lesson.countsForProgress && !finished.contains(lesson.id) {
            return lesson.id
        }
    }
    return nil
}
