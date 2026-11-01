public enum MatchMode: String, Hashable, Sendable {
    /// Pashto on the left, English on the right. Both sides are one item.
    case pashtoEnglish
    /// The line on the left, the item whose `responseTo` points at it on the right.
    case response
}

public struct MatchSide: Hashable, Sendable {
    public let itemID: ItemID
    public let text: String

    public init(itemID: ItemID, text: String) {
        self.itemID = itemID
        self.text = text
    }
}

public struct MatchPair: Hashable, Sendable {
    public let left: MatchSide
    public let right: MatchSide

    public init(left: MatchSide, right: MatchSide) {
        self.left = left
        self.right = right
    }
}

/// One link from a left-hand card to the right-hand card the learner chose.
public struct MatchLink: Hashable, Sendable {
    public let left: ItemID
    public let right: ItemID

    public init(left: ItemID, right: ItemID) {
        self.left = left
        self.right = right
    }
}

/// Three or four pairs. `pairs` is the left column.
///
/// `rightOrder` indexes `pairs` and is the right column. With two or more pairs
/// it is not `0, 1, 2, ...`, so the columns are not already matched.
public struct MatchPairsTask: Hashable, Sendable {
    public let mode: MatchMode
    public let pairs: [MatchPair]
    public let rightOrder: [Int]

    public init(mode: MatchMode, pairs: [MatchPair], rightOrder: [Int]) {
        self.mode = mode
        self.pairs = pairs
        self.rightOrder = rightOrder
    }

    public var rightColumn: [MatchSide] {
        rightOrder.map { pairs[$0].right }
    }
}

public enum MatchPairs {
    /// Nil when fewer than 3 seen items of this pool can stand in one task.
    ///
    /// The target is included. Other items are drawn at random inside each
    /// source level: this lesson, then earlier lessons in the unit, then
    /// earlier units. At most 4 pairs.
    ///
    /// No two chosen items share Pashto, pronunciation, or an English meaning
    /// (`en` or `enAlt`). Letters are only matched with letters.
    public static func pashtoEnglish(
        for target: ContentItem,
        in context: QuizContext,
        using rng: inout some RandomNumberGenerator
    ) -> MatchPairsTask? {
        let course = CourseOrder(context.bundle)
        guard let anchor = course.itemsByID[target.id] else { return nil }
        guard isQuizSeen(anchor.id, in: context, course: course) else { return nil }
        guard let anchorIntro = course.introduction(of: anchor.id) else { return nil }
        guard blankToNil(anchor.pashto) != nil, blankToNil(anchor.en) != nil else { return nil }

        var candidates: [ContentItem] = []
        for introduction in course.introductions where introduction.itemID != anchor.id {
            guard let item = course.itemsByID[introduction.itemID] else { continue }
            guard sameQuizPool(item.kind, anchor.kind) else { continue }
            guard isQuizSeen(item.id, in: context, course: course) else { continue }
            guard blankToNil(item.pashto) != nil, blankToNil(item.en) != nil else { continue }
            guard distractorSource(of: introduction, target: anchorIntro) != nil else { continue }
            candidates.append(item)
        }
        guard candidates.count + 1 >= 3 else { return nil }

        var chosen = [anchor]
        let grouped = buckets(candidates, anchor: anchorIntro, course: course)
        draw(
            from: [grouped.sameLesson, grouped.earlierLesson, grouped.earlierUnit],
            into: &chosen,
            limit: 4,
            accepts: { item, chosen in
                chosen.allSatisfy { !formsConflict(item, $0) }
            },
            using: &rng
        )
        guard chosen.count >= 3 else { return nil }

        let pairs = chosen.compactMap { item -> MatchPair? in
            guard let left = blankToNil(item.pashto), let right = blankToNil(item.en) else { return nil }
            return MatchPair(
                left: MatchSide(itemID: item.id, text: left),
                right: MatchSide(itemID: item.id, text: right)
            )
        }
        guard pairs.count == chosen.count else { return nil }
        return assemble(.pashtoEnglish, pairs: pairs, using: &rng)
    }

    /// Nil when fewer than 3 greeting/reply pairs can stand in one task.
    ///
    /// `target` is the reply (`responseTo` is set). Both sides of every pair
    /// are seen. Pashto on either side, pronunciation, and English meanings
    /// are unique across the whole task.
    public static func response(
        for target: ContentItem,
        in context: QuizContext,
        using rng: inout some RandomNumberGenerator
    ) -> MatchPairsTask? {
        let course = CourseOrder(context.bundle)
        guard let anchorReply = course.itemsByID[target.id] else { return nil }
        let pool = responsePairs(in: context, course: course)
        guard let anchor = pool.first(where: { $0.reply.id == anchorReply.id }) else { return nil }
        let others = pool.filter { $0.reply.id != anchor.reply.id }
        guard others.count + 1 >= 3 else { return nil }

        var chosen = [anchor]
        let grouped = buckets(others, anchor: anchor.introduction)
        draw(
            from: [grouped.sameLesson, grouped.earlierLesson, grouped.earlierUnit],
            into: &chosen,
            limit: 4,
            accepts: { pair, chosen in
                let used = chosen.flatMap { [$0.prompt, $0.reply] }
                let sides = [pair.prompt, pair.reply]
                for side in sides {
                    for existing in used where formsConflict(side, existing) {
                        return false
                    }
                }
                return true
            },
            using: &rng
        )
        guard chosen.count >= 3 else { return nil }

        let pairs = chosen.map { pair in
            MatchPair(
                left: MatchSide(itemID: pair.prompt.id, text: pair.prompt.pashto),
                right: MatchSide(itemID: pair.reply.id, text: pair.reply.pashto)
            )
        }
        return assemble(.response, pairs: pairs, using: &rng)
    }

