import Foundation
import Testing
@testable import PashtoCore

struct MainMenuTests {
    @Test func labelsCoverExactlyTheReleasedUnits() throws {
        let course = try loadReleasedCourse()
        let mapped = MainMenuLabels.entries.map(\.unitID)
        #expect(mapped == course.releasedUnitIDs)
        #expect(Set(mapped) == Set(course.releasedUnitIDs))
        #expect(MainMenuLabels.entries.map(\.english) == [
            "Basics", "Greetings", "Introduction", "Family", "Travel", "Time",
        ])
        #expect(MainMenuLabels.entries.map(\.catalogKey) == [
            "menu.unit.basics",
            "menu.unit.greetings",
            "menu.unit.introduction",
            "menu.unit.family",
            "menu.unit.travel",
            "menu.unit.time",
        ])
        let bundleIDs = Set(course.bundle.units.map(\.id))
        #expect(bundleIDs.count > course.releasedUnitIDs.count)
        #expect(Set(mapped).isSubset(of: bundleIDs))
        #expect(!mapped.map(\.rawValue).contains("u-sounds"))
        #expect(!mapped.map(\.rawValue).contains("u-numbers"))
    }

    @Test func rowsUseTheReleaseListInCourseOrder() throws {
        let basics = unit("u-basics", title: "The basics", lessons: [
            lesson("l-basics-learn-1", "I am", .learn),
            lesson("l-basics-phrases", "About me", .phrases),
            lesson("l-basics-1", "Practice: The basics", .practice),
        ])
        let greetings = unit("u-greetings", title: "Greetings and politeness", lessons: [
            lesson("l-greetings-learn", "Key words", .learn),
            lesson("l-greetings-1", "Practice: Saying hello", .practice),
            lesson("l-greetings-2", "Practice: How are you?", .practice),
            lesson("l-greetings-3", "Practice: Goodbye", .practice),
        ])
        let numbers = unit("u-numbers", title: "Numbers 1–10", lessons: [
            lesson("l-numbers-1", "One to five", .practice),
        ])
        let bundle = ContentBundle(
            contentVersion: "test",
            variant: ContentBundle.kabulVariant,
            romanization: Romanization(table: [], difficultCharacters: [], unstressedWords: []),
            items: [],
            units: [basics, greetings, numbers],
            nonDistractorGroups: []
        )
        let listed = releasedRows(basics) + releasedRows(greetings) + releasedRows(numbers)
        let menu = MainMenu.make(
            in: bundle,
            releasedUnitIDs: [greetings.id, basics.id],
            finishedLessonIDs: [],
            listedLessons: listed
        )
        #expect(menu.categories.map(\.id.rawValue) == ["u-basics", "u-greetings"])
        #expect(menu.categories.map(\.title) == ["The basics", "Greetings and politeness"])
        #expect(!menu.categories.map(\.id.rawValue).contains("u-numbers"))
    }

    @Test func practiceProgressIgnoresLearnAndPhrases() throws {
        let course = try loadReleasedCourse()
        let listed = RootLessonSession.lessons(
            in: course.bundle,
            releasedUnitIDs: course.releasedUnitIDs
        )
        let fresh = MainMenu.make(
            in: course.bundle,
            releasedUnitIDs: course.releasedUnitIDs,
            finishedLessonIDs: [],
            listedLessons: listed
        )
        #expect(fresh.categories.map(\.id) == course.releasedUnitIDs)
        #expect(fresh.categories.map(\.practiceCompleted) == [0, 0, 0, 0, 0, 0])
        #expect(fresh.categories.map(\.practiceTotal) == [1, 3, 3, 3, 2, 2])
        #expect(fresh.categories.map(\.label) == ["Basics", "Greetings", "Introduction", "Family", "Travel", "Time"])
        #expect(fresh.categories.map(\.title) == [
            "The basics",
            "Greetings and politeness",
            "Introducing yourself",
            "Family",
            "Travel",
            "Time and days",
        ])
        #expect(fresh.continueTarget?.lessonID == lessonID("l-basics-learn-1"))
        #expect(fresh.continueTarget?.unitLabel == "Basics")

        let nonPractice = Set(listed.filter { $0.kind != .practice }.map(\.id))
        var finished = nonPractice
        finished.insert(lessonID("l-greetings-1"))
        finished.insert(lessonID("l-greetings-2"))
        finished.insert(lessonID("l-family-1"))
        let menu = MainMenu.make(
            in: course.bundle,
            releasedUnitIDs: course.releasedUnitIDs,
            finishedLessonIDs: finished,
            listedLessons: listed
        )
        #expect(menu.categories.map(\.practiceCompleted) == [0, 2, 0, 1, 0, 0])
        #expect(menu.categories.map(\.practiceTotal) == [1, 3, 3, 3, 2, 2])
        #expect(menu.categories[0].fraction == 0)
        #expect(menu.categories[1].fraction == 2.0 / 3.0)
        #expect(menu.categories[1].isComplete == false)
        #expect(menu.categories[0].lessons.allSatisfy { $0.kind == .practice || $0.isComplete == false })
        let greetingsPractice = menu.categories[1].lessons.filter { $0.kind == .practice }
        #expect(greetingsPractice.map(\.isComplete) == [true, true, false])
        #expect(menu.categories[1].lessons.filter { $0.kind != .practice }.allSatisfy { !$0.isComplete })
        #expect(menu.continueTarget?.lessonID == lessonID("l-basics-learn-1"))

        let basicsDone = finished.union([lessonID("l-basics-1")])
        let afterBasics = MainMenu.make(
            in: course.bundle,
            releasedUnitIDs: course.releasedUnitIDs,
            finishedLessonIDs: basicsDone,
            listedLessons: listed
        )
        #expect(afterBasics.categories[0].isComplete)
        #expect(afterBasics.categories[0].fraction == 1)
        #expect(afterBasics.continueTarget?.lessonID == lessonID("l-greetings-3"))
        #expect(afterBasics.continueTarget?.unitLabel == "Greetings")

        let allPractice = Set(listed.filter { $0.kind == .practice }.map(\.id))
        let done = MainMenu.make(
            in: course.bundle,
            releasedUnitIDs: course.releasedUnitIDs,
            finishedLessonIDs: allPractice,
            listedLessons: listed
        )
        #expect(done.categories.allSatisfy { $0.isComplete })
        #expect(done.continueTarget == nil)

        let familyOnly = MainMenu.make(
            in: course.bundle,
            releasedUnitIDs: [unitID("u-family")],
            finishedLessonIDs: [lessonID("l-family-1")],
            listedLessons: listed
        )
        #expect(familyOnly.categories.map(\.id.rawValue) == ["u-family"])
        #expect(familyOnly.categories[0].practiceCompleted == 1)
        #expect(familyOnly.categories[0].practiceTotal == 3)
        #expect(familyOnly.continueTarget?.lessonID == lessonID("l-family-2"))
    }

    @Test func continueFollowsTheFirstUnitThatStillHasPractice() throws {
        let course = try loadReleasedCourse()
        let listed = RootLessonSession.lessons(
            in: course.bundle,
            releasedUnitIDs: course.releasedUnitIDs
        )
        func menu(_ finished: Set<LessonID>) -> MainMenu {
            MainMenu.make(
                in: course.bundle,
                releasedUnitIDs: course.releasedUnitIDs,
                finishedLessonIDs: finished,
                listedLessons: listed
            )
        }

        let fresh = menu([])
        #expect(fresh.continueTarget?.lessonID == lessonID("l-basics-learn-1"))
        #expect(fresh.continueTarget?.unitID == unitID("u-basics"))
        #expect(fresh.continueTarget?.unitLabel == "Basics")

        let partial = menu([lessonID("l-basics-1"), lessonID("l-greetings-1")])
        #expect(partial.continueTarget?.lessonID == lessonID("l-greetings-2"))
        #expect(partial.continueTarget?.unitID == unitID("u-greetings"))
        #expect(partial.continueTarget?.unitLabel == "Greetings")

        let nextUnit = menu([lessonID("l-basics-1")])
        #expect(nextUnit.continueTarget?.lessonID == lessonID("l-greetings-learn"))
        #expect(nextUnit.continueTarget?.unitID == unitID("u-greetings"))
        #expect(nextUnit.continueTarget?.unitLabel == "Greetings")

        let allPractice = Set(listed.filter { $0.kind == .practice }.map(\.id))
        #expect(menu(allPractice).continueTarget == nil)

        let phrasesThenPractice = unit("u-numbers", title: "Numbers 1–10", lessons: [
            lesson("l-numbers-phrases", "Counts", .phrases),
            lesson("l-numbers-1", "One to five", .practice),
        ])
        let noLearn = MainMenu.make(
            in: ContentBundle(
                contentVersion: "test",
                variant: ContentBundle.kabulVariant,
                romanization: Romanization(table: [], difficultCharacters: [], unstressedWords: []),
                items: [],
                units: [phrasesThenPractice],
                nonDistractorGroups: []
            ),
            releasedUnitIDs: [phrasesThenPractice.id],
            finishedLessonIDs: [],
            listedLessons: releasedRows(phrasesThenPractice)
        )
        #expect(noLearn.continueTarget?.lessonID == lessonID("l-numbers-phrases"))
    }

    @Test func catalogAddsOnlyTheFourMenuLabelsAndDropsTheBasicsButton() throws {
        let url = repositoryRoot().appendingPathComponent("PashtoApp/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        let keys = Set(strings.keys)
        let added = [
            "menu.unit.basics": "Basics",
            "menu.unit.greetings": "Greetings",
            "menu.unit.introduction": "Introduction",
            "menu.unit.family": "Family",
            "menu.unit.travel": "Travel",
            "menu.unit.time": "Time",
        ]
        for (key, english) in added {
            #expect(try catalogValue(key, in: strings) == english)
        }
        #expect(keys == Set(menuCatalogKeysBeforeThisChange).subtracting(["basics.button"]).union(added.keys))
        #expect(!keys.contains("basics.button"))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("basics.button"))
        #expect(!text.contains("\"value\" : \"INTRODUCTION\""))
        #expect(!text.contains("\"value\" : \"The basics\""))

        let sources = try swiftSources()
        #expect(!sources.contains("struct BasicsSheet"))
        #expect(!sources.contains("BasicsBrowser"))
        #expect(!sources.contains("BasicsCatalog"))
        #expect(!sources.contains("ApprovedBasicsCopy"))
        #expect(!sources.contains("basics.button"))
        #expect(!sources.contains("basicsOpen"))
        #expect(!sources.contains("basicsCards"))
        let sheet = repositoryRoot().appendingPathComponent("PashtoApp/Quiz/BasicsSheet.swift")
        #expect(!FileManager.default.fileExists(atPath: sheet.path))
    }

    @Test func eachMenuUnitHasItsOwnPalette() throws {
        let source = try String(
            contentsOf: repositoryRoot().appendingPathComponent("PashtoApp/Design/LapisStyle.swift"),
            encoding: .utf8
        )
        let parsed = try menuPalettes(in: source)
        let expected: [String: MenuPalette] = [
            "u-basics": MenuPalette(
                fillLight: 0xDCE5FB, fillDark: 0x1B2A4A, hueLight: 0x1E3A8A, hueDark: 0x93B4F5, trackLight: 0xA8B8E0, trackDark: 0x334155
            ),
            "u-greetings": MenuPalette(
                fillLight: 0xFBE3BC, fillDark: 0x3A2A12, hueLight: 0x8A5A12, hueDark: 0xF2B85B, trackLight: 0xE0C080, trackDark: 0x5C4A28
            ),
            "u-introductions": MenuPalette(
                fillLight: 0xCDEDE7, fillDark: 0x12352F, hueLight: 0x0F5E55, hueDark: 0x5EEAD4, trackLight: 0x7DB5AB, trackDark: 0x2A4A44
            ),
            "u-family": MenuPalette(
                fillLight: 0xF6D6DC, fillDark: 0x3A1A24, hueLight: 0x8E2F45, hueDark: 0xFDA4AF, trackLight: 0xD4A0A8, trackDark: 0x5C3340
            ),
            "u-travel": MenuPalette(
                fillLight: 0xE6DDF7, fillDark: 0x2A1E42, hueLight: 0x5B2E91, hueDark: 0xC4B5FD, trackLight: 0xC1B1DF, trackDark: 0x4A3A6B
            ),
            "u-time": MenuPalette(
                fillLight: 0xDDEBCF, fillDark: 0x1F3315, hueLight: 0x3F5F1E, hueDark: 0xBEF264, trackLight: 0xB3C6A2, trackDark: 0x3A5229
            ),
        ]
        #expect(parsed == expected)
        #expect(Set(parsed.values).count == 6)
    }
}

