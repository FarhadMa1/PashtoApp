import Foundation

/// Short home labels for the released units.
///
/// The English is the word the home draws and VoiceOver reads.
/// A unit that is not in this list can still appear on the home: the row then
/// uses the unit's own title. The list is meant to match `release-units.json`.
public enum MainMenuLabels {
    public struct Entry: Equatable, Sendable {
        public var unitID: UnitID
        public var catalogKey: String
        /// The word the home draws.
        public var english: String

        public init(unitID: UnitID, catalogKey: String, english: String) {
            self.unitID = unitID
            self.catalogKey = catalogKey
            self.english = english
        }
    }

    public static let entries: [Entry] = [
        Entry(unitID: requiredUnit("u-basics"), catalogKey: "menu.unit.basics", english: "Basics"),
        Entry(unitID: requiredUnit("u-greetings"), catalogKey: "menu.unit.greetings", english: "Greetings"),
        Entry(unitID: requiredUnit("u-introductions"), catalogKey: "menu.unit.introduction", english: "Introduction"),
        Entry(unitID: requiredUnit("u-family"), catalogKey: "menu.unit.family", english: "Family"),
        Entry(unitID: requiredUnit("u-travel"), catalogKey: "menu.unit.travel", english: "Travel"),
        Entry(unitID: requiredUnit("u-time"), catalogKey: "menu.unit.time", english: "Time"),
        Entry(unitID: requiredUnit("u-numbers"), catalogKey: "menu.unit.numbers", english: "Numbers"),
        Entry(unitID: requiredUnit("u-food"), catalogKey: "menu.unit.food", english: "Food"),
        Entry(unitID: requiredUnit("u-town"), catalogKey: "menu.unit.town", english: "Town"),
        Entry(unitID: requiredUnit("u-conversation"), catalogKey: "menu.unit.conversation", english: "Conversation"),
    ]

    public static func entry(for unitID: UnitID) -> Entry? {
        entries.first { $0.unitID == unitID }
    }

    /// The stored word, or the unit title when this unit has no menu label.
    public static func word(for unitID: UnitID, title: String) -> String {
        entry(for: unitID)?.english ?? title
    }

    private static func requiredUnit(_ raw: String) -> UnitID {
        guard let id = UnitID(rawValue: raw) else {
            preconditionFailure("\(raw) is not a unit id")
        }
        return id
    }
}

/// One released unit on the home, in course order.
public struct MainMenuCategory: Equatable, Sendable, Identifiable {
    public var id: UnitID
    /// The unit's own title. The category page uses this, not the short label.
    public var title: String
    public var catalogKey: String
    /// The word the home draws.
    public var label: String
    /// Practice lessons in this unit whose ids are finished. Learn and phrases never add to this.
    public var practiceCompleted: Int
    /// Practice lessons in this unit. Learn and phrases are not in this count.
    public var practiceTotal: Int
    /// Lessons the home can open, in course order.
    public var lessons: [MainMenuLesson]
    /// Pictured words under the lesson groups. Empty when the unit has no pictured learn card.
    public var wordList: [FamilyWordList.Row]
    /// Card color family. Nil when the row is still a unit.
    public var colorFamily: String?
    public var level: Int?
    public var categoryNumber: Int?

    public init(
        id: UnitID,
        title: String,
        catalogKey: String,
        label: String,
        practiceCompleted: Int,
        practiceTotal: Int,
        lessons: [MainMenuLesson],
        wordList: [FamilyWordList.Row] = [],
        colorFamily: String? = nil,
        level: Int? = nil,
        categoryNumber: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.catalogKey = catalogKey
        self.label = label
        self.practiceCompleted = practiceCompleted
        self.practiceTotal = practiceTotal
        self.lessons = lessons
        self.wordList = wordList
        self.colorFamily = colorFamily
        self.level = level
        self.categoryNumber = categoryNumber
    }

