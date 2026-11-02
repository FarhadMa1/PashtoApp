/// Whether a dialog option is a phrase or a single word.
///
/// A phrase is an item with `kind: phrase`, or Pashto text of more than one
/// word. Words are split on whitespace only. A comma stays on its word, and
/// ZWNJ (U+200C) does not split a word. A one-word `kind: phrase`, such as
/// سلام, is a phrase. Anything else is a word. Approved by Farhad 2026-11-02.
public enum DialogReplyShape: Hashable, Sendable {
    case phrase
    case word
}

/// Why a dialog reply is not asked, before the distractor count is considered.
///
/// `sharedUsage` is its own case so a release check does not describe it as
/// too few wrong options. `unavailable` covers a letter, a blank line, a
/// missing prompt, or an item the learner has not seen.
public enum DialogReplySkip: Hashable, Sendable {
    case sharedUsage
    case unavailable
}

/// Choose the reply to one line.
///
/// The prompt is the Pashto of the line named by `responseTo`. The correct
/// option is this item. `usage` is shown when it is non-blank, which is how
/// two replies to the same line stay distinct.
///
/// Distractors use the same seen-content rules as the other choice questions,
/// then a tighter shape rule: a phrase answer takes only phrase distractors,
/// and a word answer takes only word distractors. See `DialogReplyShape`.
/// Text that ends in the Arabic question mark (U+061F) is never a wrong option.
/// The prompt line, anything in the same nonDistractorGroup as the prompt or
/// the correct answer, and any other item whose `responseTo` points at that
/// prompt are never wrong options. Further replies come only from those groups
/// in the content. Nil when two seen replies to the line share a usage, or
/// when fewer than three distractors exist.
public struct DialogResponse: TaskGenerator {
    /// Wrong options a dialog reply must have before the question is asked.
    public static let minimumDistractors = 3

    public var kind: TaskKind { .dialogResponse }

    public init() {}

    /// Phrase or word, using `DialogReplyShape`.
    public static func replyShape(of item: ContentItem) -> DialogReplyShape {
        if item.kind == .phrase || pashtoWordCount(item.pashto) > 1 {
            return .phrase
        }
        return .word
    }

    /// Wrong options for this reply, nearest lesson first.
    ///
    /// Empty when `skipReason` is non-nil, and when the reply is askable but
    /// nothing legal remains. The lesson quiz and the release gate both use
    /// this list, so the count does not depend on the random draw.
    public static func eligibleDistractors(for reply: ContentItem, in context: QuizContext) -> [ContentItem] {
        guard let prepared = prepare(reply, in: context), prepared.skip == nil else { return [] }
        return prepared.distractors
    }

    /// Nil when the reply can be asked. The distractor count is separate:
    /// call `eligibleDistractors` for that.
    public static func skipReason(for reply: ContentItem, in context: QuizContext) -> DialogReplySkip? {
        guard let prepared = prepare(reply, in: context) else { return .unavailable }
        return prepared.skip
    }

    public func makeTask(
        for target: ContentItem,
        in context: QuizContext,
        using rng: inout some RandomNumberGenerator
    ) -> QuizTask? {
        guard let prepared = prepare(target, in: context), prepared.skip == nil else { return nil }
        let distractors = chooseDistractors(
            from: prepared.distractors,
            reply: prepared.reply,
            bundle: context.bundle,
            using: &rng
        )
        guard distractors.count >= Self.minimumDistractors else { return nil }

        var options = [QuizOption(itemID: prepared.reply.id, text: prepared.replyText)]
        options.append(contentsOf: distractors)
        options = shuffled(options, using: &rng)
        return QuizTask(
            kind: .dialogResponse,
            targetID: prepared.reply.id,
            prompt: prepared.promptText,
            usage: blankToNil(prepared.reply.usage),
            options: options
        )
    }
}

private struct PreparedReply {
    var reply: ContentItem
    var replyText: String
    var promptText: String
    var distractors: [ContentItem]
    var skip: DialogReplySkip?
}

