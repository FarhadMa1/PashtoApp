import Foundation

/// Pictured family words shown under the lesson groups on the Family page.
///
/// The order is the unit's learn cards. A row uses the same picture as that
/// learn card, so a phrase or a practice question never adds one. Every other
/// unit is empty. Pronunciation comes from `ContentItem.pronunciation` through
/// the same rule as the other screens. That rule never reads `translit`.
/// `showsPronunciation` is the stored `showTransliteration` setting, and it
/// does not hide the line. VoiceOver reads the English word and that
/// pronunciation. The Pashto is drawn and is not spoken. A row is not a
/// lesson, a quiz, or progress.
public enum FamilyWordList {
    public struct Row: Equatable, Sendable, Identifiable {
        public var id: ItemID { itemID }
        public var itemID: ItemID
        /// Asset catalog name. It is the item id.
        public var assetName: String
        /// English word. The picture uses this as its accessibility label.
        public var english: String
        /// Simple pronunciation. Nil only when the shared rule hides it.
        public var pronunciation: String?
        public var pashto: String

        public init(
            itemID: ItemID,
            assetName: String,
            english: String,
            pronunciation: String?,
            pashto: String
        ) {
            self.itemID = itemID
            self.assetName = assetName
            self.english = english
            self.pronunciation = pronunciation
            self.pashto = pashto
        }

        /// English, then the pronunciation when it is on screen. Pashto is left out.
        public var accessibilityLabel: String {
            guard let pronunciation, !Text.isBlank(pronunciation) else { return english }
            return "\(english), \(pronunciation)"
        }
    }

    /// Learn-card order. Family is the only unit with rows.
    public static func rows(
        for unitID: UnitID,
        in bundle: ContentBundle,
        showsPronunciation: Bool
    ) -> [Row] {
        guard unitID.rawValue == "u-family" else { return [] }
        guard let unit = bundle.units.first(where: { $0.id == unitID }) else { return [] }
        var itemsByID: [ItemID: ContentItem] = [:]
        for item in bundle.items where itemsByID[item.id] == nil {
            itemsByID[item.id] = item
        }
        var seen: Set<ItemID> = []
        var rows: [Row] = []
        for lesson in unit.lessons where lesson.kind == .learn {
            for reference in lesson.items where reference.role == .present {
                guard seen.insert(reference.item).inserted else { continue }
                guard let item = itemsByID[reference.item] else { continue }
                let english = item.en?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard let picture = FamilyPictures.picture(
                    for: item.id,
                    english: english,
                    lessonKind: .learn
                ) else {
                    continue
                }
                rows.append(Row(
                    itemID: item.id,
                    assetName: picture.assetName,
                    english: picture.accessibilityLabel,
                    pronunciation: QuizPresentation.spokenPronunciation(
                        text: item.pashto,
                        item: item,
                        showsPronunciation: showsPronunciation
                    ),
                    pashto: item.pashto
                ))
            }
        }
        return rows
    }
}
