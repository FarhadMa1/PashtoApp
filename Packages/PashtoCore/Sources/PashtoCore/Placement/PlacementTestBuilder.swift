/// The questions for one placement unit, in the order they are asked.
public struct PlacementUnitQuestions: Hashable, Sendable {
    public let unitID: UnitID
    public let tasks: [SessionTask]

    public init(unitID: UnitID, tasks: [SessionTask]) {
        self.unitID = unitID
        self.tasks = tasks
    }
}

/// The units the placement test asks, in course order.
///
/// The first unit of the course, the alphabet, is never here. A unit is here
/// only when it sits in the policy's window, it is in the bundle, and its id
/// is in the released list. A unit the bundle does not contain is left out,
/// and the test has no empty unit.
public struct PlacementTest: Hashable, Sendable {
    public let units: [PlacementUnitQuestions]

    public init(units: [PlacementUnitQuestions]) {
        self.units = units
    }

    public var unitIDs: [UnitID] { units.map(\.unitID) }
}

/// Builds the placement questions from the same generators a lesson uses.
///
/// `releasedUnitIDs` is the list from `release-units.json`: the units the
/// learner can actually open. An id in the bundle but missing from that list
/// is not asked. The alphabet stays out even when it is released.
///
/// The walk stops when a released unit cannot fill `questionsPerUnit`. Later
/// units are not asked, and that unit is not stored as an empty session.
/// The same `rng` and the same seed build the same test.
public enum PlacementTestBuilder {
    public static func build(
        in bundle: ContentBundle,
        releasedUnitIDs: [UnitID],
        policy: PlacementPolicy = .standard,
        using rng: inout some RandomNumberGenerator
    ) -> PlacementTest {
        guard policy.questionsPerUnit > 0, policy.unitCount > 0 else {
            return PlacementTest(units: [])
        }
        let released = Set(releasedUnitIDs)
        let window = bundle.units.dropFirst().prefix(policy.unitCount)
        var units: [PlacementUnitQuestions] = []
        for unit in window {
            guard released.contains(unit.id) else { continue }
            guard let tasks = questions(for: unit, in: bundle, count: policy.questionsPerUnit, using: &rng) else {
                break
            }
            units.append(PlacementUnitQuestions(unitID: unit.id, tasks: tasks))
        }
        return PlacementTest(units: units)
    }

    /// One task for each introduced item, drawn with `rng`, then `count` of those.
    ///
    /// Nil when the unit cannot fill `count`. The unit's own lessons are the
    /// seen set, so the generators can use that unit and still refuse later units.
    private static func questions(
        for unit: CourseUnit,
        in bundle: ContentBundle,
        count: Int,
        using rng: inout some RandomNumberGenerator
    ) -> [SessionTask]? {
        let course = CourseOrder(bundle)
        guard let unitIndex = bundle.units.firstIndex(where: { $0.id == unit.id }) else { return nil }
        let targets = course.introductions.compactMap { introduction -> ContentItem? in
            guard introduction.unitIndex == unitIndex else { return nil }
            return course.itemsByID[introduction.itemID]
        }
        let context = QuizContext(
            bundle: bundle,
            seenLessonIDs: unit.lessons.map(\.id)
        )
        let draft = LessonSessionBuilder.draft(for: targets, in: context, using: &rng)
        var onePerItem: [SessionTask] = []
        for tasks in draft.perItem {
            let ordered = shuffled(tasks, using: &rng)
            if let first = ordered.first {
                onePerItem.append(first)
            }
        }
        if onePerItem.count < count {
            onePerItem.append(contentsOf: draft.shared)
        }
        guard onePerItem.count >= count else { return nil }
        return Array(shuffled(onePerItem, using: &rng).prefix(count))
    }
}