    /// Completed practice lessons over the practice lessons in the unit. Empty is 0.
    public var fraction: Double {
        guard practiceTotal > 0 else { return 0 }
        return min(1, Double(practiceCompleted) / Double(practiceTotal))
    }

    public var isComplete: Bool {
        practiceTotal > 0 && practiceCompleted >= practiceTotal
    }
}

/// A lesson row on the category page.
public struct MainMenuLesson: Equatable, Sendable, Identifiable {
    public var id: LessonID
    public var title: String
    public var kind: LessonKind
    /// Finished practice only. Learn and phrases stay false.
    public var isComplete: Bool
    /// Derived from the lesson's items. Fresh menus are not started.
    public var status: LessonStudyStatus

    public init(
        id: LessonID,
        title: String,
        kind: LessonKind,
        isComplete: Bool,
        status: LessonStudyStatus = .notStarted
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.isComplete = isComplete
        self.status = status
    }
}

/// The next unfinished lesson Continue opens.
public struct MainMenuContinue: Equatable, Sendable {
    public var lessonID: LessonID
    public var lessonTitle: String
    public var unitID: UnitID
    public var unitLabel: String

    public init(lessonID: LessonID, lessonTitle: String, unitID: UnitID, unitLabel: String) {
        self.lessonID = lessonID
        self.lessonTitle = lessonTitle
        self.unitID = unitID
        self.unitLabel = unitLabel
    }
}

/// The home's unit rows.
///
/// Membership comes from `releasedUnitIDs` (the ids in `release-units.json`).
/// Order is the course order of those units. A unit that is only in the bundle
/// is left out. Practice progress counts practice lessons in the unit.
/// Continue uses the first of these units that still has Practice left.
/// None finished there opens its first Learn lesson, or its first lesson
/// when it has none. Some finished opens the next unfinished Practice
/// lesson. When every unit's Practice is done, Continue is absent.
public struct MainMenu: Equatable, Sendable {
    public var categories: [MainMenuCategory]
    public var continueTarget: MainMenuContinue?

    public init(categories: [MainMenuCategory], continueTarget: MainMenuContinue?) {
        self.categories = categories
        self.continueTarget = continueTarget
    }

    public static func make(
        in bundle: ContentBundle,
        releasedUnitIDs: [UnitID],
        finishedLessonIDs: Set<LessonID>,
        listedLessons: [ReleasedLesson],
        showsPronunciation: Bool = true,
        learnedItemIDs: Set<ItemID>? = nil
    ) -> MainMenu {
        if !bundle.categories.isEmpty {
            return categoryMenu(
                bundle: ReleasedCatalog.showing(bundle),
                releasedUnitIDs: releasedUnitIDs,
                finishedLessonIDs: finishedLessonIDs,
                listedLessons: listedLessons,
                showsPronunciation: showsPronunciation,
                learnedItemIDs: learnedItemIDs
            )
        }
        let released = Set(releasedUnitIDs)
        let units = bundle.units.filter { released.contains($0.id) }
        let categories = units.map { unit in
            category(
                unit,
                in: bundle,
                finishedLessonIDs: finishedLessonIDs,
                listedLessons: listedLessons,
                showsPronunciation: showsPronunciation,
                learnedItemIDs: learnedItemIDs
            )
        }
        return MainMenu(
            categories: categories,
            continueTarget: continueTarget(
                units: units,
                finishedLessonIDs: finishedLessonIDs,
                learnedItemIDs: learnedItemIDs
            )
        )
    }

