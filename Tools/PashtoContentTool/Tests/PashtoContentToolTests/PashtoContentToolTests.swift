import Foundation
import PashtoCore
import Testing
@testable import PashtoContentTool

struct ReleaseGateTests {
    @Test func draftItemsInAReleaseUnitAreErrorsAndStayInTheBundle() {
        let bundle = sampleBundle(itemCount: 6)
        let before = bundle.items.count
        let issues = ReleaseGate.issues(
            in: bundle,
            releaseUnitIDs: ["u-greetings"],
            itemUnits: Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id.rawValue, "u-greetings") }),
            specialSounds: [],
            mode: .release
        )
        #expect(bundle.items.count == before)
        let drafts = issues.filter { $0.field == "verification.status" && $0.severity == .error }
        #expect(drafts.count == 6)
        #expect(drafts.allSatisfy { $0.message.contains("must be verified") })

        let dev = ReleaseGate.issues(
            in: bundle,
            releaseUnitIDs: ["u-greetings"],
            itemUnits: Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id.rawValue, "u-greetings") }),
            specialSounds: [],
            mode: .dev
        )
        #expect(dev.filter { $0.field == "verification.status" }.allSatisfy { $0.severity == .warning })
    }

    @Test func lessonSizeIsAnErrorBelowFourAndAWarningAtFourOrFive() {
        let three = ReleaseGate.issues(in: sampleBundle(itemCount: 3), releaseUnitIDs: [], itemUnits: [:], specialSounds: [], mode: .release)
        #expect(three.contains { $0.severity == .error && $0.message.contains("has 3 items") })

        let four = ReleaseGate.issues(in: sampleBundle(itemCount: 4), releaseUnitIDs: [], itemUnits: [:], specialSounds: [], mode: .release)
        #expect(four.contains { $0.severity == .warning && $0.message.contains("has 4 items") })
        #expect(!four.contains { $0.severity == .error && $0.field == "items" })

        let five = ReleaseGate.issues(in: sampleBundle(itemCount: 5), releaseUnitIDs: [], itemUnits: [:], specialSounds: [], mode: .release)
        #expect(five.contains { $0.severity == .warning && $0.message.contains("has 5 items") })

        let six = ReleaseGate.issues(in: sampleBundle(itemCount: 6), releaseUnitIDs: [], itemUnits: [:], specialSounds: [], mode: .release)
        #expect(!six.contains { $0.field == "items" })

        let devThree = ReleaseGate.issues(in: sampleBundle(itemCount: 3), releaseUnitIDs: [], itemUnits: [:], specialSounds: [], mode: .dev)
        #expect(devThree.contains { $0.severity == .warning && $0.message.contains("has 3 items") })
        #expect(!devThree.contains { $0.severity == .error })
    }

    @Test func missingSoundExampleIsAnErrorInReleaseAndAWarningInDev() {
        let bundle = sampleBundle(itemCount: 6)
        let sound = SpecialSound(character: "ټ", translit: "ṭ")
        let release = ReleaseGate.issues(in: bundle, releaseUnitIDs: [], itemUnits: [:], specialSounds: [sound], mode: .release)
        #expect(release.contains { $0.severity == .error && $0.field == "soundExample" && $0.message.contains("ټ") })

        let dev = ReleaseGate.issues(in: bundle, releaseUnitIDs: [], itemUnits: [:], specialSounds: [sound], mode: .dev)
        #expect(dev.contains { $0.severity == .warning && $0.field == "soundExample" && $0.message.contains("ټ") })

        let covered = bundleWithSoundExample()
        let quiet = ReleaseGate.issues(
            in: covered.bundle,
            releaseUnitIDs: [],
            itemUnits: covered.itemUnits,
            specialSounds: [sound],
            mode: .release
        )
        #expect(!quiet.contains { $0.field == "soundExample" })
    }

    @Test func audioInV1IsAWarning() {
        let bundle = sampleBundle(itemCount: 6, audioOnFirst: true)
        let issues = ReleaseGate.issues(in: bundle, releaseUnitIDs: [], itemUnits: [:], specialSounds: [], mode: .release)
        #expect(issues.contains { $0.severity == .warning && $0.field == "audio" })
        #expect(!issues.contains { $0.field == "audio" && $0.severity == .error })
    }

    @Test func verifiedWithoutADateIsStillAnError() {
        let item = word("e-na", pashto: "نه", translit: "na", pronunciation: "na", en: "no", status: .verified, checkedBy: "farhad", checkedOn: nil)
        let extras = (1..<6).map { index in
            word(
                "e-extra-\(index)",
                pashto: "ن\(index)",
                translit: "na",
                pronunciation: "na",
                en: "extra \(index)",
                status: .verified,
                checkedBy: "farhad",
                checkedOn: "2026-10-27"
            )
        }
        let ids = ["e-na"] + extras.map(\.id.rawValue)
        let bundle = bundle(items: [item] + extras, lessons: [lesson(itemIDs: ids)])
        let issues = ContentValidator.validate(bundle, mode: .release)
        let missingDate = issues.contains { issue in
            issue.id == "e-na" && issue.field == "verification.checkedOn" && issue.severity == .error
        }
        #expect(missingDate)
    }
}

