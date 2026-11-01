/// An SM-2 quality grade, from 0 through 5.
///
/// The quiz uses three of them. A correct answer on the first attempt is 4.
/// A correct answer after the question was asked again is 3. A wrong answer
/// is 1.
public struct ReviewQuality: Hashable, Sendable {
    public let value: Int

    /// Correct on the first attempt.
    public static let firstAttempt = ReviewQuality(4)
    /// Correct after a wrong answer sent the question back once.
    public static let afterRetry = ReviewQuality(3)
    /// Wrong.
    public static let incorrect = ReviewQuality(1)

    public init(_ value: Int) {
        precondition((0...5).contains(value), "SM-2 quality must be from 0 through 5")
        self.value = value
    }
}

/// The grade for one quiz answer.
///
/// `isRepeat` is true when the question was appended after a miss. A wrong
/// answer is 1 whether or not it is a repeat.
public func reviewQuality(result: GradeResult, isRepeat: Bool) -> ReviewQuality {
    switch result {
    case .incorrect:
        return .incorrect
    case .correct:
        return isRepeat ? .afterRetry : .firstAttempt
    }
}

/// The grade for one stored session answer.
public func reviewQuality(for answer: SessionAnswer) -> ReviewQuality {
    reviewQuality(result: answer.result, isRepeat: answer.task.isRepeat)
}

/// The card after one review on `day`.
///
/// The day is an argument. This function does not read a clock.
///
/// Successful reviews (`quality` 3 or more) schedule 1 day, then 6 days, then
/// the previous interval multiplied by the ease from before this review.
/// That product is rounded to the nearest day, and a tie rounds away from
/// zero, so 12.5 becomes 13. A quality below 3 sets repetitions back to 0,
/// sets the interval to 1 day, and adds one lapse. Ease moves by the SM-2
/// step and is then kept at 1.3 or above.
///
/// The next interval does not use how many days passed. A `lastReviewedDay`
/// later than `day` (the clock was set back) does not zero the card and does
/// not produce a negative interval. `dueDay` is `day` plus the new interval,
/// so it is never earlier than the day after `day`.
public func review(_ card: ReviewCard, quality: ReviewQuality, on day: LocalDay) -> ReviewCard {
    let ease = easeThousandths(of: card.easeFactor)
    let scheduled = nextSchedule(card, quality: quality.value, ease: ease)
    let interval = max(1, scheduled.intervalDays)
    return ReviewCard(
        itemID: card.itemID,
        easeFactor: Double(scheduled.ease) / 1000,
        intervalDays: interval,
        repetitions: scheduled.repetitions,
        lapses: scheduled.lapses,
        dueDay: day.adding(days: interval),
        lastReviewedDay: day,
        state: card.state,
        source: card.source
    )
}

private struct ScheduledCard {
    var ease: Int
    var intervalDays: Int
    var repetitions: Int
    var lapses: Int
}

/// Ease is kept in thousandths so each SM-2 step (0.02, 0.10, 0.14, …) is exact.
private func easeThousandths(of ease: Double) -> Int {
    Int((ease * 1000).rounded(.toNearestOrAwayFromZero))
}

/// `100 - (5-q) * (80 + (5-q) * 20)` is the SM-2 ease step in thousandths.
private func nextEaseThousandths(current: Int, quality: Int) -> Int {
    let drop = 5 - quality
    let delta = 100 - drop * (80 + drop * 20)
    return max(1_300, current + delta)
}

/// Nearest day. A positive half (12.5) rounds away from zero, to 13.
private func roundedIntervalDays(previous: Int, easeThousandths: Int) -> Int {
    let product = previous * easeThousandths
    let rounded = product >= 0 ? (product + 500) / 1000 : (product - 500) / 1000
    return rounded
}

private func nextSchedule(_ card: ReviewCard, quality: Int, ease: Int) -> ScheduledCard {
    let nextEase = nextEaseThousandths(current: ease, quality: quality)
    if quality < 3 {
        return ScheduledCard(
            ease: nextEase,
            intervalDays: 1,
            repetitions: 0,
            lapses: card.lapses + 1
        )
    }

    let interval: Int
    switch card.repetitions {
    case 0:
        interval = 1
    case 1:
        interval = 6
    default:
        interval = roundedIntervalDays(previous: card.intervalDays, easeThousandths: ease)
    }
    return ScheduledCard(
        ease: nextEase,
        intervalDays: interval,
        repetitions: card.repetitions + 1,
        lapses: card.lapses
    )
}
