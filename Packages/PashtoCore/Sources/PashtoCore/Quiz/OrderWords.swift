/// One tile in a word-order question.
///
/// `index` is the tile's place in `OrderWordsTask.tokens`. Logical order is
/// right to left, so index 0 is the rightmost tile.
public struct WordTile: Hashable, Codable, Sendable {
    public let index: Int
    public let text: String
    /// Pronunciation under this tile. Nil when the item has none stored.
    public let pronunciation: String?

    public init(index: Int, text: String, pronunciation: String? = nil) {
        self.index = index
        self.text = text
        self.pronunciation = pronunciation
    }
}

/// Put the tiles in order. `؟` and `،` stay in `fixedEnding` and are not tiles.
///
/// `acceptedOrders == nil` means only the `tokens` order is correct. A nil and
/// an empty list behave the same way: no extra order is accepted.
///
/// Grading compares token text position by position, so two identical tokens
/// may swap. The presented `tiles` are never themselves a correct order when
/// the task exists.
public struct OrderWordsTask: Hashable, Codable, Sendable {
    public let targetID: ItemID
    public let tiles: [WordTile]
    public let fixedEnding: String
    public let tokens: [String]
    public let acceptedOrders: [[Int]]?

    public init(
        targetID: ItemID,
        tiles: [WordTile],
        fixedEnding: String,
        tokens: [String],
        acceptedOrders: [[Int]]?
    ) {
        self.targetID = targetID
        self.tiles = tiles
        self.fixedEnding = fixedEnding
        self.tokens = tokens
        self.acceptedOrders = acceptedOrders
    }
}

public enum OrderWords {
    /// Word order is in the lesson session. Each tile carries its pronunciation.
    public static let includedInSessions = true

    /// Nil when the item is unseen, has fewer than 2 usable tokens, or every
    /// arrangement is already correct.
    public static func makeTask(
        for target: ContentItem,
        in context: QuizContext,
        using rng: inout some RandomNumberGenerator
    ) -> OrderWordsTask? {
        let course = CourseOrder(context.bundle)
        guard let item = course.itemsByID[target.id] else { return nil }
        guard isQuizSeen(item.id, in: context, course: course) else { return nil }
        guard let tokens = item.tokens, tokens.count >= 2 else { return nil }
        guard tokens.allSatisfy(tokenIsUsable) else { return nil }

        let accepted = item.acceptedOrders
        guard let order = incorrectOrder(
            count: tokens.count,
            tokens: tokens,
            acceptedOrders: accepted,
            using: &rng
        ) else { return nil }

        let spoken = tilePronunciations(for: tokens, on: item)
        return OrderWordsTask(
            targetID: item.id,
            tiles: order.map { WordTile(index: $0, text: tokens[$0], pronunciation: spoken[$0]) },
            fixedEnding: TokenRules.fixedEnding(of: item.pashto),
            tokens: tokens,
            acceptedOrders: accepted
        )
    }

    /// A new incorrect tile order. The same task comes back when that order
    /// is the only one that is not itself a correct answer.
    static func reshuffled(
        _ task: OrderWordsTask,
        using rng: inout some RandomNumberGenerator
    ) -> OrderWordsTask {
        guard let order = incorrectOrder(
            count: task.tokens.count,
            tokens: task.tokens,
            acceptedOrders: task.acceptedOrders,
            differentFrom: task.tiles.map(\.index),
            using: &rng
        ) else {
            return task
        }
        let spoken = Dictionary(uniqueKeysWithValues: task.tiles.map { ($0.index, $0.pronunciation) })
        return OrderWordsTask(
            targetID: task.targetID,
            tiles: order.map { WordTile(index: $0, text: task.tokens[$0], pronunciation: spoken[$0] ?? nil) },
            fixedEnding: task.fixedEnding,
            tokens: task.tokens,
            acceptedOrders: task.acceptedOrders
        )
    }
}

private func tilePronunciations(for tokens: [String], on item: ContentItem) -> [String?] {
    guard let stored = item.tokenPronunciations, stored.count == tokens.count else {
        return Array(repeating: nil, count: tokens.count)
    }
    return stored.map { Text.isBlank($0) ? nil : $0 }
}

public func grade(_ task: OrderWordsTask, _ answer: QuizAnswer) -> GradeResult {
    guard case .tokenOrder(let order) = answer else { return .incorrect }
    guard isAcceptedOrder(order, tokens: task.tokens, acceptedOrders: task.acceptedOrders) else {
        return .incorrect
    }
    return .correct
}

private func tokenIsUsable(_ token: String) -> Bool {
    if Text.isBlank(token) { return false }
    guard let first = token.unicodeScalars.first, let last = token.unicodeScalars.last else { return false }
    if first == " " || last == " " { return false }
    for scalar in token.unicodeScalars {
        if scalar == PashtoScript.arabicQuestion || scalar == PashtoScript.arabicComma {
            return false
        }
    }
    return true
}

private func incorrectOrder(
    count: Int,
    tokens: [String],
    acceptedOrders: [[Int]]?,
    differentFrom current: [Int]? = nil,
    using rng: inout some RandomNumberGenerator
) -> [Int]? {
    guard count >= 2 else { return nil }
    return shuffledUntil(Array(0..<count), using: &rng) { order in
        if let current, order == current {
            return false
        }
        return !isAcceptedOrder(order, tokens: tokens, acceptedOrders: acceptedOrders)
    }
}

private func isAcceptedOrder(_ order: [Int], tokens: [String], acceptedOrders: [[Int]]?) -> Bool {
    guard let proposed = tokenTexts(order, tokens: tokens) else { return false }
    if let identity = tokenTexts(Array(0..<tokens.count), tokens: tokens), proposed == identity {
        return true
    }
    for accepted in acceptedOrders ?? [] {
        guard let expected = tokenTexts(accepted, tokens: tokens), expected == proposed else { continue }
        return true
    }
    return false
}

private func tokenTexts(_ order: [Int], tokens: [String]) -> [String]? {
    guard order.count == tokens.count else { return nil }
    var used = Array(repeating: false, count: tokens.count)
    var texts: [String] = []
    for index in order {
        guard index >= 0, index < tokens.count, !used[index] else { return nil }
        used[index] = true
        texts.append(Normalization.nfc(tokens[index]))
    }
    return texts
}
