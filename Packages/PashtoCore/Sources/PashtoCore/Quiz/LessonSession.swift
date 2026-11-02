/// One question in a lesson, plus whether it was queued again after a miss.
public struct SessionTask: Hashable, Codable, Sendable {
    public enum Payload: Hashable, Codable, Sendable {
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

public struct SessionAnswer: Hashable, Codable, Sendable {
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
/// the queue once, and its options, tiles, or pairs are shuffled again with
/// `rng`. The new order differs from the first unless no other order exists.
/// That repeat is not appended again if it is also wrong.
public struct LessonSession: Hashable, Codable, Sendable {
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
    public mutating func submit(
        _ answer: QuizAnswer,
        using rng: inout some RandomNumberGenerator
    ) -> GradeResult? {
        guard let task = tasks.first else { return nil }
        tasks.removeFirst()
        let result = grade(task, answer)
        answers.append(SessionAnswer(task: task, answer: answer, result: result))
        if result == .incorrect, !task.isRepeat {
            let payload = reshuffled(task.payload, using: &rng)
            tasks.append(SessionTask(payload: payload, isRepeat: true))
        }
        return result
    }
}

private func reshuffled(
    _ payload: SessionTask.Payload,
    using rng: inout some RandomNumberGenerator
) -> SessionTask.Payload {
    switch payload {
    case .choice(let task):
        return .choice(QuizTask(
            kind: task.kind,
            targetID: task.targetID,
            prompt: task.prompt,
            usage: task.usage,
            options: shuffledDifferent(task.options, using: &rng)
        ))
    case .matchPairs(let task):
        return .matchPairs(MatchPairs.reshuffled(task, using: &rng))
    case .orderWords(let task):
        return .orderWords(OrderWords.reshuffled(task, using: &rng))
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

private struct ItemTasks {
    var tasks: [SessionTask]
}

/// One question list per introduced item, then the shared match tasks.
///
/// The generator order is Pashto to English, English to Pashto, pronunciation,
/// word order, and dialog reply. Match pairs come after those. The placement
/// test draws from this same draft and the same `rng`.
struct LessonTaskDraft {
    var perItem: [[SessionTask]]
    var shared: [SessionTask]
}

/// Mixes the quiz kinds for one lesson, using only content the learner has seen.
///
/// The lesson being built counts as seen. An item is seen only when a seen
/// lesson introduces it. A `soundExample` reference does not count, so
/// `l-sounds-1` introduces nothing and its session is empty.
///
/// The same generator and the same seed produce the same session.
///
/// `maxQuestions` caps a lesson session. The default is 20. Nil keeps every
/// question. Review sessions do not use this cap; a review day is limited
/// to 50 cards on its own.
///
/// Every item this lesson introduces keeps one question. The cap does not
/// remove that question, even when the session then runs past the cap. Further
/// questions repeat an item the session already covers, and those
/// repetitions are dropped first when the session is cut. A question asked
/// again after a wrong answer is added after the cut, so the cap leaves it
/// in place.
public enum LessonSessionBuilder {
    /// Questions a lesson session aims for before a wrong answer is asked again.
    public static let defaultMaxQuestions = 20

    public static func build(
        for lessonID: LessonID,
        in bundle: ContentBundle,
        seenLessonIDs: [LessonID],
        retiredItemIDs: [ItemID] = [],
        maxQuestions: Int? = defaultMaxQuestions,
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
        let draft = Self.draft(for: targets, in: context, using: &rng)
        let groups = draft.perItem.map { ItemTasks(tasks: $0) }
        let tasks = groups.flatMap(\.tasks) + draft.shared
        let cap = maxQuestions.map { max($0, 0) }
        if let cap, cap < tasks.count {
            let selected = select(groups: groups, shared: draft.shared, cap: cap, using: &rng)
            return LessonSession(lessonID: lessonID, tasks: shuffled(selected, using: &rng))
        }
        return LessonSession(lessonID: lessonID, tasks: shuffled(tasks, using: &rng))
    }

    static func draft(
        for targets: [ContentItem],
        in context: QuizContext,
        using rng: inout some RandomNumberGenerator
    ) -> LessonTaskDraft {
        var perItem: [[SessionTask]] = []
        for target in targets {
            var itemTasks: [SessionTask] = []
            if let task = PashtoToEnglishChoice().makeTask(for: target, in: context, using: &rng) {
                itemTasks.append(SessionTask(payload: .choice(task)))
            }
            if let task = EnglishToPashtoChoice().makeTask(for: target, in: context, using: &rng) {
                itemTasks.append(SessionTask(payload: .choice(task)))
            }
            if let task = TransliterationChoice().makeTask(for: target, in: context, using: &rng) {
                itemTasks.append(SessionTask(payload: .choice(task)))
            }
            if let task = OrderWords.makeTask(for: target, in: context, using: &rng) {
                itemTasks.append(SessionTask(payload: .orderWords(task)))
            }
            if let task = DialogResponse().makeTask(for: target, in: context, using: &rng) {
                itemTasks.append(SessionTask(payload: .choice(task)))
            }
            if !itemTasks.isEmpty {
                perItem.append(itemTasks)
            }
        }
        var shared: [SessionTask] = []
        if let match = firstPashtoEnglish(in: targets.filter { $0.kind != .letter }, context: context, using: &rng) {
            shared.append(SessionTask(payload: .matchPairs(match)))
        }
        if let match = firstPashtoEnglish(in: targets.filter { $0.kind == .letter }, context: context, using: &rng) {
            shared.append(SessionTask(payload: .matchPairs(match)))
        }
        if let match = firstResponse(in: targets.filter { $0.responseTo != nil }, context: context, using: &rng) {
            shared.append(SessionTask(payload: .matchPairs(match)))
        }
        return LessonTaskDraft(perItem: perItem, shared: shared)
    }

    /// One question for every introduced item, then repetitions until `cap`.
    /// A repetition is another question for an item that already has one,
    /// including a shared match. Item order follows the lesson. The draw uses
    /// Fisher-Yates, so the same seed picks the same questions.
    private static func select(
        groups: [ItemTasks],
        shared: [SessionTask],
        cap: Int,
        using rng: inout some RandomNumberGenerator
    ) -> [SessionTask] {
        var selected: [SessionTask] = []
        var repetitions: [SessionTask] = []
        for group in groups {
            let ordered = shuffled(group.tasks, using: &rng)
            if let first = ordered.first {
                selected.append(first)
                repetitions.append(contentsOf: ordered.dropFirst())
            }
        }
        repetitions.append(contentsOf: shared)
        let room = cap - selected.count
        if room > 0, !repetitions.isEmpty {
            selected.append(contentsOf: shuffled(repetitions, using: &rng).prefix(room))
        }
        return selected
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
