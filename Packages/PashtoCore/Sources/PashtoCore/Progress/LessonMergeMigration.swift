import Foundation

/// How far a lesson's own items have been learned.
///
/// A lesson is started when some of its items are learned and done when all of
/// them are. The stored file still uses lesson rows and cards. This status is
/// derived from item ids, so a merged lesson does not look finished just
/// because one of the old lesson ids was finished.
public enum LessonStudyStatus: String, Equatable, Sendable {
    case notStarted
    case started
    case done

    public static func resolve(itemIDs: [ItemID], learned: Set<ItemID>) -> LessonStudyStatus {
        let learnedCount = itemIDs.reduce(into: 0) { count, id in
            if learned.contains(id) { count += 1 }
        }
        if learnedCount == 0 { return .notStarted }
        if learnedCount == itemIDs.count { return .done }
        return .started
    }
}

/// Item-level progress for lessons that were merged or moved.
///
/// A finished lesson row still means every item that lesson introduced is
/// learned. A row for a practice lesson this merge removed is read from
/// `retiredIntroductions`, so those items stay learned without a new card.
/// `apply` does not add cards, change the streak, or change the daily goal.
public enum LessonMergeMigration {
    /// Practice lessons this merge removed, and the items they introduced.
    public static let retiredIntroductions: [LessonID: [ItemID]] = {
        let rows: [(String, [String])] = [
            (
                "l-greetings-2",
                ["e-tsanga-ye", "e-taso-tsanga-yast", "e-za-xa-yam", "e-xa", "e-manana", "e-dera-manana"]
            ),
            (
                "l-greetings-3",
                [
                    "e-dera-xa", "e-ho", "e-na", "e-baxana-ghwaram", "e-mehrabani-wakray",
                    "e-xoday-paman", "e-pa-maxa-de-xa",
                ]
            ),
            (
                "l-introductions-3",
                ["e-yam", "e-ye", "e-day", "e-da", "e-yast"]
            ),
        ]
        var map: [LessonID: [ItemID]] = [:]
        for (lesson, items) in rows {
            guard let lessonID = LessonID(rawValue: lesson) else { continue }
            map[lessonID] = items.compactMap(ItemID.init(rawValue:))
        }
        return map
    }()

    /// Items a stored snapshot has learned, including items of a removed lesson.
    ///
    /// A card counts. A finished practice lesson that is still in the course
    /// counts every item it introduces now. A finished row for a removed
    /// practice lesson counts the items in `retiredIntroductions`.
    public static func learnedItemIDs(in snapshot: ProgressSnapshot, content: ContentBundle) -> Set<ItemID> {
        var learned = Set(snapshot.cards.map(\.itemID))
        for row in snapshot.lessonProgress {
            if let retired = retiredIntroductions[row.lessonID] {
                learned.formUnion(retired)
                continue
            }
            guard let lesson = lesson(row.lessonID, in: content), lesson.kind == .practice else { continue }
            for reference in lesson.items where reference.role == .introduce {
                learned.insert(reference.item)
            }
        }
        return learned
    }

    /// Practice lessons whose introduce items are all learned.
    public static func finishedLessonIDs(learned: Set<ItemID>, in content: ContentBundle) -> Set<LessonID> {
        var finished: Set<LessonID> = []
        for unit in content.units {
            for lesson in unit.lessons where lesson.kind == .practice {
                let items = lesson.items.filter { $0.role == .introduce }.map(\.item)
                guard !items.isEmpty else { continue }
                if LessonStudyStatus.resolve(itemIDs: items, learned: learned) == .done {
                    finished.insert(lesson.id)
                }
            }
        }
        return finished
    }

    public static func status(
        of lesson: Lesson,
        learned: Set<ItemID>
    ) -> LessonStudyStatus {
        LessonStudyStatus.resolve(itemIDs: lesson.items.map(\.item), learned: learned)
    }

    /// Stored cards. The merge does not add or remove any.
    public static func wordsLearned(in snapshot: ProgressSnapshot) -> Int {
        snapshot.cards.count
    }

    /// The same snapshot, plus the derived status of every lesson.
    ///
    /// Cards, the streak, settings, and every other stored field are unchanged.
    public static func apply(
        _ snapshot: ProgressSnapshot,
        to content: ContentBundle
    ) -> LessonMergeOutcome {
        let learned = learnedItemIDs(in: snapshot, content: content)
        var statuses: [LessonID: LessonStudyStatus] = [:]
        for unit in content.units {
            for lesson in unit.lessons {
                statuses[lesson.id] = status(of: lesson, learned: learned)
            }
        }
        return LessonMergeOutcome(snapshot: snapshot, learnedItemIDs: learned, statuses: statuses)
    }

    private static func lesson(_ id: LessonID, in content: ContentBundle) -> Lesson? {
        for unit in content.units {
            if let lesson = unit.lessons.first(where: { $0.id == id }) {
                return lesson
            }
        }
        return nil
    }
}

/// Derived lesson status for one stored snapshot. The snapshot itself is unchanged.
public struct LessonMergeOutcome: Equatable, Sendable {
    public var snapshot: ProgressSnapshot
    public var learnedItemIDs: Set<ItemID>
    public var statuses: [LessonID: LessonStudyStatus]

    public init(
        snapshot: ProgressSnapshot,
        learnedItemIDs: Set<ItemID>,
        statuses: [LessonID: LessonStudyStatus]
    ) {
        self.snapshot = snapshot
        self.learnedItemIDs = learnedItemIDs
        self.statuses = statuses
    }

    public var wordsLearned: Int { LessonMergeMigration.wordsLearned(in: snapshot) }
}
