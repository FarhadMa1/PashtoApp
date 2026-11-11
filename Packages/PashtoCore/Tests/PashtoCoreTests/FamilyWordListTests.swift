import Foundation
import Testing
@testable import PashtoCore

struct FamilyWordListTests {
    private let family = [
        "e-mor",
        "e-plar",
        "e-wror",
        "e-xor",
        "e-zoy",
        "e-lur",
        "e-koraney",
    ]
    private let travel = [
        "e-ha-waa-yee-da-gar",
        "e-ho-tal",
        "e-ti-kat",
        "e-tash-naab",
        "e-pay-se",
    ]
    private let town = [
        "e-tak-see",
    ]
    private let time = [
        "e-wradz",
        "e-sa-haar",
        "e-maa-khaam",
        "e-shpa",
    ]

    @Test func familyTravelAndTimeListOnlyTheirPicturedLearnWords() throws {
        let course = try loadCourse()
        let bundle = course.bundle
        let items = Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id, $0) })
        let expected = [
            "u-family": family,
            "u-travel": travel,
            "u-time": time,
            "u-town": town,
        ]

        for showsPronunciation in [true, false] {
            for (unit, pictured) in expected {
                let rows = FamilyWordList.rows(
                    for: unitID(unit),
                    in: bundle,
                    showsPronunciation: showsPronunciation
                )
                #expect(rows.map(\.itemID.rawValue) == pictured)
                #expect(rows.map(\.assetName) == pictured)
                #expect(rows.contains { row in
                    guard let item = items[row.itemID] else { return false }
                    return row.pronunciation != item.translit
                })
                for row in rows {
                    let item = try #require(items[row.itemID])
                    #expect(row.assetName == item.id.rawValue)
                    #expect(row.english == item.en)
                    #expect(row.pronunciation == item.pronunciation)
                    #expect(row.pashto == item.pashto)
                    #expect(row.accessibilityLabel == "\(item.en ?? ""), \(item.pronunciation)")
                    #expect(!row.accessibilityLabel.contains(item.pashto))
                    if item.translit != item.pronunciation {
                        #expect(row.pronunciation != item.translit)
                        #expect(!row.accessibilityLabel.contains(item.translit))
                    }
                    let asset = repositoryRoot()
                        .appendingPathComponent("PashtoApp/Assets.xcassets")
                        .appendingPathComponent("\(row.assetName).imageset")
                        .appendingPathComponent("\(row.assetName).png")
                    #expect(FileManager.default.fileExists(atPath: asset.path))
                }
            }
        }

        for unit in bundle.units where expected[unit.id.rawValue] == nil {
            #expect(FamilyWordList.rows(for: unit.id, in: bundle, showsPronunciation: true).isEmpty)
            #expect(FamilyWordList.rows(for: unit.id, in: bundle, showsPronunciation: false).isEmpty)
        }

        let listed = RootLessonSession.lessons(in: bundle, releasedUnitIDs: course.releasedUnitIDs)
        let menu = MainMenu.make(
            in: bundle,
            releasedUnitIDs: course.releasedUnitIDs,
            finishedLessonIDs: [],
            listedLessons: listed,
            showsPronunciation: false
        )
        for category in menu.categories {
            if let pictured = expected[category.id.rawValue] {
                #expect(category.wordList.map(\.itemID.rawValue) == pictured)
                #expect(category.wordList.map(\.assetName) == pictured)
                #expect(category.wordList.map(\.pronunciation) == pictured.map { items[itemID($0)]?.pronunciation })
            } else {
                #expect(category.wordList.isEmpty)
            }
        }
    }

    @Test func theCategoryPageShowsTheListAndTheQuizDoesNot() throws {
        let root = repositoryRoot()
        let screen = try String(contentsOf: root.appendingPathComponent("PashtoApp/ContentView.swift"), encoding: .utf8)
        let quiz = try String(contentsOf: root.appendingPathComponent("PashtoApp/Quiz/QuizScreen.swift"), encoding: .utf8)
        let model = try String(contentsOf: root.appendingPathComponent("PashtoApp/Launch/AppModel.swift"), encoding: .utf8)
        let list = try String(
            contentsOf: root.appendingPathComponent("Packages/PashtoCore/Sources/PashtoCore/Quiz/FamilyWordList.swift"),
            encoding: .utf8
        )
        let page = try section("private func categoryPage", until: "private var categoryKinds", in: screen)
        let row = try section("private struct FamilyWordRowView", until: "private struct DailyGoalRing", in: screen)
        let pashto = try section("private var pashto", until: "private struct DailyGoalRing", in: screen)

        #expect(page.contains("categorySection(kind, in: category)"))
        #expect(page.contains("FamilyWordListView(rows: category.wordList)"))
        let sectionIndex = try #require(page.range(of: "categorySection(kind, in: category)"))
        let listIndex = try #require(page.range(of: "FamilyWordListView(rows: category.wordList)"))
        #expect(sectionIndex.lowerBound < listIndex.lowerBound)
        #expect(!row.contains("Button"))
        #expect(!row.contains("startLesson"))
        #expect(row.contains("accessibilityElement(children: .ignore)"))
        #expect(row.contains("row.accessibilityLabel"))
        #expect(row.contains("accessibilityLabel(Text(verbatim: row.english))"))
        #expect(pashto.contains("accessibilityHidden(true)"))
        #expect(!pashto.contains("lineLimit"))
        #expect(!pashto.contains("truncationMode"))
        #expect(!quiz.contains("FamilyWordList"))
        #expect(!quiz.contains("FamilyPictures"))
        #expect(model.contains("showsPronunciation: snapshot?.settings.showTransliteration ?? UserSettings.initial.showTransliteration"))
        #expect(list.contains("QuizPresentation.spokenPronunciation"))
        #expect(list.contains("showsPronunciation: showsPronunciation"))
        #expect(!list.contains(".translit"))
    }

    private func section(_ start: String, until end: String, in source: String) throws -> String {
        let lower = try #require(source.range(of: start))
        let upper = try #require(source.range(of: end, range: lower.upperBound..<source.endIndex))
        return String(source[lower.lowerBound..<upper.lowerBound])
    }
}

private func loadCourse() throws -> BundledCourse {
    let root = repositoryRoot()
    let content = try Data(contentsOf: root.appendingPathComponent("content/content.json"))
    let release = try Data(contentsOf: root.appendingPathComponent("content/release-units.json"))
    guard case .ready(let course) = BundledCourseLoader.load(content: content, releaseUnits: release) else {
        Issue.record("The bundled course did not decode")
        throw FamilyWordListTestError.missing
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

private enum FamilyWordListTestError: Error {
    case missing
}