    /// Home rows for categories that have a lesson in a released unit.
    /// Order is level, then category number. The row id is `u-cat-N`.
    private static func categoryMenu(
        bundle: ContentBundle,
        releasedUnitIDs: [UnitID],
        finishedLessonIDs: Set<LessonID>,
        listedLessons: [ReleasedLesson],
        showsPronunciation: Bool,
        learnedItemIDs: Set<ItemID>?
    ) -> MainMenu {
        let released = Set(releasedUnitIDs)
        var pairs: [Int: [(lesson: Lesson, unitID: UnitID)]] = [:]
        for unit in bundle.units where released.contains(unit.id) {
            for lesson in unit.lessons {
                guard let number = lesson.categoryNumber else { continue }
                pairs[number, default: []].append((lesson, unit.id))
            }
        }
        let ordered = bundle.categories
            .filter { pairs[$0.number] != nil }
            .sorted { lhs, rhs in
                if lhs.level != rhs.level { return lhs.level < rhs.level }
                return lhs.number < rhs.number
            }
        let listedByID = Dictionary(uniqueKeysWithValues: listedLessons.map { ($0.id, $0) })
        let rows = ordered.map { category in
            categoryRow(
                category,
                lessons: pairs[category.number] ?? [],
                in: bundle,
                finishedLessonIDs: finishedLessonIDs,
                listedByID: listedByID,
                showsPronunciation: showsPronunciation,
                learnedItemIDs: learnedItemIDs
            )
        }
        return MainMenu(
            categories: rows,
            continueTarget: categoryContinue(
                ordered: ordered,
                pairs: pairs,
                finishedLessonIDs: finishedLessonIDs,
                learnedItemIDs: learnedItemIDs
            )
        )
    }

    private static func categoryRow(
        _ category: CourseCategory,
        lessons pairs: [(lesson: Lesson, unitID: UnitID)],
        in bundle: ContentBundle,
        finishedLessonIDs: Set<LessonID>,
        listedByID: [LessonID: ReleasedLesson],
        showsPronunciation: Bool,
        learnedItemIDs: Set<ItemID>?
    ) -> MainMenuCategory {
        let practice = pairs.map(\.lesson).filter { $0.kind == .practice }
        let completed = practice.filter {
            isPracticeDone($0, finished: finishedLessonIDs, learned: learnedItemIDs)
        }.count
        let lessons = pairs.compactMap { pair -> MainMenuLesson? in
            guard let listed = listedByID[pair.lesson.id] else { return nil }
            let status = studyStatus(pair.lesson, finished: finishedLessonIDs, learned: learnedItemIDs)
            return MainMenuLesson(
                id: listed.id,
                title: listed.title,
                kind: listed.kind,
                isComplete: listed.kind == .practice && status == .done,
                status: status
            )
        }
        guard let id = UnitID(rawValue: "u-cat-\(category.number)") else {
            preconditionFailure("u-cat-\(category.number) is not a unit id")
        }
        return MainMenuCategory(
            id: id,
            title: category.title,
            catalogKey: "menu.category.\(category.number)",
            label: category.title,
            practiceCompleted: completed,
            practiceTotal: practice.count,
            lessons: lessons,
            wordList: FamilyWordList.rows(
                lessons: pairs,
                in: bundle,
                showsPronunciation: showsPronunciation
            ),
            colorFamily: category.colorFamily,
            level: category.level,
            categoryNumber: category.number
        )
    }

    private static func categoryContinue(
        ordered: [CourseCategory],
        pairs: [Int: [(lesson: Lesson, unitID: UnitID)]],
        finishedLessonIDs: Set<LessonID>,
        learnedItemIDs: Set<ItemID>?
    ) -> MainMenuContinue? {
        for category in ordered {
            let lessons = pairs[category.number]?.map(\.lesson) ?? []
            let practice = lessons.filter { $0.kind == .practice }
            guard !practice.isEmpty, practice.contains(where: {
                !isPracticeDone($0, finished: finishedLessonIDs, learned: learnedItemIDs)
            }) else { continue }
            let completed = practice.filter {
                isPracticeDone($0, finished: finishedLessonIDs, learned: learnedItemIDs)
            }.count
            let chosen: Lesson?
            if completed == 0 {
                chosen = lessons.first { $0.kind == .learn } ?? lessons.first
            } else {
                chosen = practice.first {
                    !isPracticeDone($0, finished: finishedLessonIDs, learned: learnedItemIDs)
                }
            }
            guard let chosen, let id = UnitID(rawValue: "u-cat-\(category.number)") else { return nil }
            return MainMenuContinue(
                lessonID: chosen.id,
                lessonTitle: chosen.title,
                unitID: id,
                unitLabel: category.title
            )
        }
        return nil
    }

