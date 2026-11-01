/// The SM-2 grade a finished lesson gives one new card.
///
/// The grade comes from the first answer whose question targets `itemID`.
/// A correct first attempt is quality 4. A wrong first attempt is quality 1,
/// unless a later repeat of that item is correct, which is quality 3. The
/// lesson asks a miss once more, and that repeat is the next `isRepeat`
/// answer for the item. Answers after that first cycle do not change the
/// grade. A later question that is correct on its own first attempt does not
/// replace a miss.
///
/// Match pairs are not a grade for one item. One result covers every pair.
/// A word that was only answered inside a match has no lesson grade.
///
/// Answers are read in the order they were given. A word that was answered
/// several times still produces one grade. The function returns nil when no
/// single-item answer targets `itemID`.
public func lessonReviewQuality(for itemID: ItemID, answers: [SessionAnswer]) -> ReviewQuality? {
    let aboutItem = answers.filter { lessonTarget(of: $0.task) == itemID }
    guard let first = aboutItem.first else { return nil }
    if first.result == .correct {
        return reviewQuality(for: first)
    }
    if let retry = aboutItem.dropFirst().first(where: { $0.task.isRepeat }) {
        return retry.result == .correct ? .afterRetry : .incorrect
    }
    return .incorrect
}

/// Applies the lesson quiz as the first review of each new card.
///
/// A new card has no `lastReviewedDay`. Each such card whose item has a
/// `lessonReviewQuality` is passed to `review` on `day`. The new interval is
/// at least one day, so the card is due on the day after `day` at the
/// earliest, and `dailyPlan` leaves it out of `day`. A card that was already
/// reviewed is returned unchanged, and so is a card with no single-item
/// answer. Cards stay in their original order. This function does not read
/// a clock.
public func applyLessonReviews(
    _ cards: [ReviewCard],
    answers: [SessionAnswer],
    on day: LocalDay
) -> [ReviewCard] {
    cards.map { card in
        guard card.lastReviewedDay == nil else { return card }
        guard let quality = lessonReviewQuality(for: card.itemID, answers: answers) else {
            return card
        }
        return review(card, quality: quality, on: day)
    }
}

/// The one item a question grades, or nil for a match.
private func lessonTarget(of task: SessionTask) -> ItemID? {
    switch task.payload {
    case .choice(let quiz):
        return quiz.targetID
    case .orderWords(let order):
        return order.targetID
    case .matchPairs:
        return nil
    }
}
