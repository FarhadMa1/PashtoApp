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

/// Applies the lesson quiz as the first review of each new card from `lesson`.
///
/// A new card has no `lastReviewedDay` and `source` `lesson`. Its item is one
/// this lesson introduces. `soundExample` references introduce nothing. Each
/// new card whose item has a `lessonReviewQuality` is passed to `review` on
/// `day`. The new interval is at least one day, so the card is due on the day
/// after `day` at the earliest, and `dailyPlan` leaves it out of `day`.
///
/// A new card from this lesson with no single-item grade is not reviewed.
/// Match pairs are the case that produces no grade. Its `dueDay` moves to
/// the day after `day` when it would have been earlier, and no other field
/// changes: repetitions, ease, interval, lapses, `lastReviewedDay`, and
/// `createdDay` stay as they were. It still does not enter today's queue.
/// A due day that is already the next day or later stays where it is.
///
/// A card that was already reviewed is returned unchanged. So is a placement
/// card, and so is a card this lesson does not introduce. Cards stay in their
/// original order. This function does not read a clock.
public func applyLessonReviews(
    _ cards: [ReviewCard],
    introducedIn lesson: Lesson,
    answers: [SessionAnswer],
    on day: LocalDay
) -> [ReviewCard] {
    let introduced = Set(reviewCards(introducedIn: lesson, on: day).map(\.itemID))
    let earliest = day.adding(days: 1)
    return cards.map { card in
        guard card.source == .lesson, introduced.contains(card.itemID) else { return card }
        guard card.lastReviewedDay == nil else { return card }
        if let quality = lessonReviewQuality(for: card.itemID, answers: answers) {
            return review(card, quality: quality, on: day)
        }
        guard card.dueDay < earliest else { return card }
        return ReviewCard(
            itemID: card.itemID,
            easeFactor: card.easeFactor,
            intervalDays: card.intervalDays,
            repetitions: card.repetitions,
            lapses: card.lapses,
            dueDay: earliest,
            lastReviewedDay: card.lastReviewedDay,
            createdDay: card.createdDay,
            state: card.state,
            source: card.source
        )
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