    private static func practiceLessons(in unit: CourseUnit) -> [Lesson] {
        unit.lessons.filter { $0.kind == .practice }
    }

    private static func category(
        _ unit: CourseUnit,
        in bundle: ContentBundle,
        finishedLessonIDs: Set<LessonID>,
        listedLessons: [ReleasedLesson],
        showsPronunciation: Bool,
        learnedItemIDs: Set<ItemID>?
    ) -> MainMenuCategory {
        let practice = practiceLessons(in: unit)
        let completed = practice.filter {
            isPracticeDone($0, finished: finishedLessonIDs, learned: learnedItemIDs)
        }.count
        let entry = MainMenuLabels.entry(for: unit.id)
        let lessons = listedLessons.filter { $0.unitID == unit.id }.map { listed in
            let source = unit.lessons.first { $0.id == listed.id }
            let status = studyStatus(source, finished: finishedLessonIDs, learned: learnedItemIDs)
            return MainMenuLesson(
                id: listed.id,
                title: listed.title,
                kind: listed.kind,
                isComplete: listed.kind == .practice && status == .done,
                status: status
            )
        }
        return MainMenuCategory(
            id: unit.id,
            title: unit.title,
            catalogKey: entry?.catalogKey ?? "",
            label: entry?.english ?? unit.title,
            practiceCompleted: completed,
            practiceTotal: practice.count,
            lessons: lessons,
            wordList: FamilyWordList.rows(
                for: unit.id,
                in: bundle,
                showsPronunciation: showsPronunciation
            )
        )
    }

    /// The first released unit that still has Practice left, then the lesson Continue opens.
    private static func continueTarget(
        units: [CourseUnit],
        finishedLessonIDs: Set<LessonID>,
        learnedItemIDs: Set<ItemID>?
    ) -> MainMenuContinue? {
        guard let unit = units.first(where: {
            let practice = practiceLessons(in: $0)
            return !practice.isEmpty && practice.contains {
                !isPracticeDone($0, finished: finishedLessonIDs, learned: learnedItemIDs)
            }
        }) else {
            return nil
        }
        let practice = practiceLessons(in: unit)
        let completed = practice.filter {
            isPracticeDone($0, finished: finishedLessonIDs, learned: learnedItemIDs)
        }.count
        let chosen: Lesson?
        if completed == 0 {
            chosen = unit.lessons.first { $0.kind == .learn } ?? unit.lessons.first
        } else {
            chosen = practice.first {
                !isPracticeDone($0, finished: finishedLessonIDs, learned: learnedItemIDs)
            }
        }
        guard let chosen else { return nil }
        return MainMenuContinue(
            lessonID: chosen.id,
            lessonTitle: chosen.title,
            unitID: unit.id,
            unitLabel: MainMenuLabels.word(for: unit.id, title: unit.title)
        )
    }

    /// A practice lesson is done when every item it introduces is learned.
    /// Without a learned set, a stored finished id means the same thing.
    private static func isPracticeDone(
        _ lesson: Lesson,
        finished: Set<LessonID>,
        learned: Set<ItemID>?
    ) -> Bool {
        guard lesson.kind == .practice else { return false }
        if let learned {
            return LessonStudyStatus.resolve(itemIDs: lesson.items.map(\.item), learned: learned) == .done
        }
        return finished.contains(lesson.id)
    }

    private static func studyStatus(
        _ lesson: Lesson?,
        finished: Set<LessonID>,
        learned: Set<ItemID>?
    ) -> LessonStudyStatus {
        guard let lesson else { return .notStarted }
        if let learned {
            return LessonStudyStatus.resolve(itemIDs: lesson.items.map(\.item), learned: learned)
        }
        if lesson.kind == .practice, finished.contains(lesson.id) {
            return .done
        }
        return .notStarted
    }
}
