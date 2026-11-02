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
/// only when it sits in the policy's window and every unit from the start of
/// that window through this one is released and can fill its questions. The
/// test has no empty unit.
public struct PlacementTest: Hashable, Sendable {
    public let units: [PlacementUnitQuestions]

    public init(units: [PlacementUnitQuestions]) {
        self.units = units
    }

    public var unitIDs: [UnitID] { units.map(\.unitID) }
}

/// Builds the placement questions from the same generators a lesson uses.
///
/// `releasedUnitIDs` is the list the caller took from `release-units.json`:
/// the units the learner can actually open. This type does not read that
/// file. The alphabet stays out even when it is released.
///
/// The walk stops at the first unit in the window that is not released, so a
/// later unit is not asked when an earlier one is missing. It also stops when
/// a released unit cannot fill `questionsPerUnit`. That unit is not asked and
/// not skipped, and nothing after it is asked. The same `rng` and the same
/// seed build the same test.
///
/// Distractors come from the unit under test. A letter is only a distractor
/// for another letter. The other kinds use the pool the lesson generators
/// already use. Items from an earlier or a later unit are not used.
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
            guard released.contains(unit.id) else { break }
            guard let tasks = questions(for: unit, in: bundle, count: policy.questionsPerUnit, using: &rng) else {
                break
            }
            units.append(PlacementUnitQuestions(unitID: unit.id, tasks: tasks))
        }
        return PlacementTest(units: units)
    }

    /// Released units in the placement window that cannot fill their questions.
    ///
    /// The window is the first `unitCount` units after the alphabet, in course
    /// order. The alphabet is not included. An unreleased unit is not included.
    /// A released unit past the window is not included. An empty release list
    /// returns an empty array.
    public static func releasedUnitsThatCannotFillQuestions(
        in bundle: ContentBundle,
        releasedUnitIDs: [UnitID],
        policy: PlacementPolicy = .standard
    ) -> [UnitID] {
        guard policy.questionsPerUnit > 0, policy.unitCount > 0 else { return [] }
        let released = Set(releasedUnitIDs)
        let window = bundle.units.dropFirst().prefix(policy.unitCount)
        var short: [UnitID] = []
        var rng = PlacementFillCheck()
        for unit in window where released.contains(unit.id) {
            if questions(for: unit, in: bundle, count: policy.questionsPerUnit, using: &rng) == nil {
                short.append(unit.id)
            }
        }
        return short
    }

    /// One task for each introduced item, drawn with `rng`, then `count` of those.
    ///
    /// Nil when the unit cannot fill `count`. The unit's own lessons are the
    /// seen set, so a distractor is taken from this unit and not from another.
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

/// Fixed generator for the release check. The fill decision does not depend
/// on which distractor is drawn, only on whether enough exist.
private struct PlacementFillCheck: RandomNumberGenerator {
    var state: UInt64 = 0xA5A5_5A5A_1234_5678

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