    /// Shuffles both columns again. The right column stays unmatched.
    /// The same task comes back only when two identical pairs have no other layout.
    static func reshuffled(
        _ task: MatchPairsTask,
        using rng: inout some RandomNumberGenerator
    ) -> MatchPairsTask {
        guard pairsCanChange(task) else { return task }
        var next = assemble(task.mode, pairs: task.pairs, using: &rng)
        while next == task {
            next = assemble(task.mode, pairs: task.pairs, using: &rng)
        }
        return next
    }
}

public func grade(_ task: MatchPairsTask, _ answer: QuizAnswer) -> GradeResult {
    guard case .matches(let links) = answer else { return .incorrect }
    guard links.count == task.pairs.count else { return .incorrect }
    for pair in task.pairs {
        let hits = links.filter { $0.left == pair.left.itemID && $0.right == pair.right.itemID }
        if hits.count != 1 { return .incorrect }
    }
    return .correct
}

private struct ResponsePair {
    var prompt: ContentItem
    var reply: ContentItem
    var introduction: Introduction
}

private func responsePairs(in context: QuizContext, course: CourseOrder) -> [ResponsePair] {
    var pairs: [ResponsePair] = []
    for introduction in course.introductions {
        guard let reply = course.itemsByID[introduction.itemID] else { continue }
        guard reply.kind != .letter else { continue }
        guard let promptID = reply.responseTo, promptID != reply.id else { continue }
        guard let prompt = course.itemsByID[promptID] else { continue }
        guard prompt.kind != .letter else { continue }
        guard sameQuizPool(reply.kind, prompt.kind) else { continue }
        guard isQuizSeen(reply.id, in: context, course: course) else { continue }
        guard isQuizSeen(prompt.id, in: context, course: course) else { continue }
        guard blankToNil(reply.pashto) != nil, blankToNil(prompt.pashto) != nil else { continue }
        if formsConflict(reply, prompt) { continue }
        pairs.append(ResponsePair(prompt: prompt, reply: reply, introduction: introduction))
    }
    return pairs
}

private struct SourceBuckets<T> {
    var sameLesson: [T]
    var earlierLesson: [T]
    var earlierUnit: [T]
}

private func buckets(
    _ items: [ContentItem],
    anchor: Introduction,
    course: CourseOrder
) -> SourceBuckets<ContentItem> {
    var grouped = SourceBuckets<ContentItem>(sameLesson: [], earlierLesson: [], earlierUnit: [])
    for item in items {
        guard let introduction = course.introduction(of: item.id) else { continue }
        switch distractorSource(of: introduction, target: anchor) {
        case .sameLesson:
            grouped.sameLesson.append(item)
        case .earlierLessonInUnit:
            grouped.earlierLesson.append(item)
        case .earlierUnit:
            grouped.earlierUnit.append(item)
        case nil:
            break
        }
    }
    return grouped
}

private func buckets(
    _ pairs: [ResponsePair],
    anchor: Introduction
) -> SourceBuckets<ResponsePair> {
    var grouped = SourceBuckets<ResponsePair>(sameLesson: [], earlierLesson: [], earlierUnit: [])
    for pair in pairs {
        switch distractorSource(of: pair.introduction, target: anchor) {
        case .sameLesson:
            grouped.sameLesson.append(pair)
        case .earlierLessonInUnit:
            grouped.earlierLesson.append(pair)
        case .earlierUnit:
            grouped.earlierUnit.append(pair)
        case nil:
            break
        }
    }
    return grouped
}

private func draw<T>(
    from levels: [[T]],
    into chosen: inout [T],
    limit: Int,
    accepts: (T, [T]) -> Bool,
    using rng: inout some RandomNumberGenerator
) {
    for level in levels where chosen.count < limit {
        var pool = level.filter { accepts($0, chosen) }
        while chosen.count < limit, !pool.isEmpty {
            let index = Int(rng.next() % UInt64(pool.count))
            let picked = pool.remove(at: index)
            guard accepts(picked, chosen) else { continue }
            chosen.append(picked)
        }
    }
}

private func formsConflict(_ lhs: ContentItem, _ rhs: ContentItem) -> Bool {
    if lhs.id == rhs.id { return true }
    if Normalization.nfc(lhs.pashto) == Normalization.nfc(rhs.pashto) { return true }
    if Normalization.comparisonKey(lhs.pronunciation) == Normalization.comparisonKey(rhs.pronunciation) {
        return true
    }
    if meaningsOverlap(lhs, rhs) { return true }
    return false
}

private func assemble(
    _ mode: MatchMode,
    pairs: [MatchPair],
    using rng: inout some RandomNumberGenerator
) -> MatchPairsTask {
    let left = shuffled(pairs, using: &rng)
    return MatchPairsTask(mode: mode, pairs: left, rightOrder: misaligned(count: left.count, using: &rng))
}

private func misaligned(count: Int, using rng: inout some RandomNumberGenerator) -> [Int] {
    let identity = Array(0..<count)
    guard count > 1 else { return identity }
    return shuffledUntil(identity, using: &rng) { $0 != identity } ?? identity
}

private func pairsCanChange(_ task: MatchPairsTask) -> Bool {
    let count = task.pairs.count
    guard count > 1 else { return false }
    if count > 2 { return true }
    for pair in task.pairs.dropFirst() where pair != task.pairs[0] {
        return true
    }
    return false
}
