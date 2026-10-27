import Foundation
@testable import PashtoCore

let standardUnstressed = [
    "ma", "še", "de", "da", "day", "ye", "yəm", "yāst", "na", "ho", "pə", "la", "də", "tsə", "zə", "tə",
]

func itemID(_ raw: String) -> ItemID {
    guard let id = ItemID(rawValue: raw) else { preconditionFailure("bad item id \(raw)") }
    return id
}

func lessonID(_ raw: String) -> LessonID {
    guard let id = LessonID(rawValue: raw) else { preconditionFailure("bad lesson id \(raw)") }
    return id
}

func unitID(_ raw: String) -> UnitID {
    guard let id = UnitID(rawValue: raw) else { preconditionFailure("bad unit id \(raw)") }
    return id
}

func dialogID(_ raw: String) -> DialogID {
    guard let id = DialogID(rawValue: raw) else { preconditionFailure("bad dialog id \(raw)") }
    return id
}

func makeItem(
    _ id: String = "e-salam",
    kind: ContentKind = .word,
    pashto: String = "سلام",
    translit: String = "sal\u{0101}\u{0301}m",
    pronunciation: String = "sa-LAAM",
    en: String? = "hello",
    usage: String? = nil,
    pronunciationNote: String? = nil,
    responseTo: String? = nil,
    tokens: [String]? = nil,
    acceptedOrders: [[Int]]? = nil,
    name: String? = nil,
    forms: LetterForms? = nil,
    sound: String? = nil,
    verification: Verification = Verification(status: .draft)
) -> ContentItem {
    let response = responseTo.map(itemID)
    return ContentItem(
        id: itemID(id),
        kind: kind,
        pashto: pashto,
        translit: translit,
        pronunciation: pronunciation,
        en: en,
        verification: verification,
        usage: usage,
        pronunciationNote: pronunciationNote,
        responseTo: response,
        tokens: tokens,
        acceptedOrders: acceptedOrders,
        name: name,
        forms: forms,
        sound: sound
    )
}

func makeBundle(
    items: [ContentItem],
    units: [CourseUnit]? = nil,
    difficult: [String] = [],
    unstressed: [String]? = nil,
    tableTranslit: String? = nil,
    groups: [[ItemID]] = [],
    variant: String = ContentBundle.kabulVariant
) -> ContentBundle {
    let unstressedWords = unstressed ?? standardUnstressed
    let coverage = tableTranslit ?? Normalization.nfc(unstressedWords.joined())
    let romanization = Romanization(
        table: [
            Romanization.Entry(
                letter: "a",
                translit: coverage.isEmpty ? "a" : coverage,
                ascii: "a",
                pronunciation: "a",
                description: "Test coverage for unstressedWords."
            ),
        ],
        difficultCharacters: difficult,
        unstressedWords: unstressedWords
    )
    return ContentBundle(
        contentVersion: "test",
        variant: variant,
        romanization: romanization,
        items: items,
        units: units ?? defaultUnits(for: items),
        nonDistractorGroups: groups
    )
}

func defaultUnits(for items: [ContentItem]) -> [CourseUnit] {
    let letters = items.filter { $0.kind == .letter }.map(\.id)
    let refs = items.filter { $0.kind != .letter }.map { LessonItemRef(item: $0.id, role: .introduce) }
    let lesson = Lesson(
        id: lessonID("l-greetings-1"),
        title: "Lesson",
        items: refs,
        letters: letters
    )
    return [CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [lesson])]
}

func validate(_ bundle: ContentBundle, mode: ValidationMode = .authoring) -> [ValidationIssue] {
    ContentValidator.validate(bundle, mode: mode)
}

func messages(_ issues: [ValidationIssue], severity: ValidationSeverity? = nil) -> [String] {
    issues.filter { severity == nil || $0.severity == severity }.map(\.message)
}
