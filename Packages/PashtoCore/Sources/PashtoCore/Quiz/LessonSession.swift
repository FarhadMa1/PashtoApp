/// One question in a lesson, plus whether it was queued again after a miss.
public struct SessionTask: Hashable, Sendable {
    public enum Payload: Hashable, Sendable {
        case choice(QuizTask)
        case matchPairs(MatchPairsTask)
        case orderWords(OrderWordsTask)
    }

    public let payload: Payload
    /// True when this question was appended after a wrong answer.
    public let isRepeat: Bool

    public init(payload: Payload, isRepeat: Bool = false) {
        self.payload = payload
        self.isRepeat = isRepeat
    }

    public var kind: TaskKind {
        switch payload {
        case .choice(let task):
            return task.kind
        case .matchPairs:
            return .matchPairs
        case .orderWords:
            return .orderWords
        }
    }
}

public struct SessionAnswer: Hashable, Sendable {
    public let task: SessionTask
    public let answer: QuizAnswer
    public let result: GradeResult

    public init(task: SessionTask, answer: QuizAnswer, result: GradeResult) {
        self.task = task
        self.answer = answer
        self.result = result
    }
}

/// The questions still to answer, and the answers already given.
///
/// `submit` stores each answer as it happens. A wrong answer is appended to
/// the queue once. That repeat is not appended again if it is also wrong.
public struct LessonSession: Hashable, Sendable {
    public let lessonID: LessonID
    public private(set) var tasks: [SessionTask]
    public private(set) var answers: [SessionAnswer]

    public init(lessonID: LessonID, tasks: [SessionTask], answers: [SessionAnswer] = []) {
        self.lessonID = lessonID
        self.tasks = tasks
        self.answers = answers
    }

    public var current: SessionTask? { tasks.first }

    public var isComplete: Bool { tasks.isEmpty }

    @discardableResult
    public mutating func submit(_ answer: QuizAnswer) -> GradeResult? {
        guard let task = tasks.first else { return nil }
        tasks.removeFirst()
        let result = grade(task, answer)
        answers.append(SessionAnswer(task: task, answer: answer, result: result))
        if result == .incorrect, !task.isRepeat {
            tasks.append(SessionTask(payload: task.payload, isRepeat: true))
        }
        return result
    }
}

public func grade(_ task: SessionTask, _ answer: QuizAnswer) -> GradeResult {
    switch task.payload {
    case .choice(let quiz):
        return grade(quiz, answer)
    case .matchPairs(let match):
        return grade(match, answer)
    case .orderWords(let order):
        return grade(order, answer)
    }
}

/// Mixes the quiz kinds for one lesson, using only content the learner has seen.
///
/// The lesson being built counts as seen. An item is seen only when a seen
/// lesson introduces it. A `soundExample` reference does not count, so
/// `l-sounds-1` introduces nothing and its session is empty.
///
/// The same generator and the same seed produce the same session.
public enum LessonSessionBuilder {
    public static func build(
        for lessonID: LessonID,
        in bundle: ContentBundle,
        seenLessonIDs: [LessonID],
        retiredItemIDs: [ItemID] = [],
        using rng: inout some RandomNumberGenerator
    ) -> LessonSession {
        var seen = seenLessonIDs
        if !seen.contains(lessonID) {
            seen.append(lessonID)
        }
        let context = QuizContext(
            bundle: bundle,
            seenLessonIDs: seen,
            retiredItemIDs: retiredItemIDs
        )
        let targets = Distractors.introducedItems(in: lessonID, bundle: bundle)
        var tasks: [SessionTask] = []
        for target in targets {
            if let task = PashtoToEnglishChoice().makeTask(for: target, in: context, using: &rng) {
                tasks.append(SessionTask(payload: .choice(task)))
            }
            if let task = EnglishToPashtoChoice().makeTask(for: target, in: context, using: &rng) {
                tasks.append(SessionTask(payload: .choice(task)))
            }
            if let task = TransliterationChoice().makeTask(for: target, in: context, using: &rng) {
                tasks.append(SessionTask(payload: .choice(task)))
            }
            if let task = OrderWords.makeTask(for: target, in: context, using: &rng) {
                tasks.append(SessionTask(payload: .orderWords(task)))
            }
            if let task = DialogResponse().makeTask(for: target, in: context, using: &rng) {
                tasks.append(SessionTask(payload: .choice(task)))
            }
        }
        if let match = firstPashtoEnglish(in: targets.filter { $0.kind != .letter }, context: context, using: &rng) {
            tasks.append(SessionTask(payload: .matchPairs(match)))
        }
        if let match = firstPashtoEnglish(in: targets.filter { $0.kind == .letter }, context: context, using: &rng) {
            tasks.append(SessionTask(payload: .matchPairs(match)))
        }
        if let match = firstResponse(in: targets.filter { $0.responseTo != nil }, context: context, using: &rng) {
            tasks.append(SessionTask(payload: .matchPairs(match)))
        }
        return LessonSession(lessonID: lessonID, tasks: shuffled(tasks, using: &rng))
    }

    private static func firstPashtoEnglish(
        in anchors: [ContentItem],
        context: QuizContext,
        using rng: inout some RandomNumberGenerator
    ) -> MatchPairsTask? {
        for anchor in anchors {
            if let task = MatchPairs.pashtoEnglish(for: anchor, in: context, using: &rng) {
                return task
            }
        }
        return nil
    }

    private static func firstResponse(
        in anchors: [ContentItem],
        context: QuizContext,
        using rng: inout some RandomNumberGenerator
    ) -> MatchPairsTask? {
        for anchor in anchors {
            if let task = MatchPairs.response(for: anchor, in: context, using: &rng) {
                return task
            }
        }
        return nil
    }
}
