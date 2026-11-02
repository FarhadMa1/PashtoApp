/// Whether a review card is in the queue.
///
/// Paused cards stay stored. This type does not decide when a card is paused.
public enum ReviewCardState: String, Codable, Hashable, Sendable {
    case active
    case paused
}

/// Why the card was created.
///
/// `lesson` is an item the learner was introduced to. `placement` is reserved
/// for a unit the placement test skipped. Spreading those cards across the
/// first week is a later step.
public enum ReviewCardSource: String, Codable, Hashable, Sendable {
    case lesson
    case placement
}

/// One item the learner will review.
///
/// A new card starts at ease 2.5, with no repetitions and no lapses.
/// `dueDay` and `lastReviewedDay` are civil dates. The review function takes
/// the day as a `LocalDay` and does not read the clock.
public struct ReviewCard: Hashable, Codable, Sendable {
    /// Ease before the first review. Quality 4 leaves this value unchanged.
    public static let initialEaseFactor = 2.5
    /// SM-2 never stores an ease below this.
    public static let minimumEaseFactor = 1.3
    /// Longest interval `review` will schedule, in days. The same ceiling Anki uses.
    ///
    /// `LocalDay` traps on a date after year 9999. The stored interval times the
    /// ease factor can otherwise land `dueDay` past that year. Every new
    /// interval is kept at or below this value, including when the stored
    /// interval or ease is already too large.
    public static let maximumIntervalDays = 36_500

    public let itemID: ItemID
    public let easeFactor: Double
    public let intervalDays: Int
    public let repetitions: Int
    public let lapses: Int
    public let dueDay: LocalDay
    public let lastReviewedDay: LocalDay?
    /// The civil day the card was created. A review does not change it.
    ///
    /// Lesson cards whose `createdDay` is today are the new items for that
    /// day. A placement card is never a new item, on the day it was created
    /// or later.
    public let createdDay: LocalDay
    public let state: ReviewCardState
    public let source: ReviewCardSource

    public init(
        itemID: ItemID,
        easeFactor: Double,
        intervalDays: Int,
        repetitions: Int,
        lapses: Int,
        dueDay: LocalDay,
        lastReviewedDay: LocalDay?,
        createdDay: LocalDay,
        state: ReviewCardState,
        source: ReviewCardSource
    ) {
        self.itemID = itemID
        self.easeFactor = easeFactor
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.lapses = lapses
        self.dueDay = dueDay
        self.lastReviewedDay = lastReviewedDay
        self.createdDay = createdDay
        self.state = state
        self.source = source
    }

    /// A card for an item that was just introduced or skipped in placement.
    ///
    /// The card is due on `day` and has not been reviewed. `createdDay` is
    /// `day`. The first successful review schedules the one-day interval.
    public static func introduced(
        itemID: ItemID,
        on day: LocalDay,
        source: ReviewCardSource = .lesson
    ) -> ReviewCard {
        ReviewCard(
            itemID: itemID,
            easeFactor: initialEaseFactor,
            intervalDays: 0,
            repetitions: 0,
            lapses: 0,
            dueDay: day,
            lastReviewedDay: nil,
            createdDay: day,
            state: .active,
            source: source
        )
    }
}

/// Cards for items a lesson introduces.
///
/// An `introduce` reference creates one card. A `soundExample` reference
/// creates none. Letter ids on the lesson are introductions too. The same id
/// twice in one lesson creates one card, and the first reference wins.
public func reviewCards(introducedIn lesson: Lesson, on day: LocalDay) -> [ReviewCard] {
    var seen: Set<ItemID> = []
    var cards: [ReviewCard] = []
    for reference in lesson.items where reference.role == .introduce {
        guard seen.insert(reference.item).inserted else { continue }
        cards.append(.introduced(itemID: reference.item, on: day))
    }
    for letter in lesson.letters {
        guard seen.insert(letter).inserted else { continue }
        cards.append(.introduced(itemID: letter, on: day))
    }
    return cards
}

/// Cards for every item the course introduces, in course order.
///
/// `soundExample` references are skipped. An id that is only a sound example
/// gets no card. An id introduced again later keeps the first card.
public func reviewCards(introducedIn bundle: ContentBundle, on day: LocalDay) -> [ReviewCard] {
    CourseOrder(bundle).introductions.map { introduction in
        ReviewCard.introduced(itemID: introduction.itemID, on: day)
    }
}