private func prepare(_ target: ContentItem, in context: QuizContext) -> PreparedReply? {
    let course = CourseOrder(context.bundle)
    guard let reply = course.itemsByID[target.id] else { return nil }
    guard reply.kind != .letter else { return nil }
    guard let promptID = reply.responseTo, promptID != reply.id else { return nil }
    guard let prompt = course.itemsByID[promptID] else { return nil }
    guard let promptText = blankToNil(prompt.pashto) else { return nil }
    guard let replyText = blankToNil(reply.pashto) else { return nil }
    guard isQuizSeen(reply.id, in: context, course: course) else { return nil }
    guard isQuizSeen(prompt.id, in: context, course: course) else { return nil }

    let usageKey = Normalization.comparisonKey(reply.usage ?? "")
    var siblings: [ContentItem] = []
    for introduction in course.introductions {
        guard let item = course.itemsByID[introduction.itemID] else { continue }
        guard item.responseTo == prompt.id else { continue }
        guard isQuizSeen(item.id, in: context, course: course) else { continue }
        siblings.append(item)
    }
    let sameUsage = siblings.filter { Normalization.comparisonKey($0.usage ?? "") == usageKey }
    if sameUsage.count != 1 || sameUsage[0].id != reply.id {
        return PreparedReply(
            reply: reply,
            replyText: replyText,
            promptText: promptText,
            distractors: [],
            skip: .sharedUsage
        )
    }

    let shape = DialogResponse.replyShape(of: reply)
    let ranked = Distractors.candidates(for: reply, in: context)
    let groups = context.bundle.nonDistractorGroups
    var distractors: [ContentItem] = []
    var seenKeys = [Normalization.nfc(replyText)]
    for candidate in ranked {
        guard candidate.itemID != prompt.id, candidate.itemID != reply.id else { continue }
        guard let item = course.itemsByID[candidate.itemID] else { continue }
        guard item.responseTo != prompt.id else { continue }
        guard !sharesGroup(item.id, prompt.id, groups) else { continue }
        guard !sharesGroup(item.id, reply.id, groups) else { continue }
        guard DialogResponse.replyShape(of: item) == shape else { continue }
        guard let text = blankToNil(item.pashto) else { continue }
        guard !endsWithArabicQuestion(text) else { continue }
        let key = Normalization.nfc(text)
        guard !seenKeys.contains(key) else { continue }
        seenKeys.append(key)
        distractors.append(item)
    }
    return PreparedReply(
        reply: reply,
        replyText: replyText,
        promptText: promptText,
        distractors: distractors,
        skip: nil
    )
}

/// Nearest level first. Within a level the draw is random, and the next level
/// is used only after that level's legal options run out.
private func chooseDistractors(
    from pool: [ContentItem],
    reply: ContentItem,
    bundle: ContentBundle,
    using rng: inout some RandomNumberGenerator
) -> [QuizOption] {
    let course = CourseOrder(bundle)
    guard let replyIntro = course.introduction(of: reply.id) else { return [] }
    var chosen: [QuizOption] = []
    var seenKeys = [Normalization.nfc(reply.pashto)]
    let levels: [DistractorSource] = [.sameLesson, .earlierLessonInUnit, .earlierUnit]
    for level in levels where chosen.count < DialogResponse.minimumDistractors {
        var levelPool: [(item: ContentItem, text: String)] = []
        for item in pool {
            guard let introduction = course.introduction(of: item.id) else { continue }
            guard distractorSource(of: introduction, target: replyIntro) == level else { continue }
            guard let text = blankToNil(item.pashto) else { continue }
            let key = Normalization.nfc(text)
            guard !seenKeys.contains(key) else { continue }
            levelPool.append((item, text))
        }
        while chosen.count < DialogResponse.minimumDistractors, !levelPool.isEmpty {
            let index = Int(rng.next() % UInt64(levelPool.count))
            let picked = levelPool.remove(at: index)
            let key = Normalization.nfc(picked.text)
            guard !seenKeys.contains(key) else { continue }
            seenKeys.append(key)
            chosen.append(QuizOption(itemID: picked.item.id, text: picked.text))
        }
    }
    return chosen
}

private func pashtoWordCount(_ text: String) -> Int {
    text.split(whereSeparator: \.isWhitespace).count
}

private func endsWithArabicQuestion(_ text: String) -> Bool {
    let trimmed = text.unicodeScalars.reversed().drop { Character($0).isWhitespace }
    guard let last = trimmed.first else { return false }
    return last == PashtoScript.arabicQuestion
}
