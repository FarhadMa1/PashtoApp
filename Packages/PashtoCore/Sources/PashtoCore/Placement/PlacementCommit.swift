/// Lesson rows, placement cards, and the day the test was taken.
///
/// The store writes all three in one save. A day with no skipped units still
/// belongs here: the test was taken, so it is not offered again.
public struct PlacementCommit: Hashable, Sendable {
    public let lessonProgress: [LessonProgress]
    public let cards: [ReviewCard]
    public let placementTakenDay: LocalDay

    public init(
        lessonProgress: [LessonProgress],
        cards: [ReviewCard],
        placementTakenDay: LocalDay
    ) {
        self.lessonProgress = lessonProgress
        self.cards = cards
        self.placementTakenDay = placementTakenDay
    }
}

/// The rows a finished placement test stores.
///
/// Each lesson in a skipped unit becomes `LessonProgress` with source
/// `placement`. The percent is that unit's correct answers over its questions.
/// Items those lessons introduce become placement cards, spread from `takenOn`.
/// A `soundExample` does not become a card. The alphabet, the first unit, is
/// dropped even if a score names it.
///
/// A lesson row that is already stored stays out, and so does an item that
/// already has a card. The first completion, its score, and the existing card
/// remain. The store keeps that promise even when a commit still names them.
public func placementCommit(
    scores: [PlacementUnitScore],
    in bundle: ContentBundle,
    takenOn day: LocalDay,
    existingCards: [ReviewCard] = [],
    existingLessons: [LessonProgress] = []
) -> PlacementCommit {
    let playable = PlayableCourse.hidingScript(bundle)
    let alphabet = playable.units.first?.id
    var skipped: [PlacementUnitScore] = []
    var seenUnits = Set<UnitID>()
    for score in scores where score.skipped && score.unitID != alphabet {
        guard seenUnits.insert(score.unitID).inserted else { continue }
        skipped.append(score)
    }

    var knownLessons = Set<LessonID>()
    for lesson in existingLessons {
        knownLessons.insert(lesson.lessonID)
    }
    var lessons: [LessonProgress] = []
    for score in skipped {
        guard let unit = playable.units.first(where: { $0.id == score.unitID }) else { continue }
        let percent = scorePercent(correct: score.correct, questions: score.questions)
        for lesson in unit.lessons where lesson.countsForProgress && knownLessons.insert(lesson.id).inserted {
            lessons.append(LessonProgress(
                lessonID: lesson.id,
                source: .placement,
                firstCompletedDay: day,
                bestScorePercent: percent
            ))
        }
    }

    let skippedIDs = Set(skipped.map(\.unitID))
    var knownItems = Set(existingCards.map(\.itemID))
    var itemIDs: [ItemID] = []
    let course = CourseOrder(playable)
    for introduction in course.introductions {
        let unitID = playable.units[introduction.unitIndex].id
        guard skippedIDs.contains(unitID) else { continue }
        guard knownItems.insert(introduction.itemID).inserted else { continue }
        itemIDs.append(introduction.itemID)
    }

    return PlacementCommit(
        lessonProgress: lessons,
        cards: PlacementScheduler.cards(for: itemIDs, takenOn: day),
        placementTakenDay: day
    )
}

private func scorePercent(correct: Int, questions: Int) -> Int {
    guard questions > 0 else { return 0 }
    let percent = (correct * 100) / questions
    if percent < 0 { return 0 }
    if percent > 100 { return 100 }
    return percent
}
