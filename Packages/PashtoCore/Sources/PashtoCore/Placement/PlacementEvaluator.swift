/// The score for one unit after its questions have all been answered.
public struct PlacementUnitScore: Hashable, Sendable {
    public let unitID: UnitID
    public let correct: Int
    public let questions: Int
    /// True when `correct` reached the policy's skip line.
    public let skipped: Bool

    public init(unitID: UnitID, correct: Int, questions: Int, skipped: Bool) {
        self.unitID = unitID
        self.correct = correct
        self.questions = questions
        self.skipped = skipped
    }
}

/// What the test does after one answer.
public enum PlacementStep: Hashable, Sendable {
    /// This unit still has questions left.
    case ongoing
    /// The unit is skipped. `next` is the following unit, or nil when none remains.
    case skipped(UnitID, next: UnitID?)
    /// The unit stays in the course. Later units are not asked.
    case stopped(UnitID)
    /// Nothing is left to ask.
    case finished
}

/// The placement rules, with no stored course and no clock.
///
/// Feed it one answer at a time, in unit order. A unit with at least
/// `policy.correctToSkip` correct answers is skipped and the next unit starts.
/// A lower score stops the test. Answers after that do not skip a later unit.
public struct PlacementEvaluator: Hashable, Sendable {
    public let policy: PlacementPolicy
    public let unitIDs: [UnitID]
    public private(set) var results: [PlacementUnitScore]

    private var index: Int
    private var answered: Int
    private var correct: Int
    private var terminal: PlacementStep?

    public init(unitIDs: [UnitID], policy: PlacementPolicy = .standard) {
        self.policy = policy
        self.unitIDs = unitIDs
        results = []
        index = 0
        answered = 0
        correct = 0
        terminal = unitIDs.isEmpty || policy.questionsPerUnit <= 0 ? .finished : nil
    }

    public var isFinished: Bool { terminal != nil }

    /// Units that cleared the skip line, in the order they were asked.
    public var skippedUnitIDs: [UnitID] {
        results.compactMap { $0.skipped ? $0.unitID : nil }
    }

    @discardableResult
    public mutating func record(correct isCorrect: Bool) -> PlacementStep {
        if let terminal {
            return terminal
        }
        guard index < unitIDs.count else {
            terminal = .finished
            return .finished
        }
        answered += 1
        if isCorrect {
            correct += 1
        }
        guard answered >= policy.questionsPerUnit else {
            return .ongoing
        }

        let unitID = unitIDs[index]
        let hits = correct
        let questions = answered
        let skipped = hits >= policy.correctToSkip
        results.append(PlacementUnitScore(
            unitID: unitID,
            correct: hits,
            questions: questions,
            skipped: skipped
        ))
        answered = 0
        correct = 0
        index += 1

        if skipped {
            let next = index < unitIDs.count ? unitIDs[index] : nil
            if next == nil {
                terminal = .finished
            }
            return .skipped(unitID, next: next)
        }
        let step = PlacementStep.stopped(unitID)
        terminal = step
        return step
    }
}
