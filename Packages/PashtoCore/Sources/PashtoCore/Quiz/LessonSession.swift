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
    /// The pronunciation setting this session was started with.
    ///
    /// Changing `UserSettings.showTransliteration` does not change a session
    /// that is already running. The next session reads the new value.
    /// Missing keys in an older payload decode as `true`, which is the default.
    public let showsPronunciation: Bool
    public private(set) var tasks: [SessionTask]
    public private(set) var answers: [SessionAnswer]

    public init(
        lessonID: LessonID,
        showsPronunciation: Bool = true,
        tasks: [SessionTask],
        answers: [SessionAnswer] = []
    ) {
        self.lessonID = lessonID
        self.showsPronunciation = showsPronunciation
        self.tasks = tasks
        self.answers = answers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lessonID = try container.decode(LessonID.self, forKey: .lessonID)
        showsPronunciation = try container.decodeIfPresent(Bool.self, forKey: .showsPronunciation) ?? true
        tasks = try container.decode([SessionTask].self, forKey: .tasks)
        answers = try container.decodeIfPresent([SessionAnswer].self, forKey: .answers) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lessonID, forKey: .lessonID)
        try container.encode(showsPronunciation, forKey: .showsPronunciation)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(answers, forKey: .answers)
    }

    private enum CodingKeys: String, CodingKey {
        case lessonID
        case showsPronunciation
        case tasks
        case answers
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
            options: shuffledDifferent(task.options, using: &rng),
            promptItemID: task.promptItemID
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
/// The generator order is Pashto to English, English to Pashto, then the
/// pronunciation question when pronunciation is hidden. A letter uses B1 and
/// B2 instead of the old letter choices while pronunciation is shown. B1 and
/// B3 are not built when pronunciation is hidden. B2 is built in both cases,
/// and it is the only letter task when pronunciation is hidden. VoiceOver
/// builds none of the letter tasks, and it does not fall back to the old
/// letter meaning questions while pronunciation is shown. Word order stays
/// out of the session until `OrderWords.includedInSessions` is turned on.
/// Dialog reply and match pairs follow. The placement test draws from this
/// same draft and the same `rng`.
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
/// `releasedUnitIDs` has no default. Pass nil only when the caller really
/// means the whole bundle, such as a dev check. An empty list releases
/// nothing, so a forgotten list cannot quiz unreleased units.
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
        releasedUnitIDs: [UnitID]?,
        showsPronunciation: Bool = true,
        voiceOver: Bool = false,
        using rng: inout some RandomNumberGenerator
    ) -> LessonSession {
        let course: ContentBundle
        if let releasedUnitIDs {
            course = ReleasedCourse.limiting(bundle, to: releasedUnitIDs)
            let listed = Set(releasedUnitIDs)
            let lessonIsReleased = course.units.contains { unit in
                listed.contains(unit.id) && unit.lessons.contains { $0.id == lessonID }
            }
            if !lessonIsReleased {
                return LessonSession(
                    lessonID: lessonID,
                    showsPronunciation: showsPronunciation,
                    tasks: []
                )
            }
        } else {
            course = bundle
        }
        var seen = seenLessonIDs
        if !seen.contains(lessonID) {
            seen.append(lessonID)
        }
        let context = QuizContext(
            bundle: course,
            seenLessonIDs: seen,
            retiredItemIDs: retiredItemIDs
        )
        let policy = QuizPolicy(showsPronunciation: showsPronunciation, voiceOver: voiceOver)
        let targets = Distractors.introducedItems(in: lessonID, bundle: course)
        let draft = Self.draft(for: targets, in: context, policy: policy, using: &rng)
        let groups = draft.perItem.map { ItemTasks(tasks: $0) }
        let tasks = groups.flatMap(\.tasks) + draft.shared
        let cap = maxQuestions.map { max($0, 0) }
        if let cap, cap < tasks.count {
            let selected = select(groups: groups, shared: draft.shared, cap: cap, using: &rng)
            return LessonSession(
                lessonID: lessonID,
                showsPronunciation: showsPronunciation,
                tasks: shuffled(selected, using: &rng)
            )
        }
        return LessonSession(
            lessonID: lessonID,
            showsPronunciation: showsPronunciation,
            tasks: shuffled(tasks, using: &rng)
        )
    }

    static func draft(
        for targets: [ContentItem],
        in context: QuizContext,
        policy: QuizPolicy = .initial,
        using rng: inout some RandomNumberGenerator
    ) -> LessonTaskDraft {
        var perItem: [[SessionTask]] = []
        for target in targets {
            var itemTasks: [SessionTask] = []
            for task in QuizSchedule.choices(for: target, in: context, policy: policy, using: &rng) {
                itemTasks.append(SessionTask(payload: .choice(task)))
            }
            if !policy.voiceOver, target.kind == .letter {
                if policy.showsPronunciation,
                   let task = LetterTasks.findLetter(for: target, in: context, using: &rng) {
                    itemTasks.append(SessionTask(payload: .choice(task)))
                }
                if let task = LetterTasks.contrast(for: target, in: context, using: &rng) {
                    itemTasks.append(SessionTask(payload: .choice(task)))
                }
            }
            if !policy.voiceOver, policy.showsPronunciation, target.kind != .letter {
                if let task = LetterTasks.firstLetter(of: target, in: context, using: &rng) {
                    itemTasks.append(SessionTask(payload: .choice(task)))
                }
            }
            // Word order is paused. Farhad is still deciding the pronunciation
            // under each tile. `OrderWords.includedInSessions` turns it back on.
            if OrderWords.includedInSessions,
               let task = OrderWords.makeTask(for: target, in: context, using: &rng) {
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
            // A first-letter question grades the letter, not the word it shows.
            // The word keeps a question that grades the word when it has one.
            let aboutItem = ordered.filter(gradesTheIntroducedItem)
            let aboutSomethingElse = ordered.filter { !gradesTheIntroducedItem($0) }
            if let first = aboutItem.first {
                selected.append(first)
                repetitions.append(contentsOf: aboutItem.dropFirst())
                repetitions.append(contentsOf: aboutSomethingElse)
            } else if let first = ordered.first {
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

    /// True when the question's grade is for the item the draft built it for.
    ///
    /// A first-letter question is filed under the word, and its grade is the letter.
    private static func gradesTheIntroducedItem(_ task: SessionTask) -> Bool {
        switch task.payload {
        case .choice(let quiz):
            return quiz.kind != .firstLetter
        case .orderWords, .matchPairs:
            return true
        }
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
