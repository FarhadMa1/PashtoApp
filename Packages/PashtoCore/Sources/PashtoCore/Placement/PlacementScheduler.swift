/// Spreads placement cards from the day after the test was taken.
///
/// The cards stay in the order they are given. That order is the course order
/// of the items the skipped units introduce. At most `maximumPerDay` cards are
/// due on one civil day. The first batch is due on the day after `takenOn`.
/// The next batch is due the day after that, and the spread continues past
/// the first week. `createdDay` stays `takenOn`.
public enum PlacementScheduler {
    /// Cards due on one civil day.
    public static let maximumPerDay = 10

    public static func cards(
        for itemIDs: [ItemID],
        takenOn day: LocalDay,
        perDay: Int = maximumPerDay
    ) -> [ReviewCard] {
        guard perDay > 0 else { return [] }
        return itemIDs.enumerated().map { index, itemID in
            ReviewCard(
                itemID: itemID,
                easeFactor: ReviewCard.initialEaseFactor,
                intervalDays: 0,
                repetitions: 0,
                lapses: 0,
                dueDay: day.adding(days: index / perDay + 1),
                lastReviewedDay: nil,
                createdDay: day,
                state: .active,
                source: .placement
            )
        }
    }
}
