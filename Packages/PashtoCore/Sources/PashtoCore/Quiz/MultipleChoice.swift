/// Quiz kinds this package can build.
///
/// Meaning and pronunciation questions are multiple choice. Match pairs and
/// word order use their own task values. A dialog reply is multiple choice too.
public enum TaskKind: String, Hashable, Sendable, CaseIterable {
    /// See the Pashto and choose the English meaning.
    case meaningPashtoToEnglish
    /// See the English meaning and choose the Pashto.
    case meaningEnglishToPashto
    /// See the Pashto and choose the pronunciation. Letter items use this too.
    case transliterationChoice
    /// Match 3 or 4 Pashto/English pairs, or greeting/reply pairs.
    case matchPairs
    /// Put word tiles in logical order. The sentence is read right to left.
    case orderWords
    /// Read one line and choose the reply.
    case dialogResponse
}

public protocol TaskGenerator: Sendable {
    var kind: TaskKind { get }
    func makeTask(
        for target: ContentItem,
        in context: QuizContext,
        using rng: inout some RandomNumberGenerator
    ) -> QuizTask?
}

public struct QuizOption: Hashable, Sendable {
    public let itemID: ItemID
    public let text: String

    public init(itemID: ItemID, text: String) {
        self.itemID = itemID
        self.text = text
    }
}

/// One multiple-choice question. `options` contains the correct item exactly once.
public struct QuizTask: Hashable, Sendable {
    public let kind: TaskKind
    public let targetID: ItemID
    public let prompt: String
    /// Target `usage` when it is non-blank, so the app can show it with the prompt.
    public let usage: String?
    public let options: [QuizOption]

    public init(
        kind: TaskKind,
        targetID: ItemID,
        prompt: String,
        usage: String?,
        options: [QuizOption]
    ) {
        self.kind = kind
        self.targetID = targetID
        self.prompt = prompt
        self.usage = usage
        self.options = options
    }
}

public enum QuizAnswer: Hashable, Sendable {
    case choice(ItemID)
    /// One link per left-hand card. The array order does not matter.
    case matches([MatchLink])
    /// Original token indexes in logical order. Index 0 is the rightmost tile.
    case tokenOrder([Int])
}

public enum GradeResult: Hashable, Sendable {
    case correct
    case incorrect
}

public func grade(_ task: QuizTask, _ answer: QuizAnswer) -> GradeResult {
    switch answer {
    case .choice(let itemID):
        return itemID == task.targetID ? .correct : .incorrect
    case .matches, .tokenOrder:
        return .incorrect
    }
}

public struct PashtoToEnglishChoice: TaskGenerator {
    public var kind: TaskKind { .meaningPashtoToEnglish }

    public init() {}

    public func makeTask(
        for target: ContentItem,
        in context: QuizContext,
        using rng: inout some RandomNumberGenerator
    ) -> QuizTask? {
        ChoiceBuilder.make(.meaningPashtoToEnglish, target: target, in: context, using: &rng)
    }
}

public struct EnglishToPashtoChoice: TaskGenerator {
    public var kind: TaskKind { .meaningEnglishToPashto }

    public init() {}

    public func makeTask(
        for target: ContentItem,
        in context: QuizContext,
        using rng: inout some RandomNumberGenerator
    ) -> QuizTask? {
        ChoiceBuilder.make(.meaningEnglishToPashto, target: target, in: context, using: &rng)
    }
}

public struct TransliterationChoice: TaskGenerator {
    public var kind: TaskKind { .transliterationChoice }

    public init() {}

    public func makeTask(
        for target: ContentItem,
        in context: QuizContext,
        using rng: inout some RandomNumberGenerator
    ) -> QuizTask? {
        ChoiceBuilder.make(.transliterationChoice, target: target, in: context, using: &rng)
    }
}

/// Multiple-choice questions for one lesson.
///
/// The lesson's own introduced items are treated as seen, together with
/// `seenLessonIDs`. Questions are returned in lesson order, and for each item
/// in the order Pashto to English, English to Pashto, then pronunciation.
/// A kind that cannot reach three options is skipped. The generator returns
/// nothing when the lesson introduces no items.
public enum MultipleChoiceQuiz {
    public static func questions(
        for lessonID: LessonID,
        in bundle: ContentBundle,
        seenLessonIDs: [LessonID],
        retiredItemIDs: [ItemID] = [],
        using rng: inout some RandomNumberGenerator
    ) -> [QuizTask] {
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
        var tasks: [QuizTask] = []
        for target in targets {
            if let task = PashtoToEnglishChoice().makeTask(for: target, in: context, using: &rng) {
                tasks.append(task)
            }
            if let task = EnglishToPashtoChoice().makeTask(for: target, in: context, using: &rng) {
                tasks.append(task)
            }
            if let task = TransliterationChoice().makeTask(for: target, in: context, using: &rng) {
                tasks.append(task)
            }
        }
        return tasks
    }
}

