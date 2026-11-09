import Foundation

/// Learn cards from the released basics unit, in lesson order then card order.
///
/// Phrases and practice are not included. A unit that is not in the release
/// list contributes nothing. This reads the bundle it is given and does not
/// write progress, a streak, a daily goal, or placement.
public enum BasicsCatalog {
    /// Course id of the unit. The home button does not use this as a label.
    public static let unitRawValue = "u-basics"

    public static func learnCards(in bundle: ContentBundle, releasedUnitIDs: [UnitID]) -> [StudyCard] {
        guard let unitID = UnitID(rawValue: unitRawValue) else { return [] }
        guard releasedUnitIDs.contains(unitID) else { return [] }
        let released = ReleasedCourse.limiting(bundle, to: releasedUnitIDs)
        guard let unit = released.units.first(where: { $0.id == unitID }) else { return [] }
        var cards: [StudyCard] = []
        for lesson in unit.lessons where lesson.kind == .learn {
            guard let deck = StudyCourse.deck(for: lesson.id, in: released) else { continue }
            cards.append(contentsOf: deck.cards)
        }
        return cards
    }
}

/// Opening the reference list and looking at one card.
///
/// `progress` is carried so a caller can see that these steps do not change it.
/// `open`, `view`, `closeCard`, and `close` never assign `progress`.
public struct BasicsBrowser: Equatable, Sendable {
    public private(set) var progress: ProgressSnapshot
    public let cards: [StudyCard]
    public private(set) var isOpen: Bool
    public private(set) var visibleItemID: ItemID?

    public init(progress: ProgressSnapshot, cards: [StudyCard]) {
        self.progress = progress
        self.cards = cards
        self.isOpen = false
        self.visibleItemID = nil
    }

    public var visibleCard: StudyCard? {
        guard let visibleItemID else { return nil }
        return cards.first { $0.itemID == visibleItemID }
    }

    public mutating func open() {
        isOpen = true
    }

    /// Shows one listed card. An id that is not in `cards` is ignored.
    public mutating func view(_ itemID: ItemID) {
        guard cards.contains(where: { $0.itemID == itemID }) else { return }
        visibleItemID = itemID
    }

    public mutating func closeCard() {
        visibleItemID = nil
    }

    public mutating func close() {
        isOpen = false
        visibleItemID = nil
    }
}
