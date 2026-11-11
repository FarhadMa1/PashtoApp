/// Quiz kinds this package can build.
///
/// Meaning and pronunciation questions are multiple choice. Match pairs and
/// word order use their own task values. A dialog reply is multiple choice too.
public enum TaskKind: String, Hashable, Codable, Sendable, CaseIterable {
    /// See the Pashto and choose the English meaning.
    case meaningPashtoToEnglish
    /// See the English meaning and choose the Pashto.
    case meaningEnglishToPashto
    /// See the Pashto and choose the pronunciation.
    ///
    /// Not built for the playable quiz. A visible pronunciation would be the
    /// answer. Saved sessions that still contain one are started over.
    case transliterationChoice
    /// See the letter's English description and choose its glyph.
    ///
    /// The Pashto name and the `sound` field are not the question.
    case findLetter
    /// See one shape hint and choose which of two same-sound letters it is.
    case letterContrast
    /// See a word and choose its first letter. Words that start with آ are skipped.
    case firstLetter
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

public struct QuizOption: Hashable, Codable, Sendable {
    public let itemID: ItemID
    public let text: String

    public init(itemID: ItemID, text: String) {
        self.itemID = itemID
        self.text = text
    }
}

/// One multiple-choice question. `options` contains the correct item exactly once.
public struct QuizTask: Hashable, Codable, Sendable {
    public let kind: TaskKind
    public let targetID: ItemID
    public let prompt: String
    /// Target `usage` when it is non-blank, so the app can show it with the prompt.
    public let usage: String?
    public let options: [QuizOption]
    /// The item whose Pashto is the prompt, when that item is not `targetID`.
    ///
    /// A first-letter question's target is the letter. This is the word.
    public let promptItemID: ItemID?

    public init(
        kind: TaskKind,
        targetID: ItemID,
        prompt: String,
        usage: String?,
        options: [QuizOption],
        promptItemID: ItemID? = nil
    ) {
        self.kind = kind
        self.targetID = targetID
        self.prompt = prompt
        self.usage = usage
        self.options = options
        self.promptItemID = promptItemID
    }
}

public enum QuizAnswer: Hashable, Codable, Sendable {
    case choice(ItemID)
    /// One link per left-hand card. The array order does not matter.
    case matches([MatchLink])
    /// Original token indexes in logical order. Index 0 is the rightmost tile.
    case tokenOrder([Int])
}

public enum GradeResult: Hashable, Codable, Sendable {
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
/// `seenLessonIDs`. Questions are returned in lesson order. For each item the
/// order is Pashto to English, then English to Pashto. A pronunciation
/// choice is not built: the pronunciation is always on screen, so it would
/// be the answer. A letter does not get the meaning questions while
/// pronunciation is on screen, because the pronunciation under the letter
/// would be the answer. Letter tasks B1–B3 are built by `LessonSessionBuilder`
/// only when the lesson still introduces letters. A kind that cannot reach
/// three options is skipped. The generator returns nothing when the lesson
/// introduces no items.
public enum MultipleChoiceQuiz {
    public static func questions(
        for lessonID: LessonID,
        in bundle: ContentBundle,
        seenLessonIDs: [LessonID],
        retiredItemIDs: [ItemID] = [],
        showsPronunciation: Bool = true,
        voiceOver: Bool = false,
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
        let policy = QuizPolicy(showsPronunciation: showsPronunciation, voiceOver: voiceOver)
        let targets = Distractors.introducedItems(in: lessonID, bundle: bundle)
        var tasks: [QuizTask] = []
        for target in targets {
            tasks.append(contentsOf: QuizSchedule.choices(for: target, in: context, policy: policy, using: &rng))
        }
        return tasks
    }
}

/// Whether this session shows pronunciation, and whether VoiceOver was on when it was built.
struct QuizPolicy: Hashable, Sendable {
    var showsPronunciation: Bool
    var voiceOver: Bool

    static let initial = QuizPolicy(showsPronunciation: true, voiceOver: false)
}

/// The choice questions one item contributes.
///
/// Meaning questions are always available, except for a letter while
/// pronunciation is on screen. Those old letter questions name the letter
/// ("the letter ta"), so VoiceOver does not bring them back. A pronunciation
/// choice is not built. The stored preference does not bring it back.
enum QuizSchedule {
    static func choices(
        for target: ContentItem,
        in context: QuizContext,
        policy: QuizPolicy,
        using rng: inout some RandomNumberGenerator
    ) -> [QuizTask] {
        if target.kind == .letter, policy.showsPronunciation {
            return []
        }
        var tasks: [QuizTask] = []
        if let task = PashtoToEnglishChoice().makeTask(for: target, in: context, using: &rng) {
            tasks.append(task)
        }
        if let task = EnglishToPashtoChoice().makeTask(for: target, in: context, using: &rng) {
            tasks.append(task)
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

        let courseOrder = CourseOrder(context.bundle)
        let shapeSplit: Bool
        if let introduction = courseOrder.introduction(of: target.id) {
            shapeSplit = answerShapesAreSplit(introduction.unitID, releasedUnitIDs: context.releasedUnitIDs)
        } else {
            shapeSplit = false
        }
        // A word or phrase in a released unit after Greetings needs three wrong
        // answers of that shape. Greetings, Basics, and a unit that is not in
        // the release list still accept two.
        let minimumDistractors = shapeSplit ? 3 : 2

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
                if YouAreForms.clash(picked.item.id, target.id) { continue }
                if distractors.contains(where: { YouAreForms.clash(picked.item.id, $0.itemID) }) { continue }
                seenKeys.append(key)
                distractors.append(QuizOption(itemID: picked.item.id, text: picked.text))
            }
        }
        // Units after Greetings skip the question when fewer than three
        // same-shape wrong answers remain after earlier released units are
        // included. Greetings is not skipped for shape. `u-basics` never
        // fills another unit.
        guard distractors.count >= minimumDistractors else { return nil }

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
    case .findLetter, .letterContrast, .firstLetter, .matchPairs, .orderWords, .dialogResponse:
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
    case .findLetter, .letterContrast, .firstLetter, .matchPairs, .orderWords, .dialogResponse:
        return nil
    }
}

private func answerKey(for kind: TaskKind, text: String) -> String {
    switch kind {
    case .meaningPashtoToEnglish, .transliterationChoice:
        return Normalization.comparisonKey(text)
    case .meaningEnglishToPashto:
        return Normalization.nfc(text)
    case .findLetter, .letterContrast, .firstLetter, .matchPairs, .orderWords, .dialogResponse:
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
