import Foundation

/// One learn or phrases card. The meaning is the item's approved English.
public struct StudyCard: Equatable, Sendable {
    public let itemID: ItemID
    public let pronunciation: String
    public let pashto: String
    public let meaning: String
    /// Approved explanation from the item's usage. Nil when the item has none.
    public let explanation: String?
    /// The item's pronunciation note, shown in the same secondary style as other notes.
    public let pronunciationNote: String?

    public init(
        itemID: ItemID,
        pronunciation: String,
        pashto: String,
        meaning: String,
        explanation: String? = nil,
        pronunciationNote: String? = nil
    ) {
        self.itemID = itemID
        self.pronunciation = pronunciation
        self.pashto = pashto
        self.meaning = meaning
        self.explanation = explanation
        self.pronunciationNote = pronunciationNote
    }
}

/// What one tap on a card screen did.
public enum StudyStep: Equatable, Sendable {
    /// The next card is showing. The meaning is hidden again on a phrases card.
    case advanced
    /// The English meaning was revealed. A second tap does not reveal it again.
    case revealedMeaning
    /// Open this lesson. A practice id starts the quiz. A card lesson replaces the deck.
    case open(LessonID)
    /// The tap was ignored. A second tap while the first is still in flight lands here.
    case ignored
}

/// The cards for one learn or phrases lesson. Nothing here is saved.
///
/// `next` moves one card. On the last card of a learn lesson, or of a phrases
/// lesson that is not the unit's last phrases lesson, `openNextLesson` opens
/// the next lesson. `startPractice` is only the last card of the unit's last
/// phrases lesson, and it opens the first practice lesson. `skipToPractice`
/// does that from any card.
/// A second tap before `settle` does not move another card and does not open
/// another lesson. `showMeaning` reveals the English once.
public struct StudyDeck: Equatable, Sendable {
    public let lessonID: LessonID
    public let unitID: UnitID
    public let title: String
    public let kind: LessonKind
    /// True for the last phrases lesson in the unit. Its last card reads Start practice.
    public let endsPhrases: Bool
    public let cards: [StudyCard]
    public private(set) var index: Int
    /// Learn cards show the meaning. Phrases cards hide it until Show meaning.
    public private(set) var meaningVisible: Bool
    private var locked: Bool

    public init(
        lessonID: LessonID,
        unitID: UnitID,
        title: String,
        kind: LessonKind,
        endsPhrases: Bool = false,
        cards: [StudyCard]
    ) {
        self.lessonID = lessonID
        self.unitID = unitID
        self.title = title
        self.kind = kind
        self.endsPhrases = endsPhrases
        self.cards = cards
        index = 0
        meaningVisible = kind == .learn
        locked = false
    }

    public var count: Int { cards.count }

    public var isLast: Bool { !cards.isEmpty && index == cards.count - 1 }

    /// The primary button reads Start practice only on the last card of the unit's last phrases lesson.
    public var offersStartPractice: Bool { endsPhrases && isLast }

    public var card: StudyCard? {
        cards.indices.contains(index) ? cards[index] : nil
    }

    /// Allows the next tap. The screen calls this after the card change has been taken.
    public mutating func settle() {
        locked = false
    }

    /// Ignores taps until `settle`. Used when a button just opened this deck.
    public mutating func hold() {
        locked = true
    }

    public mutating func next() -> StudyStep {
        guard !isLast else { return .ignored }
        guard lock() else { return .ignored }
        index += 1
        meaningVisible = kind == .learn
        return .advanced
    }

    public mutating func showMeaning() -> StudyStep {
        guard kind == .phrases, !meaningVisible else { return .ignored }
        guard lock() else { return .ignored }
        meaningVisible = true
        return .revealedMeaning
    }

    /// Last card of a lesson that is not the unit's last phrases lesson.
    /// `target` is the next lesson.
    public mutating func openNextLesson(_ target: LessonID?) -> StudyStep {
        guard isLast, !endsPhrases, let target else { return .ignored }
        guard kind == .learn || kind == .phrases else { return .ignored }
        guard lock() else { return .ignored }
        return .open(target)
    }

    /// Last card of the unit's last phrases lesson. `target` is the first practice lesson.
    public mutating func startPractice(opening target: LessonID?) -> StudyStep {
        guard endsPhrases, isLast, let target else { return .ignored }
        guard lock() else { return .ignored }
        return .open(target)
    }

    public mutating func skipToPractice(_ target: LessonID?) -> StudyStep {
        guard let target else { return .ignored }
        guard lock() else { return .ignored }
        return .open(target)
    }

    private mutating func lock() -> Bool {
        if locked { return false }
        locked = true
        return true
    }
}

/// Card lessons and the lessons their buttons open.
public enum StudyCourse {
    public static func lesson(_ id: LessonID, in bundle: ContentBundle) -> (unit: CourseUnit, lesson: Lesson)? {
        for unit in bundle.units {
            if let lesson = unit.lessons.first(where: { $0.id == id }) {
                return (unit, lesson)
            }
        }
        return nil
    }

    /// Cards for a learn or phrases lesson, in lesson order. Practice returns nil.
    public static func deck(for lessonID: LessonID, in bundle: ContentBundle) -> StudyDeck? {
        guard let found = lesson(lessonID, in: bundle) else { return nil }
        guard found.lesson.kind == .learn || found.lesson.kind == .phrases else { return nil }
        var itemsByID: [ItemID: ContentItem] = [:]
        for item in bundle.items where itemsByID[item.id] == nil {
            itemsByID[item.id] = item
        }
        var cards: [StudyCard] = []
        for reference in found.lesson.items where reference.role == .present {
            guard let item = itemsByID[reference.item] else { continue }
            let meaning = item.en?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let explanation = item.usage?.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = item.pronunciationNote?.trimmingCharacters(in: .whitespacesAndNewlines)
            cards.append(StudyCard(
                itemID: item.id,
                pronunciation: item.pronunciation,
                pashto: item.pashto,
                meaning: meaning,
                explanation: (explanation?.isEmpty == false) ? explanation : nil,
                pronunciationNote: (note?.isEmpty == false) ? note : nil
            ))
        }
        guard !cards.isEmpty else { return nil }
        guard let index = found.unit.lessons.firstIndex(where: { $0.id == found.lesson.id }) else { return nil }
        let later = found.unit.lessons[found.unit.lessons.index(after: index)...]
        let endsPhrases = found.lesson.kind == .phrases && !later.contains { $0.kind == .phrases }
        return StudyDeck(
            lessonID: found.lesson.id,
            unitID: found.unit.id,
            title: found.lesson.title,
            kind: found.lesson.kind,
            endsPhrases: endsPhrases,
            cards: cards
        )
    }

    /// The lesson after `lessonID` in its unit. Nil at the end of the unit.
    public static func nextLesson(after lessonID: LessonID, in bundle: ContentBundle) -> LessonID? {
        guard let found = lesson(lessonID, in: bundle) else { return nil }
        guard let index = found.unit.lessons.firstIndex(where: { $0.id == lessonID }) else { return nil }
        let next = found.unit.lessons.index(after: index)
        guard next < found.unit.lessons.endIndex else { return nil }
        return found.unit.lessons[next].id
    }

    /// The first practice lesson in the unit that contains `lessonID`.
    public static func firstPracticeLesson(for lessonID: LessonID, in bundle: ContentBundle) -> LessonID? {
        guard let found = lesson(lessonID, in: bundle) else { return nil }
        return found.unit.lessons.first { $0.kind == .practice }?.id
    }
}