private let menuCatalogKeysBeforeThisChange = [
    "Pashto",
    "basics.button",
    "celebration.correct",
    "celebration.dailyGoal",
    "celebration.dayStreak",
    "celebration.goalReached",
    "celebration.lessonComplete",
    "celebration.streakFreezeEarned",
    "celebration.toGo",
    "celebration.word.one",
    "celebration.word.other",
    "module.section.learn",
    "module.section.phrases",
    "module.section.practice",
    "path.locked",
    "path.now",
    "quiz.continue.button",
    "quiz.feedback.correct",
    "quiz.feedback.incorrect",
    "quiz.letterHint.da.plain",
    "quiz.letterHint.da.ring",
    "quiz.letterHint.ra.plain",
    "quiz.letterHint.ra.ring",
    "quiz.letterHint.ta.plain",
    "quiz.letterHint.ta.ring",
    "quiz.letterHint.za.dalDot",
    "quiz.letterHint.za.raDot",
    "quiz.option.1",
    "quiz.option.2",
    "quiz.option.3",
    "quiz.option.4",
    "storageError.body",
    "storageError.startOver.button",
    "storageError.startOver.cancel",
    "storageError.startOver.confirmMessage",
    "storageError.startOver.confirmTitle",
    "storageError.title",
    "storageError.tryAgain.button",
    "study.newWords",
    "study.next",
    "study.skipToPractice",
    "study.startPractice",
    "today.showMeaning",
    "today.wordOfTheDay",
    "updateNeeded.body",
    "updateNeeded.openAppStore.button",
    "updateNeeded.title",
    "welcomeBack.body",
    "welcomeBack.startReview.button",
    "welcomeBack.title",
]

