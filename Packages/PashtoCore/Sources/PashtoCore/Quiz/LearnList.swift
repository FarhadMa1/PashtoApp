import Foundation

/// One row on a learn lesson's word list.
///
/// `pronunciation` is the stored field, capitals included. The screen draws
/// `displayedPronunciation`, which swaps an ASCII hyphen for U+2011 so the
/// line wraps at spaces only. `picture` is nil when this unit does not show
/// one. The taxi picture is Town only, so Travel's taxi row has none.
public struct LearnListRow: Equatable, Sendable {
    public let itemID: ItemID
    public let english: String
    public let pronunciation: String
    public let pashto: String
    /// True when a bundled clip exists for this item. The screen plays it only after a tap.
    public let showsPlayButton: Bool
    public let picture: FamilyPictures.Picture?

    public init(
        itemID: ItemID,
        english: String,
        pronunciation: String,
        pashto: String,
        showsPlayButton: Bool,
        picture: FamilyPictures.Picture?
    ) {
        self.itemID = itemID
        self.english = english
        self.pronunciation = pronunciation
        self.pashto = pashto
        self.showsPlayButton = showsPlayButton
        self.picture = picture
    }

    /// The pronunciation the row draws. Letters and capitals match `pronunciation`.
    public var displayedPronunciation: String {
        LearnListPronunciation.display(pronunciation)
    }
}

/// Display form of a stored pronunciation.
///
/// An ASCII hyphen becomes U+2011. Nothing else changes, so capitals that
/// mark stress stay as they are stored.
public enum LearnListPronunciation {
    public static let nonBreakingHyphen: Character = "\u{2011}"

    public static func display(_ stored: String) -> String {
        String(stored.map { character in
            character == "-" ? nonBreakingHyphen : character
        })
    }

    /// The stored pronunciation. Display hyphens map back to ASCII hyphens.
    public static func stored(fromDisplayed displayed: String) -> String {
        String(displayed.map { character in
            character == nonBreakingHyphen ? "-" : character
        })
    }
}

/// The words of one learn lesson, in lesson order.
///
/// Phrases and practice return nil. `completedCount` is how many of these
/// words a finished practice lesson introduces. Opening the list does not
/// change that count and does not finish the lesson.
public struct LearnList: Equatable, Sendable {
    public let lessonID: LessonID
    public let unitID: UnitID
    public let title: String
    public let rows: [LearnListRow]
    public let completedCount: Int
    /// The unit's first practice lesson. Nil when the unit has none.
    public let practiceLessonID: LessonID?

    public init(
        lessonID: LessonID,
        unitID: UnitID,
        title: String,
        rows: [LearnListRow],
        completedCount: Int,
        practiceLessonID: LessonID?
    ) {
        self.lessonID = lessonID
        self.unitID = unitID
        self.title = title
        self.rows = rows
        self.completedCount = completedCount
        self.practiceLessonID = practiceLessonID
    }

    public var wordCount: Int { rows.count }

    /// `3 of 7 words`. The noun stays `words` for every count.
    public var countLabel: String {
        ModuleCopy.wordsCount(completed: completedCount, total: wordCount)
    }

    /// Looking at the list. The completed count stays where it was.
    public func viewed() -> LearnList { self }

    /// Rows for a learn lesson. Nil for phrases, practice, and an unknown id.
    ///
    /// `audioItemIDs` are the items that have a bundled clip. A finished
    /// learn lesson id does not raise `completedCount`. Only a finished
    /// practice lesson that introduces the word does.
    public static func make(
        for lessonID: LessonID,
        in bundle: ContentBundle,
        finishedLessonIDs: Set<LessonID>,
        audioItemIDs: Set<ItemID>
    ) -> LearnList? {
        guard let found = StudyCourse.lesson(lessonID, in: bundle) else { return nil }
        guard found.lesson.kind == .learn else { return nil }
        var itemsByID: [ItemID: ContentItem] = [:]
        for item in bundle.items where itemsByID[item.id] == nil {
            itemsByID[item.id] = item
        }
        let introduced = introducedByFinishedPractice(in: bundle, finishedLessonIDs: finishedLessonIDs)
        var rows: [LearnListRow] = []
        for reference in found.lesson.items where reference.role == .present {
            guard let item = itemsByID[reference.item] else { continue }
            let english = item.en?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            rows.append(LearnListRow(
                itemID: item.id,
                english: english,
                pronunciation: item.pronunciation,
                pashto: item.pashto,
                showsPlayButton: audioItemIDs.contains(item.id),
                picture: FamilyPictures.picture(
                    for: item.id,
                    english: item.en,
                    lessonKind: .learn,
                    unitID: found.unit.id
                )
            ))
        }
        guard !rows.isEmpty else { return nil }
        let completed = rows.reduce(into: 0) { count, row in
            if introduced.contains(row.itemID) { count += 1 }
        }
        return LearnList(
            lessonID: found.lesson.id,
            unitID: found.unit.id,
            title: found.lesson.title,
            rows: rows,
            completedCount: completed,
            practiceLessonID: StudyCourse.firstPracticeLesson(for: found.lesson.id, in: bundle)
        )
    }

    /// Item ids introduced by a finished practice lesson. Learn and phrases add nothing.
    private static func introducedByFinishedPractice(
        in bundle: ContentBundle,
        finishedLessonIDs: Set<LessonID>
    ) -> Set<ItemID> {
        var ids: Set<ItemID> = []
        for unit in bundle.units {
            for lesson in unit.lessons where lesson.kind == .practice && finishedLessonIDs.contains(lesson.id) {
                for reference in lesson.items where reference.role == .introduce {
                    ids.insert(reference.item)
                }
            }
        }
        return ids
    }
}

/// Saved words. The file sits next to the progress store and is not lesson progress.
///
/// A missing or unreadable file is an empty set. Toggling a word does not
/// finish a lesson.
public enum FavouriteWordStore {
    public static let fileName = "favourite-words.json"

    public static func fileURL(beside storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appendingPathComponent(fileName)
    }

    public static func load(beside storeURL: URL) -> Set<ItemID> {
        let url = fileURL(beside: storeURL)
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let stored = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        var ids: Set<ItemID> = []
        for raw in stored.itemIDs {
            if let id = ItemID(rawValue: raw) {
                ids.insert(id)
            }
        }
        return ids
    }

    public static func save(_ ids: Set<ItemID>, beside storeURL: URL) throws {
        let url = fileURL(beside: storeURL)
        let stored = File(itemIDs: ids.map(\.rawValue).sorted())
        let data = try JSONEncoder().encode(stored)
        try data.write(to: url, options: .atomic)
    }

    /// Removes the file. A missing file is already empty.
    public static func reset(beside storeURL: URL) {
        try? FileManager.default.removeItem(at: fileURL(beside: storeURL))
    }

    /// Adds the word, or removes it when it is already saved. The finished lessons stay as they were.
    public static func toggle(_ id: ItemID, in ids: Set<ItemID>) -> Set<ItemID> {
        var next = ids
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        return next
    }

    private struct File: Codable {
        var itemIDs: [String]
    }
}
