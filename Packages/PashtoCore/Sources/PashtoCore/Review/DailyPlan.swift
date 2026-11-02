/// How many new items the learner wants on a day that is not over the review cap.
///
/// Light is 5, regular is 10, and serious is 15. Regular is the usual goal.
/// The review queue has its own cap, `DailyPlan.maximumReviews`, and does not
/// use this value.
public enum DailyGoal: Int, CaseIterable, Hashable, Sendable {
    case light = 5
    case regular = 10
    case serious = 15

    /// New items allowed when 50 or fewer cards are due.
    public var newItemLimit: Int { rawValue }
}

/// One day's reviews, and how many new items a lesson may still introduce.
///
/// `reviews` is the queue. New items come after it. The value does not say
/// which lesson is next, and it does not store cards. `dailyPlan` builds it.
/// The day is an argument. Nothing here reads a clock.
public struct DailyPlan: Hashable, Sendable {
    /// Reviews taken from the due queue on one day.
    public static let maximumReviews = 50

    /// Due cards to review, oldest `dueDay` first and then `itemID`.
    ///
    /// At most `maximumReviews`. A placement card is an ordinary due card
    /// with `source: placement`, so it sits in this queue and counts toward
    /// the cap. It is not pulled ahead of an older lesson card.
    public let reviews: [ReviewCard]

    /// Due cards before the cap is applied.
    ///
    /// More than `maximumReviews` means no new items today. Exactly
    /// `maximumReviews` still allows the goal.
    public let dueCount: Int

    /// New items still allowed today. Never negative.
    ///
    /// A lesson is not cut to fit this number. While it is greater than zero
    /// the learner may start one lesson, and that lesson may run past it.
    public let newItemsRemaining: Int

    /// True when `newItemsRemaining` is greater than zero.
    ///
    /// This is the cap only. `pathState` decides whether a lesson is left
    /// in the course.
    public let canStartLesson: Bool

    public init(
        reviews: [ReviewCard],
        dueCount: Int,
        newItemsRemaining: Int,
        canStartLesson: Bool
    ) {
        self.reviews = reviews
        self.dueCount = dueCount
        self.newItemsRemaining = newItemsRemaining
        self.canStartLesson = canStartLesson
    }
}

/// The review queue and the new-item allowance for `today`.
///
/// A card is due when it is `active`, its item is in `knownItemIDs`, and
/// `dueDay` is on or before `today`. Paused cards are not due. The count is
/// taken before the cap of 50. The queue keeps the 50 with the oldest
/// `dueDay`, and `itemID.rawValue` breaks a tie. The same cards always come
/// out in the same order.
///
/// A card with `lastReviewedDay` equal to `today` is left out, so a card is
/// reviewed at most once on a civil day. A card whose `lastReviewedDay` is
/// after `today` is left out as well. That is a clock set back: the stored
/// day has not come round again. The card is not deleted, the count does not
/// go negative, and this function does not trap. Call it again when `today`
/// is after that `lastReviewedDay`. The card is queued then if it is still
/// due, on the same rules as any other card. On the stored review day itself
/// it stays out, because that day was already reviewed.
///
/// An item id that is not in `knownItemIDs` is left out of the queue and out
/// of `dueCount`. It is not removed from `cards`. The caller keeps it.
/// Pausing or deleting it belongs to progress reconciliation, which is a
/// later change. An empty `cards` list is an empty queue. The new-item
/// allowance is still the goal, because nothing is due. This function does
/// not know whether the course has another lesson.
///
/// New items follow `goal` when `dueCount` is 50 or less. More than 50 due
/// cards leaves `newItemsRemaining` at 0. `newItemsShownToday` is how many
/// new items were already introduced on `today`. The allowance is the goal
/// minus that number, and it is never negative, so a goal changed during the
/// day does not take shown items back. A negative shown count is treated as
/// zero. The shown count is an argument: a review also stores `today` on an
/// old card, so the cards alone cannot say which items were new.
///
/// `today` is a `LocalDay`. This function does not read a clock.
/// `pathState` reads this plan when it decides what the lesson path shows.
public func dailyPlan(
    cards: [ReviewCard],
    knownItemIDs: Set<ItemID>,
    goal: DailyGoal,
    newItemsShownToday: Int,
    on today: LocalDay
) -> DailyPlan {
    let due = cards.filter { isDue($0, knownItemIDs: knownItemIDs, on: today) }
    let ordered = due.sorted { left, right in
        if left.dueDay != right.dueDay {
            return left.dueDay < right.dueDay
        }
        return left.itemID.rawValue < right.itemID.rawValue
    }
    let allowance = due.count > DailyPlan.maximumReviews ? 0 : goal.newItemLimit
    let shown = max(0, newItemsShownToday)
    let remaining = max(0, allowance - shown)
    return DailyPlan(
        reviews: Array(ordered.prefix(DailyPlan.maximumReviews)),
        dueCount: due.count,
        newItemsRemaining: remaining,
        canStartLesson: remaining > 0
    )
}

/// Active, known, and due on `today`, and not already reviewed on or after it.
private func isDue(_ card: ReviewCard, knownItemIDs: Set<ItemID>, on today: LocalDay) -> Bool {
    guard card.state == .active else { return false }
    guard knownItemIDs.contains(card.itemID) else { return false }
    guard card.dueDay <= today else { return false }
    if let lastReviewedDay = card.lastReviewedDay, lastReviewedDay >= today {
        return false
    }
    return true
}