private func catalogValue(_ key: String, in strings: [String: Any]) throws -> String {
    let entry = try #require(strings[key] as? [String: Any])
    let localizations = try #require(entry["localizations"] as? [String: Any])
    let english = try #require(localizations["en"] as? [String: Any])
    let unit = try #require(english["stringUnit"] as? [String: Any])
    return try #require(unit["value"] as? String)
}

private func swiftSources() throws -> String {
    let root = repositoryRoot()
    let directories = [
        root.appendingPathComponent("PashtoApp"),
        root.appendingPathComponent("Packages/PashtoCore/Sources"),
    ]
    var text = ""
    for directory in directories {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            continue
        }
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            text += try String(contentsOf: url, encoding: .utf8)
            text += "\n"
        }
    }
    return text
}

private func loadReleasedCourse() throws -> BundledCourse {
    let root = repositoryRoot()
    let content = try Data(contentsOf: root.appendingPathComponent("content/content.json"))
    let release = try Data(contentsOf: root.appendingPathComponent("content/release-units.json"))
    guard case .ready(let course) = BundledCourseLoader.load(content: content, releaseUnits: release) else {
        Issue.record("The bundled course did not decode")
        throw MainMenuTestError.missing
    }
    return course
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func lesson(_ id: String, _ title: String, _ kind: LessonKind) -> Lesson {
    Lesson(id: lessonID(id), title: title, items: [], kind: kind)
}

private func unit(_ id: String, title: String, lessons: [Lesson]) -> CourseUnit {
    CourseUnit(id: unitID(id), track: "main", title: title, lessons: lessons)
}

private func releasedRows(_ unit: CourseUnit) -> [ReleasedLesson] {
    unit.lessons.map { ReleasedLesson(id: $0.id, title: $0.title, unitID: unit.id, kind: $0.kind) }
}

private enum MainMenuTestError: Error {
    case missing
}

private struct MenuPalette: Equatable, Hashable {
    var fillLight: UInt32
    var fillDark: UInt32
    var hueLight: UInt32
    var hueDark: UInt32
    var trackLight: UInt32
    var trackDark: UInt32
}

private func menuPalettes(in source: String) throws -> [String: MenuPalette] {
    let resolve = try #require(source.range(of: "static func resolve(_ unitID: UnitID) -> MenuCard {"))
    let body = source[resolve.upperBound...]
    let names = ["u-greetings", "u-introductions", "u-family", "u-time", "u-travel", "default"]
    var blocks: [String: String] = [:]
    for (index, name) in names.enumerated() {
        let marker = name == "default" ? "default:" : "case \"\(name)\":"
        guard let start = body.range(of: marker) else { continue }
        let rest = body[start.upperBound...]
        let end = names[(index + 1)...].compactMap { next -> String.Index? in
            let token = next == "default" ? "default:" : "case \"\(next)\":"
            return rest.range(of: token)?.lowerBound
        }.min() ?? rest.endIndex
        blocks[name] = String(rest[..<end])
    }
    var parsed: [String: MenuPalette] = [:]
    for (name, block) in blocks {
        let card: String
        if let literal = block.range(of: "MenuCard(") {
            card = String(block[literal.lowerBound...])
        } else {
            let token = block.split(whereSeparator: { $0.isWhitespace || $0 == "\n" }).first.map(String.init) ?? ""
            let declaration = "static let \(token) = MenuCard("
            guard let found = source.range(of: declaration) else { continue }
            card = String(source[found.upperBound...])
        }
        let pairs = dynamicPairs(in: card).prefix(3)
        guard pairs.count == 3 else { continue }
        let key = name == "default" ? "u-basics" : name
        parsed[key] = MenuPalette(
            fillLight: pairs[0].0, fillDark: pairs[0].1,
            hueLight: pairs[1].0, hueDark: pairs[1].1,
            trackLight: pairs[2].0, trackDark: pairs[2].1
        )
    }
    return parsed
}

private func dynamicPairs(in source: String) -> [(UInt32, UInt32)] {
    var pairs: [(UInt32, UInt32)] = []
    var rest = Substring(source)
    let light = "light: 0x"
    let dark = "dark: 0x"
    while let lightRange = rest.range(of: light) {
        rest = rest[lightRange.upperBound...]
        let lightHex = rest.prefix { $0.isHexDigit }
        guard let darkRange = rest.range(of: dark) else { break }
        rest = rest[darkRange.upperBound...]
        let darkHex = rest.prefix { $0.isHexDigit }
        if let lightValue = UInt32(lightHex, radix: 16), let darkValue = UInt32(darkHex, radix: 16) {
            pairs.append((lightValue, darkValue))
        }
        if pairs.count == 3 { break }
    }
    return pairs
}
