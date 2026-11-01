/// Choose the reply to one line.
///
/// The prompt is the Pashto of the line named by `responseTo`. The correct
/// option is this item. `usage` is shown when it is non-blank, which is how
/// two replies to the same line stay distinct.
///
/// Distractors use the same seen-content and same-kind rules as the other
/// choice questions. The prompt line, anything in the same nonDistractorGroup
/// as the prompt or the correct answer, and any other item whose `responseTo`
/// points at that prompt are never wrong options. Further replies come only
/// from those groups in the content. Nil when two seen replies to the line
/// share a usage, or when fewer than two distractors exist.
public struct DialogResponse: TaskGenerator {
    public var kind: TaskKind { .dialogResponse }

    public init() {}

    public func makeTask(
        for target: ContentItem,
        in context: QuizContext,
        using rng: inout some RandomNumberGenerator
    ) -> QuizTask? {
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
        guard sameUsage.count == 1, sameUsage[0].id == reply.id else { return nil }

        let ranked = Distractors.candidates(for: reply, in: context)
        let groups = context.bundle.nonDistractorGroups
        var distractors: [QuizOption] = []
        var seenKeys = [Normalization.nfc(replyText)]
        let levels: [DistractorSource] = [.sameLesson, .earlierLessonInUnit, .earlierUnit]
        for level in levels where distractors.count < 3 {
            var pool: [(item: ContentItem, text: String)] = []
            for candidate in ranked where candidate.source == level {
                guard candidate.itemID != prompt.id, candidate.itemID != reply.id else { continue }
                guard let item = course.itemsByID[candidate.itemID] else { continue }
                guard item.responseTo != prompt.id else { continue }
                guard !sharesGroup(item.id, prompt.id, groups) else { continue }
                guard !sharesGroup(item.id, reply.id, groups) else { continue }
                guard let text = blankToNil(item.pashto) else { continue }
                let key = Normalization.nfc(text)
                guard !seenKeys.contains(key) else { continue }
                pool.append((item, text))
            }
            while distractors.count < 3, !pool.isEmpty {
                let index = Int(rng.next() % UInt64(pool.count))
                let picked = pool.remove(at: index)
                let key = Normalization.nfc(picked.text)
                guard !seenKeys.contains(key) else { continue }
                seenKeys.append(key)
                distractors.append(QuizOption(itemID: picked.item.id, text: picked.text))
            }
        }
        guard distractors.count >= 2 else { return nil }

        var options = [QuizOption(itemID: reply.id, text: replyText)]
        options.append(contentsOf: distractors)
        options = shuffled(options, using: &rng)
        return QuizTask(
            kind: .dialogResponse,
            targetID: reply.id,
            prompt: promptText,
            usage: blankToNil(reply.usage),
            options: options
        )
    }
}
