/// Where a distractor was introduced, relative to the correct item.
public enum DistractorSource: Hashable, Sendable {
    /// Another item introduced in the correct item's lesson.
    case sameLesson
    /// An earlier lesson in the same unit. The nearest lesson comes first.
    case earlierLessonInUnit
    /// An earlier unit. The nearest unit comes first.
    case earlierUnit
}

/// One item that may be a wrong answer, in the order distractors are taken.
public struct DistractorCandidate: Hashable, Sendable {
    public let itemID: ItemID
    public let source: DistractorSource

    public init(itemID: ItemID, source: DistractorSource) {
        self.itemID = itemID
        self.source = source
    }
}

/// Distractors for one correct item.
///
/// Candidates come from the same lesson, then earlier lessons in that unit,
/// then earlier units. Later lessons are not used, even when their ids are in
/// `seenLessonIDs`. Unseen items, the correct item, retired items, items in the
/// same `nonDistractorGroup`, and items that share a normalized English
/// meaning (`en` or `enAlt`), Pashto spelling, transliteration, or
/// pronunciation are left out.
///
/// A letter is only a candidate for another letter. A day name is only a
/// candidate for another day name, including the two-word سه شنبه. A Travel
/// or Time item is a candidate only for the same Pashto word count: one word,
/// or more than one. `kind` does not decide that split. Earlier lessons keep
/// the pool they already had, so a greeting can still use a phrase as a wrong
/// option.
///
/// Membership tests use `Set.contains`. The course order itself is the
/// `units` array, so this type never walks a `Set` or `Dictionary`.
public enum Distractors {
    public static func candidates(for target: ContentItem, in context: QuizContext) -> [DistractorCandidate] {
        let course = CourseOrder(context.bundle)
        guard let stored = course.itemsByID[target.id] else { return [] }
        guard let targetIntro = course.introduction(of: target.id) else { return [] }
        let seenLessons = Set(context.seenLessonIDs)
        let retired = Set(context.retiredItemIDs)
        guard seenLessons.contains(targetIntro.lessonID), !retired.contains(target.id) else { return [] }

        var rows: [(introduction: Introduction, source: DistractorSource)] = []
        for introduction in course.introductions {
            guard introduction.itemID != target.id else { continue }
            guard seenLessons.contains(introduction.lessonID) else { continue }
            guard !retired.contains(introduction.itemID) else { continue }
            guard let source = distractorSource(of: introduction, target: targetIntro) else { continue }
            guard let item = course.itemsByID[introduction.itemID] else { continue }
            guard sameQuizPool(item.kind, stored.kind) else { continue }
            guard sameAnswerPool(item, stored) else { continue }
            guard !excluded(item, target: stored, groups: context.bundle.nonDistractorGroups) else { continue }
            rows.append((introduction, source))
        }

        rows.sort { lhs, rhs in
            comesBefore(lhs.introduction, rhs.introduction, target: targetIntro)
        }
        return rows.map { DistractorCandidate(itemID: $0.introduction.itemID, source: $0.source) }
    }

    /// Items this lesson introduces, in lesson order. A `soundExample` does not count.
    public static func introducedItems(in lessonID: LessonID, bundle: ContentBundle) -> [ContentItem] {
        let course = CourseOrder(bundle)
        var items: [ContentItem] = []
        for introduction in course.introductions where introduction.lessonID == lessonID {
            guard let item = course.itemsByID[introduction.itemID] else { continue }
            items.append(item)
        }
        return items
    }
}

struct Introduction {
    var itemID: ItemID
    var unitID: UnitID
    var unitIndex: Int
    var lessonIndex: Int
    var lessonID: LessonID
    var position: Int
}

/// Introductions in course order. The first introduction of an id wins.
struct CourseOrder {
    var introductions: [Introduction]
    var itemsByID: [ItemID: ContentItem]