/// At least three options, at most four. The correct item is one of them.
///
/// Each source level is drawn at random with `rng`. The same lesson is used
/// first. Earlier lessons in the unit are used only when that level runs out,
/// and earlier units only after that. The same generator then shuffles the
/// options, so the correct answer is not stuck in one slot.
enum ChoiceBuilder {
    static func make(
        _ kind: TaskKind,
        target: ContentItem,
        in context: QuizContext,
        using rng: inout some RandomNumberGenerator
    ) -> QuizTask? {
        let courseItems = itemsByID(context.bundle)
        guard let target = courseItems[target.id] else { return nil }
        guard let prompt = prompt(for: kind, item: target) else { return nil }
        guard let correctText = answer(for: kind, item: target) else { return nil }

        let ranked = Distractors.candidates(for: target, in: context)
        var distractors: [QuizOption] = []
        var seenKeys = [answerKey(for: kind, text: correctText)]
        let levels: [DistractorSource] = [.sameLesson, .earlierLessonInUnit, .earlierUnit]
        for level in levels where distractors.count < 3 {
            var pool: [(item: ContentItem, text: String)] = []
            for candidate in ranked where candidate.source == level {
                guard let item = courseItems[candidate.itemID] else { continue }
                guard let text = answer(for: kind, item: item) else { continue }
                let key = answerKey(for: kind, text: text)
                guard !seenKeys.contains(key) else { continue }
                pool.append((item, text))
            }
            while distractors.count < 3, !pool.isEmpty {
                let index = Int(rng.next() % UInt64(pool.count))
                let picked = pool.remove(at: index)
                let key = answerKey(for: kind, text: picked.text)
                guard !seenKeys.contains(key) else { continue }
                seenKeys.append(key)
                distractors.append(QuizOption(itemID: picked.item.id, text: picked.text))
            }
        }
        // 0, 1, or 2 eligible items of this pool: fewer than two distractors.
        guard distractors.count >= 2 else { return nil }

        var options = [QuizOption(itemID: target.id, text: correctText)]
        options.append(contentsOf: distractors)
        options = shuffled(options, using: &rng)
        return QuizTask(
            kind: kind,
            targetID: target.id,
            prompt: prompt,
            usage: blankToNil(target.usage),
            options: options
        )
    }
}

private func prompt(for kind: TaskKind, item: ContentItem) -> String? {
    switch kind {
    case .meaningPashtoToEnglish, .transliterationChoice:
        return blankToNil(item.pashto)
    case .meaningEnglishToPashto:
        return blankToNil(item.en)
    case .matchPairs, .orderWords, .dialogResponse:
        return nil
    }
}

private func answer(for kind: TaskKind, item: ContentItem) -> String? {
    switch kind {
    case .meaningPashtoToEnglish:
        return blankToNil(item.en)
    case .meaningEnglishToPashto:
        return blankToNil(item.pashto)
    case .transliterationChoice:
        return blankToNil(item.pronunciation)
    case .matchPairs, .orderWords, .dialogResponse:
        return nil
    }
}

private func answerKey(for kind: TaskKind, text: String) -> String {
    switch kind {
    case .meaningPashtoToEnglish, .transliterationChoice:
        return Normalization.comparisonKey(text)
    case .meaningEnglishToPashto:
        return Normalization.nfc(text)
    case .matchPairs, .orderWords, .dialogResponse:
        return Normalization.comparisonKey(text)
    }
}

func blankToNil(_ text: String?) -> String? {
    guard let text, !Text.isBlank(text) else { return nil }
    return text
}

private func itemsByID(_ bundle: ContentBundle) -> [ItemID: ContentItem] {
    var map: [ItemID: ContentItem] = [:]
    for item in bundle.items where map[item.id] == nil {
        map[item.id] = item
    }
    return map
}
