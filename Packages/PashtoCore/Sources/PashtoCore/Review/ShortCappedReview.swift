/// The review queue for one day, already capped.
///
/// `cards` is `dailyPlan`'s queue. That queue keeps at most
/// `DailyPlan.maximumReviews` due cards, oldest `dueDay` first. This value
/// does not add a second cap and it does not store cards.
public struct ShortCappedReview: Equatable, Sendable {
    public let cards: [ReviewCard]

    public init(cards: [ReviewCard]) {
        self.cards = cards
    }
}

/// The short review a learner can start today.
///
/// The cards are the due queue from `dailyPlan`, so the cap of 50, the
/// order, and the rules for a paused or already-reviewed card stay in one
/// place. `day` is an argument. This function does not read a clock.
public func shortCappedReview(
    cards: [ReviewCard],
    knownItemIDs: Set<ItemID>,
    goal: DailyGoal,
    newItemsShownToday: Int,
    on day: LocalDay
) -> ShortCappedReview {
    let plan = dailyPlan(
        cards: cards,
        knownItemIDs: knownItemIDs,
        goal: goal,
        newItemsShownToday: newItemsShownToday,
        on: day
    )
    return ShortCappedReview(cards: plan.reviews)
}
