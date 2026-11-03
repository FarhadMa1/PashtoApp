import Foundation

/// Edits the learner can make before Continue.
///
/// A placed word-order tile can be put back. A match can be changed, and a
/// right-hand card is linked to only one left-hand card.
public enum QuizDraft {
    public static func place(_ placed: [Int], tile: Int) -> [Int] {
        if let index = placed.firstIndex(of: tile) {
            var next = placed
            next.remove(at: index)
            return next
        }
        return placed + [tile]
    }

    public static func link(_ links: [ItemID: ItemID], left: ItemID, right: ItemID) -> [ItemID: ItemID] {
        var next = links
        for (key, value) in links where value == right && key != left {
            next[key] = nil
        }
        next[left] = right
        return next
    }

    public static func unlink(_ links: [ItemID: ItemID], left: ItemID) -> [ItemID: ItemID] {
        var next = links
        next[left] = nil
        return next
    }

    /// The mark for one linked pair after the answer.
    ///
    /// A correct pair stays marked when another pair is wrong.
    public static func pairMark(linkedRight: ItemID?, correctRight: ItemID, revealed: Bool) -> QuizResultMark? {
        guard revealed, let linkedRight else { return nil }
        return linkedRight == correctRight ? .correct : .incorrect
    }
}
