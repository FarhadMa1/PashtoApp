import Foundation
import Testing
@testable import PashtoCore

struct RealisticContentValidationTests {
    @Test func difficultCharacterFileMatchesCodepoints() throws {
        let list = try loadDifficultCharacters()
        #expect(list.version == 1)
        #expect(list.letters.count == 13)
        #expect(DifficultCharacterRules.issues(in: list).isEmpty)

        let broken = DifficultCharacterList(version: 1, letters: [
            DifficultCharacterEntry(char: "ab", codepoint: "U+0061", translit: "a"),
            DifficultCharacterEntry(char: "ټ", codepoint: "U+0061", translit: "t"),
            DifficultCharacterEntry(char: "ټ", codepoint: "nope", translit: "t"),
        ])
        let issues = DifficultCharacterRules.issues(in: broken)
        #expect(issues.count == 4)
        #expect(issues.contains { $0.message.contains("one character") })
        #expect(issues.contains { $0.message.contains("does not match") })
        #expect(issues.contains { $0.message.contains("repeats") })
        #expect(issues.contains { $0.message.contains("not a U+ value") })
    }

    @Test func unitsZeroThroughTwoReportLetterGapsOnly() throws {
        let bundle = try loadUnitsBundle()
        let issues = validate(bundle)
        #expect(validate(bundle, mode: .release) == issues)

        let letterIDs = [
            "e-letter-alif", "e-letter-be", "e-letter-pe", "e-letter-te", "e-letter-tte", "e-letter-se",
            "e-letter-jim", "e-letter-che", "e-letter-he", "e-letter-xe", "e-letter-tse", "e-letter-dze",
        ]
        var expected: [ValidationIssue] = []
        for id in letterIDs {
            expected.append(ValidationIssue(id: id, field: "en", message: "en is required.", severity: .error))
            expected.append(ValidationIssue(id: id, field: "forms", message: "forms is required on a letter.", severity: .error))
            expected.append(ValidationIssue(id: id, field: "sound", message: "sound is required on a letter.", severity: .error))
        }
        #expect(issues == expected)
    }
}

private struct UnitSourceFile: Decodable {
    let id: UnitID
    let track: String
    let title: String
    let items: [ContentItem]
    let lessons: [Lesson]
}

private struct CourseSourceFile: Decodable {
    let units: [String]
    let nonDistractorGroups: [[String]]
}

private func fixtureRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("units-0-2")
}

private func loadDifficultCharacters() throws -> DifficultCharacterList {
    let url = fixtureRoot().appendingPathComponent("difficult-characters.json")
    return try JSONDecoder().decode(DifficultCharacterList.self, from: Data(contentsOf: url))
}

private func loadUnitsBundle() throws -> ContentBundle {
    let root = fixtureRoot()
    let course = try JSONDecoder().decode(CourseSourceFile.self, from: Data(contentsOf: root.appendingPathComponent("course.json")))
    let difficult = try loadDifficultCharacters()
    var items: [ContentItem] = []
    var units: [CourseUnit] = []
    for unitName in course.units {
        let file = root.appendingPathComponent("units").appendingPathComponent("\(unitName).json")
        let source = try JSONDecoder().decode(UnitSourceFile.self, from: Data(contentsOf: file))
        items.append(contentsOf: source.items)
        units.append(CourseUnit(id: source.id, track: source.track, title: source.title, lessons: source.lessons))
    }
    let groups = try course.nonDistractorGroups.map { group in
        try group.map { raw in
            try #require(ItemID(rawValue: raw))
        }
    }
    return makeBundle(
        items: items,
        units: units,
        difficult: difficult.letters.map(\.char),
        groups: groups
    )
}