    init(_ bundle: ContentBundle) {
        var itemsByID: [ItemID: ContentItem] = [:]
        for item in bundle.items where itemsByID[item.id] == nil {
            itemsByID[item.id] = item
        }
        self.itemsByID = itemsByID

        var introductions: [Introduction] = []
        var introduced = Set<ItemID>()
        for (unitIndex, unit) in bundle.units.enumerated() {
            for (lessonIndex, lesson) in unit.lessons.enumerated() {
                var position = 0
                for reference in lesson.items where reference.role == .introduce {
                    guard introduced.insert(reference.item).inserted else { continue }
                    introductions.append(Introduction(
                        itemID: reference.item,
                        unitID: unit.id,
                        unitIndex: unitIndex,
                        lessonIndex: lessonIndex,
                        lessonID: lesson.id,
                        position: position
                    ))
                    position += 1
                }
                for letter in lesson.letters {
                    guard introduced.insert(letter).inserted else { continue }
                    introductions.append(Introduction(
                        itemID: letter,
                        unitID: unit.id,
                        unitIndex: unitIndex,
                        lessonIndex: lessonIndex,
                        lessonID: lesson.id,
                        position: position
                    ))
                    position += 1
                }
            }
        }
        self.introductions = introductions
    }

    func introduction(of itemID: ItemID) -> Introduction? {
        introductions.first { $0.itemID == itemID }
    }
}

func distractorSource(of introduction: Introduction, target: Introduction) -> DistractorSource? {
    // The basics is inserted before units that already shipped. Its new phrases
    // stay inside that unit, so the quizzes in those units keep their pools.
    if introduction.unitID.rawValue == "u-basics", target.unitID.rawValue != "u-basics" {
        return nil
    }
    if introduction.lessonID == target.lessonID {
        return .sameLesson
    }
    if introduction.unitIndex == target.unitIndex, introduction.lessonIndex < target.lessonIndex {
        return .earlierLessonInUnit
    }
    if introduction.unitIndex < target.unitIndex {
        return .earlierUnit
    }
    return nil
}

/// Same lesson keeps content order. Earlier lessons and units are nearest first.
private func comesBefore(_ lhs: Introduction, _ rhs: Introduction, target: Introduction) -> Bool {
    let leftTier = tier(of: lhs, target: target)
    let rightTier = tier(of: rhs, target: target)
    if leftTier != rightTier {
        return leftTier < rightTier
    }
    switch leftTier {
    case 0:
        break
    case 1:
        if lhs.lessonIndex != rhs.lessonIndex {
            return lhs.lessonIndex > rhs.lessonIndex
        }
    default:
        if lhs.unitIndex != rhs.unitIndex {
            return lhs.unitIndex > rhs.unitIndex
        }
        if lhs.lessonIndex != rhs.lessonIndex {
            return lhs.lessonIndex > rhs.lessonIndex
        }
    }
    if lhs.position != rhs.position {
        return lhs.position < rhs.position
    }
    return lhs.itemID.rawValue < rhs.itemID.rawValue
}

private func tier(of introduction: Introduction, target: Introduction) -> Int {
    if introduction.lessonID == target.lessonID {
        return 0
    }
    if introduction.unitIndex == target.unitIndex {
        return 1
    }
    return 2
}

/// Letters stand alone. Day names and word-or-phrase shape are `sameAnswerPool`.
func sameQuizPool(_ candidate: ContentKind, _ target: ContentKind) -> Bool {
    (candidate == .letter) == (target == .letter)
}

/// Day names are wrong options only for day names. Travel and Time items
/// stay with their own shape: one Pashto word, or more than one. The two-word
/// day سه شنبه stays in the day-name pool, so it still has the other day names.
/// Items from earlier units are not split by shape.
enum AnswerPool {
    static let dayNames: Set<String> = [
        "e-shan-ba",
        "e-yak-shan-ba",
        "e-do-shan-ba",
        "e-se-shan-ba",
        "e-cha-haar-shan-ba",
        "e-panj-shan-ba",
        "e-ju-ma",
    ]

