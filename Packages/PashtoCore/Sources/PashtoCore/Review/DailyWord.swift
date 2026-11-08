import Foundation

/// Approved words for the Today card. The English matches the string catalog.
public enum DailyWordCopy {
    public static let title = "Word of the day"
    public static let showMeaning = "Show meaning"
}

/// One learned word for a civil day.
///
/// `pronunciation` is the simple pronunciation already stored for Pashto, or
/// nil when that field is blank. The stored preference does not leave it out.
/// This value never carries scholarly transliteration.
public struct DailyWord: Equatable, Sendable {
    public var itemID: ItemID
    public var pashto: String
    public var pronunciation: String?
    public var meaning: String

    public init(itemID: ItemID, pashto: String, pronunciation: String?, meaning: String) {
        self.itemID = itemID
        self.pashto = pashto
        self.pronunciation = pronunciation
        self.meaning = meaning
    }
}

/// The word for one local calendar date, taken from persisted review cards.
///
/// A review card is the stored record that an item was learned: a finished
/// lesson creates one, and a placement skip creates one too. A paused card
/// stays learned. An item with no card has not been learned, including a
/// word that only appears in the course. The item must also belong to a
/// released unit. Letters are not vocabulary. A word with no English meaning
/// is left out. The same day and the same cards return the same word. Card
/// order does not matter. Nil when nothing is eligible, so the home can omit
/// the card.
public enum DailyWordSelection {
    public static func select(
        cards: [ReviewCard],
        in bundle: ContentBundle,
        releasedUnitIDs: [UnitID],
        on day: LocalDay,
        showsPronunciation: Bool
    ) -> DailyWord? {
        // `showsPronunciation` is the stored preference. It does not hide the word.
        _ = showsPronunciation
        let released = ReleasedCourse.limiting(bundle, to: releasedUnitIDs)
        var itemsByID: [ItemID: ContentItem] = [:]
        for item in released.items where itemsByID[item.id] == nil {
            itemsByID[item.id] = item
        }
        var learned = Set<ItemID>()
        for card in cards {
            learned.insert(card.itemID)
        }
        let eligible = itemsByID.values.filter { item in
            learned.contains(item.id) && isVocabulary(item)
        }
        let sorted = eligible.sorted { $0.id.rawValue < $1.id.rawValue }
        guard let item = sorted[safe: index(on: day, count: sorted.count)] else { return nil }
        let meaning = item.en?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return DailyWord(
            itemID: item.id,
            pashto: item.pashto,
            pronunciation: QuizPresentation.spokenPronunciation(
                text: item.pashto,
                item: item,
                showsPronunciation: showsPronunciation
            ),
            meaning: meaning
        )
    }

    /// Stable across platforms. The input is the civil date `YYYY-MM-DD`.
    static func dayKey(_ day: LocalDay) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in day.isoDay.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    static func index(on day: LocalDay, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(dayKey(day) % UInt64(count))
    }

    /// Words, phrases, and dialog lines. A letter is script, not vocabulary.
    private static func isVocabulary(_ item: ContentItem) -> Bool {
        switch item.kind {
        case .word, .phrase, .dialogLine:
            break
        case .letter:
            return false
        }
        guard !Text.isBlank(item.pashto) else { return false }
        guard let meaning = item.en, !Text.isBlank(meaning) else { return false }
        return true
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
