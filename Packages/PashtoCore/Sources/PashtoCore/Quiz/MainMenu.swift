import Foundation

/// Short home labels for the released units.
///
/// The English is the word VoiceOver reads. The home draws it in uppercase.
/// A unit that is not in this list can still appear on the home: the row then
/// uses the unit's own title. The list is meant to match `release-units.json`.
public enum MainMenuLabels {
    public struct Entry: Equatable, Sendable {
        public var unitID: UnitID
        public var catalogKey: String
        /// Stored word. Not the uppercase drawing.
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
    /// Stored word. The home uppercases it when it draws the row.
    public var label: String
    /// Practice lessons in this unit whose ids are finished. Learn and phrases never add to this.
    public var practiceCompleted: Int
    /// Practice lessons in this unit. Learn and phrases are not in this count.
    public var practiceTotal: Int
    /// Lessons the home can open, in course order.
    public var lessons: [MainMenuLesson]

    public init(
        id: UnitID,
        title: String,
        catalogKey: String,
        label: String,
        practiceCompleted: Int,
        practiceTotal: Int,
        lessons: [MainMenuLesson]
    ) {
        self.id = id
        self.title = title
        self.catalogKey = catalogKey
        self.label = label
        self.practiceCompleted = practiceCompleted
        self.practiceTotal = practiceTotal
        self.lessons = lessons
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

    public init(id: LessonID, title: String, kind: LessonKind, isComplete: Bool) {
        self.id = id
        self.title = title
        self.kind = kind
        self.isComplete = isComplete
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
        listedLessons: [ReleasedLesson]
    ) -> MainMenu {
        let released = Set(releasedUnitIDs)
        let units = bundle.units.filter { released.contains($0.id) }
        let categories = units.map { unit in
            category(unit, finishedLessonIDs: finishedLessonIDs, listedLessons: listedLessons)
        }
        return MainMenu(
            categories: categories,
            continueTarget: continueTarget(units: units, finishedLessonIDs: finishedLessonIDs)
        )
    }

    private static func practiceLessons(in unit: CourseUnit) -> [Lesson] {
        unit.lessons.filter { $0.kind == .practice }
    }

    private static func category(
        _ unit: CourseUnit,
        finishedLessonIDs: Set<LessonID>,
        listedLessons: [ReleasedLesson]
    ) -> MainMenuCategory {
        let practice = practiceLessons(in: unit)
        let completed = practice.filter { finishedLessonIDs.contains($0.id) }.count
        let entry = MainMenuLabels.entry(for: unit.id)
        let lessons = listedLessons.filter { $0.unitID == unit.id }.map { lesson in
            MainMenuLesson(
                id: lesson.id,
                title: lesson.title,
                kind: lesson.kind,
                isComplete: lesson.kind == .practice && finishedLessonIDs.contains(lesson.id)
            )
        }
        return MainMenuCategory(
            id: unit.id,
            title: unit.title,
            catalogKey: entry?.catalogKey ?? "",
            label: entry?.english ?? unit.title,
            practiceCompleted: completed,
            practiceTotal: practice.count,
            lessons: lessons
        )
    }

    /// The first released unit that still has Practice left, then the lesson Continue opens.
    private static func continueTarget(
        units: [CourseUnit],
        finishedLessonIDs: Set<LessonID>
    ) -> MainMenuContinue? {
        guard let unit = units.first(where: {
            let practice = practiceLessons(in: $0)
            return !practice.isEmpty && practice.contains { !finishedLessonIDs.contains($0.id) }
        }) else {
            return nil
        }
        let practice = practiceLessons(in: unit)
        let completed = practice.filter { finishedLessonIDs.contains($0.id) }.count
        let chosen: Lesson?
        if completed == 0 {
            chosen = unit.lessons.first { $0.kind == .learn } ?? unit.lessons.first
        } else {
            chosen = practice.first { !finishedLessonIDs.contains($0.id) }
        }
        guard let chosen else { return nil }
        return MainMenuContinue(
            lessonID: chosen.id,
            lessonTitle: chosen.title,
            unitID: unit.id,
            unitLabel: MainMenuLabels.word(for: unit.id, title: unit.title)
        )
    }
}