    /// New Travel and Time items. Day names are listed here too; the day-name
    /// check runs first and keeps سه شنبه with the other days.
    static let shaped: Set<String> = [
        "e-ha-waa-yee-da-gar",
        "e-ho-tal",
        "e-ti-kat",
        "e-tash-naab",
        "e-pay-se",
        "e-graan",
        "e-ar-zaan",
        "e-mras-ta",
        "e-ho-tal-cher-ta-day",
        "e-tash-naab-cher-ta-day",
        "e-za-ha-waa-yee-da-gar-ta-dzam",
        "e-dal-ta-wu-dre-ga",
        "e-za-ti-kat-ghwaa-ram",
        "e-daa-pa-tso-day",
        "e-der-graan-day",
        "e-mras-ta-wu-kray",
        "e-wradz",
        "e-sa-haar",
        "e-maa-khaam",
        "e-shpa",
        "e-os",
        "e-pa-roon",
        "e-shan-ba",
        "e-yak-shan-ba",
        "e-do-shan-ba",
        "e-se-shan-ba",
        "e-cha-haar-shan-ba",
        "e-panj-shan-ba",
        "e-ju-ma",
        "e-nan-tsa-wradz-da",
        "e-nan-ju-ma-da",
        "e-sa-baa-shan-ba-da",
        "e-tso-ba-je-dee",
        "e-sa-haar-mo-pa-khayr",
        "e-shpa-mo-pa-khayr",
        "e-za-os-dzam",
        "e-za-sa-haar-kaar-ka-wam",
    ]
}

func sameAnswerPool(_ candidate: ContentItem, _ target: ContentItem) -> Bool {
    let candidateDay = AnswerPool.dayNames.contains(candidate.id.rawValue)
    let targetDay = AnswerPool.dayNames.contains(target.id.rawValue)
    if candidateDay || targetDay {
        return candidateDay && targetDay
    }
    if AnswerPool.shaped.contains(candidate.id.rawValue) || AnswerPool.shaped.contains(target.id.rawValue) {
        return DialogResponse.replyShape(of: candidate) == DialogResponse.replyShape(of: target)
    }
    return true
}

private func excluded(_ candidate: ContentItem, target: ContentItem, groups: [[ItemID]]) -> Bool {
    if sharesGroup(candidate.id, target.id, groups) {
        return true
    }
    if meaningsOverlap(candidate, target) {
        return true
    }
    if Normalization.nfc(candidate.pashto) == Normalization.nfc(target.pashto) {
        return true
    }
    if Normalization.transliterationKey(candidate.translit) == Normalization.transliterationKey(target.translit) {
        return true
    }
    if Normalization.comparisonKey(candidate.pronunciation) == Normalization.comparisonKey(target.pronunciation) {
        return true
    }
    return false
}

func isQuizSeen(_ itemID: ItemID, in context: QuizContext, course: CourseOrder) -> Bool {
    guard let introduction = course.introduction(of: itemID) else { return false }
    if !context.seenLessonIDs.contains(introduction.lessonID) { return false }
    if context.retiredItemIDs.contains(itemID) { return false }
    return true
}

/// The two “you are” lines. A question must not offer both.
enum YouAreForms {
    private static let pair: Set<String> = ["e-ta-ye", "e-taso-yast"]

    static func clash(_ lhs: ItemID, _ rhs: ItemID) -> Bool {
        lhs != rhs && pair.contains(lhs.rawValue) && pair.contains(rhs.rawValue)
    }
}

func sharesGroup(_ lhs: ItemID, _ rhs: ItemID, _ groups: [[ItemID]]) -> Bool {
    for group in groups where group.contains(lhs) && group.contains(rhs) {
        return true
    }
    return false
}

/// `en` and every `enAlt`, folded with `Normalization.comparisonKey`.
func meaningsOverlap(_ lhs: ContentItem, _ rhs: ContentItem) -> Bool {
    let left = meaningKeys(lhs)
    let right = meaningKeys(rhs)
    for key in left where right.contains(key) {
        return true
    }
    return false
}

private func meaningKeys(_ item: ContentItem) -> [String] {
    var keys: [String] = []
    if let en = item.en, !Text.isBlank(en) {
        keys.append(Normalization.comparisonKey(en))
    }
    for alternate in item.enAlt ?? [] where !Text.isBlank(alternate) {
        let key = Normalization.comparisonKey(alternate)
        if !keys.contains(key) {
            keys.append(key)
        }
    }
    return keys
}