struct RegistryTests {
    @Test func emptyRegistryPassesAndMissingOrRetiredIDsFail() {
        let bundle = sampleBundle(itemCount: 6)
        #expect(IDRegistryCheck.issues(entries: [], bundle: bundle).isEmpty)

        let missing = IDRegistryCheck.issues(entries: [RegistryEntry(id: "e-gone", retired: false)], bundle: bundle)
        #expect(missing.count == 1)
        #expect(missing[0].message.contains("not retired"))

        let retired = IDRegistryCheck.issues(entries: [RegistryEntry(id: "e-na", retired: true)], bundle: bundle)
        #expect(retired.count == 1)
        #expect(retired[0].message.contains("used again"))

        let kept = IDRegistryCheck.issues(entries: [RegistryEntry(id: "e-na", retired: false)], bundle: bundle)
        #expect(kept.isEmpty)
    }
}

struct MergeTests {
    @Test func sameInputEncodesToTheSameBytes() throws {
        let root = try writeCourse(itemCount: 6, difficult: false, releaseUnits: [], registry: [])
        let first = ContentMerger.merge(root: root)
        let second = ContentMerger.merge(root: root)
        #expect(first.issues.isEmpty)
        #expect(first.bytes == second.bytes)
        let again = try BundleJSON.encode(#require(first.merged).bundle)
        #expect(again == first.bytes)
    }

    @Test func checkFailsWhenTheCommittedFileDiffers() throws {
        let root = try writeCourse(itemCount: 6, difficult: false, releaseUnits: [], registry: [])
        let outcome = ContentMerger.merge(root: root)
        let bytes = try #require(outcome.bytes)
        try bytes.write(to: ContentRoot(url: root).bundleFile)
        #expect(ContentMerger.checkCommittedBundle(root: root).isEmpty)

        var changed = bytes
        changed.append(contentsOf: [0x20])
        try changed.write(to: ContentRoot(url: root).bundleFile)
        let issues = ContentMerger.checkCommittedBundle(root: root)
        #expect(issues.contains { $0.message.contains("does not match") })
    }

    @Test func duplicateIDsNameBothFiles() throws {
        let root = try writeCourse(itemCount: 6, difficult: false, releaseUnits: [], registry: [])
        let copy = """
        {
          "id": "u-other",
          "track": "main",
          "title": "Other",
          "items": [\(itemJSON("e-na", pashto: "نه", translit: "na", pronunciation: "na", en: "no"))],
          "lessons": [\(lessonJSON("l-other-1", itemIDs: ["e-na"]))]
        }
        """
        try copy.write(to: ContentRoot(url: root).unitFile(named: "u-other"), atomically: true, encoding: .utf8)
        var course = try String(contentsOf: ContentRoot(url: root).courseFile, encoding: .utf8)
        course = course.replacingOccurrences(of: "\"u-greetings\"", with: "\"u-greetings\", \"u-other\"")
        try course.write(to: ContentRoot(url: root).courseFile, atomically: true, encoding: .utf8)

        let issues = ContentMerger.merge(root: root).issues
        #expect(issues.contains { $0.message.contains("e-na") && $0.message.contains("u-greetings.json") && $0.message.contains("u-other.json") })
    }

    @Test func fileNameMustMatchTheUnitID() throws {
        let root = try writeCourse(itemCount: 6, difficult: false, releaseUnits: [], registry: [])
        let file = ContentRoot(url: root).unitFile(named: "u-greetings")
        var text = try String(contentsOf: file, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"id\":\"u-greetings\"", with: "\"id\":\"u-other\"")
        try text.write(to: file, atomically: true, encoding: .utf8)
        let issues = ContentMerger.merge(root: root).issues
        #expect(issues.contains { $0.message.contains("file name must match") })
    }

    @Test func releaseCommandGoesRedForDraftsSmallLessonsAndMissingSounds() throws {
        let drafts = try writeCourse(itemCount: 6, difficult: false, releaseUnits: ["u-greetings"], registry: [])
        let draftIssues = ContentCheck.issues(root: drafts, mode: .release)
        #expect(draftIssues.contains { $0.severity == .error && $0.message.contains("must be verified") })

        let small = try writeCourse(itemCount: 3, difficult: false, releaseUnits: [], registry: [])
        let smallIssues = ContentCheck.issues(root: small, mode: .release)
        #expect(smallIssues.contains { $0.severity == .error && $0.message.contains("has 3 items") })

        let sounds = try writeCourse(itemCount: 6, difficult: true, releaseUnits: [], registry: [])
        let soundIssues = ContentCheck.issues(root: sounds, mode: .release)
        #expect(soundIssues.contains { $0.severity == .error && $0.field == "soundExample" })
        let devSounds = ContentCheck.issues(root: sounds, mode: .dev)
        #expect(devSounds.contains { $0.severity == .warning && $0.field == "soundExample" })
        #expect(!devSounds.contains { $0.severity == .error && $0.field == "soundExample" })
    }

    @Test func currentCourseReleaseGateReportsOnlyMissingSoundExamples() throws {
        let root = try repositoryRoot()
        #expect(ContentMerger.checkCommittedBundle(root: root).isEmpty)
        let dev = ContentCheck.issues(root: root, mode: .dev)
        let release = ContentCheck.issues(root: root, mode: .release)
        let sounds = ["ټ (ṭ)", "ڼ (ṇ)", "ږ (ǧ)", "ژ (ž)", "ق (q)", "ع (ʿ)"]
        #expect(dev.count == sounds.count)
        #expect(release.count == sounds.count)
        for (index, sound) in sounds.enumerated() {
            #expect(dev[index].severity == .warning)
            #expect(release[index].severity == .error)
            #expect(dev[index].id == "u-sounds")
            #expect(release[index].field == "soundExample")
            #expect(release[index].message.contains(sound))
            #expect(dev[index].message == release[index].message)
        }
    }
}

private struct Covered {
    var bundle: ContentBundle
    var itemUnits: [String: String]
}

private func bundleWithSoundExample() -> Covered {
    let example = word("e-tol", pashto: "ټول", translit: "ṭol", pronunciation: "tol", en: "all", status: .draft, note: "ټ")
    let others = [
        word("e-na", pashto: "نه", translit: "na", pronunciation: "na", en: "no", status: .draft),
        word("e-ho", pashto: "هو", translit: "ho", pronunciation: "ho", en: "yes", status: .draft),
        word("e-za", pashto: "زه", translit: "zə", pronunciation: "za", en: "I", status: .draft),
        word("e-ta", pashto: "ته", translit: "tə", pronunciation: "ta", en: "you", status: .draft),
        word("e-da", pashto: "دا", translit: "da", pronunciation: "da", en: "this", status: .draft),
    ]
    let sounds = Lesson(
        id: LessonID(rawValue: "l-sounds-1")!,
        title: "Sounds",
        items: [LessonItemRef(item: example.id, role: .soundExample, sound: "ṭ")] + others.map { LessonItemRef(item: $0.id, role: .introduce) }
    )
    let later = Lesson(
        id: LessonID(rawValue: "l-greetings-1")!,
        title: "Later",
        items: ([example] + others).map { LessonItemRef(item: $0.id, role: .introduce) }
    )
    let bundle = ContentBundle(
        contentVersion: "test",
        variant: ContentBundle.kabulVariant,
        romanization: romanization(difficult: ["ټ"]),
        items: [example] + others,
        units: [
            CourseUnit(id: UnitID(rawValue: "u-sounds")!, track: "main", title: "Sounds", lessons: [sounds]),
            CourseUnit(id: UnitID(rawValue: "u-greetings")!, track: "main", title: "Greetings", lessons: [later]),
        ],
        nonDistractorGroups: []
    )
    return Covered(bundle: bundle, itemUnits: ["e-tol": "u-greetings"])
}

private func sampleBundle(itemCount: Int, audioOnFirst: Bool = false) -> ContentBundle {
    let rows = sampleWords(itemCount)
    var items = rows.map { row in
        word(row.id, pashto: row.pashto, translit: row.translit, pronunciation: row.pronunciation, en: row.en, status: .draft)
    }
    if audioOnFirst, let audio = AudioRef(normal: "a", slow: "b", speaker: "c") {
        let first = items[0]
        items[0] = ContentItem(
            id: first.id,
            kind: first.kind,
            pashto: first.pashto,
            translit: first.translit,
            pronunciation: first.pronunciation,
            en: first.en,
            verification: first.verification,
            audio: audio
        )
    }
    return bundle(items: items, lessons: [lesson(itemIDs: items.map(\.id.rawValue))])
}

private func bundle(items: [ContentItem], lessons: [Lesson]) -> ContentBundle {
    ContentBundle(
        contentVersion: "test",
        variant: ContentBundle.kabulVariant,
        romanization: romanization(difficult: []),
        items: items,
        units: [CourseUnit(id: UnitID(rawValue: "u-greetings")!, track: "main", title: "Greetings", lessons: lessons)],
        nonDistractorGroups: []
    )
}

private func lesson(itemIDs: [String]) -> Lesson {
    Lesson(
        id: LessonID(rawValue: "l-greetings-1")!,
        title: "Hello",
        items: itemIDs.map { LessonItemRef(item: ItemID(rawValue: $0)!, role: .introduce) }
    )
}

private func romanization(difficult: [String]) -> Romanization {
    Romanization(
        table: [Romanization.Entry(letter: "a", translit: GeneratedBundle.unstressedWords.joined(), ascii: "a", pronunciation: "a", description: "Coverage.")],
        difficultCharacters: difficult,
        unstressedWords: GeneratedBundle.unstressedWords
    )
}

private struct WordRow {
    var id: String
    var pashto: String
    var translit: String
    var pronunciation: String
    var en: String
}

private func sampleWords(_ count: Int) -> [WordRow] {
    let rows = [
        WordRow(id: "e-na", pashto: "نه", translit: "na", pronunciation: "na", en: "no"),
        WordRow(id: "e-ho", pashto: "هو", translit: "ho", pronunciation: "ho", en: "yes"),
        WordRow(id: "e-za", pashto: "زه", translit: "zə", pronunciation: "za", en: "I"),
        WordRow(id: "e-ta", pashto: "ته", translit: "tə", pronunciation: "ta", en: "you"),
        WordRow(id: "e-da", pashto: "دا", translit: "da", pronunciation: "da", en: "this"),
        WordRow(id: "e-ma", pashto: "مه", translit: "ma", pronunciation: "ma", en: "me"),
    ]
    return Array(rows.prefix(count))
}

private func word(
    _ id: String,
    pashto: String,
    translit: String,
    pronunciation: String,
    en: String,
    status: VerificationStatus,
    checkedBy: String? = nil,
    checkedOn: String? = nil,
    note: String? = nil
) -> ContentItem {
    ContentItem(
        id: ItemID(rawValue: id)!,
        kind: .word,
        pashto: pashto,
        translit: translit,
        pronunciation: pronunciation,
        en: en,
        verification: Verification(status: status, checkedBy: checkedBy, checkedOn: checkedOn),
        pronunciationNote: note
    )
}

private func writeCourse(itemCount: Int, difficult: Bool, releaseUnits: [String], registry: [RegistryEntry]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let content = root.appendingPathComponent("content", isDirectory: true)
    let units = content.appendingPathComponent("units", isDirectory: true)
    try FileManager.default.createDirectory(at: units, withIntermediateDirectories: true)
    let rows = sampleWords(itemCount)
    let items = rows.map { itemJSON($0.id, pashto: $0.pashto, translit: $0.translit, pronunciation: $0.pronunciation, en: $0.en) }.joined(separator: ",")
    let lesson = lessonJSON("l-greetings-1", itemIDs: rows.map(\.id))
    let unit = """
    {"id":"u-greetings","track":"main","title":"Greetings","items":[\(items)],"lessons":[\(lesson)]}
    """
    try unit.write(to: units.appendingPathComponent("u-greetings.json"), atomically: true, encoding: .utf8)
    try """
    {"units":["u-greetings"],"nonDistractorGroups":[]}
    """.write(to: content.appendingPathComponent("course.json"), atomically: true, encoding: .utf8)
    let letters = difficult ? #"[{"char":"ټ","codepoint":"U+067C","translit":"ṭ"}]"# : "[]"
    try """
    {"version":1,"letters":\(letters)}
    """.write(to: content.appendingPathComponent("difficult-characters.json"), atomically: true, encoding: .utf8)
    let release = releaseUnits.map { "\"\($0)\"" }.joined(separator: ",")
    try """
    {"units":[\(release)]}
    """.write(to: content.appendingPathComponent("release-units.json"), atomically: true, encoding: .utf8)
    let entries = registry.map { "{\"id\":\"\($0.id)\",\"retired\":\($0.retired)}" }.joined(separator: ",")
    try """
    {"entries":[\(entries)]}
    """.write(to: content.appendingPathComponent("id-registry.json"), atomically: true, encoding: .utf8)
    return root
}

private func itemJSON(_ id: String, pashto: String, translit: String, pronunciation: String, en: String) -> String {
    """
    {"id":"\(id)","kind":"word","pashto":"\(pashto)","translit":"\(translit)","pronunciation":"\(pronunciation)","en":"\(en)","verification":{"status":"draft"}}
    """
}

private func repositoryRoot() throws -> URL {
    var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let fileManager = FileManager.default
    while url.path != "/" {
        let course = url.appendingPathComponent("content").appendingPathComponent("course.json")
        if fileManager.fileExists(atPath: course.path) {
            return url
        }
        url.deleteLastPathComponent()
    }
    Issue.record("content/course.json was not found from \(#filePath)")
    throw CancellationError()
}

private func lessonJSON(_ id: String, itemIDs: [String]) -> String {
    let refs = itemIDs.map { #"{"item":"\#($0)","role":"introduce"}"# }.joined(separator: ",")
    return #"{"id":"\#(id)","title":"Hello","items":[\#(refs)]}"#
}
