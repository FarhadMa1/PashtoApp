import Foundation
import Testing
@testable import PashtoCore

struct LearnListTests {
    @Test func playButtonFollowsBundledAudioAndNotTheUnitName() throws {
        let bundle = try loadCourse().bundle
        let withAudio = try audioItemIDs()
        let greetings = try #require(LearnList.make(
            for: lessonID("l-greetings-learn"),
            in: bundle,
            finishedLessonIDs: [],
            audioItemIDs: withAudio
        ))
        #expect(greetings.rows.map(\.itemID.rawValue) == ["e-xa", "e-manana", "e-ho", "e-na"])
        #expect(greetings.rows.allSatisfy { $0.showsPlayButton })

        let numbers = try #require(LearnList.make(
            for: lessonID("l-numbers-learn-one-to-five"),
            in: bundle,
            finishedLessonIDs: [],
            audioItemIDs: withAudio
        ))
        #expect(numbers.rows.allSatisfy { !$0.showsPlayButton })

        let onlyHello = try #require(ItemID(rawValue: "e-xa"))
        let partial = try #require(LearnList.make(
            for: lessonID("l-greetings-learn"),
            in: bundle,
            finishedLessonIDs: [],
            audioItemIDs: [onlyHello]
        ))
        #expect(partial.rows.map(\.showsPlayButton) == [true, false, false, false])
        #expect(LearnList.make(
            for: lessonID("l-greetings-phrases-hello"),
            in: bundle,
            finishedLessonIDs: [],
            audioItemIDs: withAudio
        ) == nil)
    }

    @Test func countIsPracticeWordsOverTheLessonAndViewingDoesNotFinishIt() throws {
        let bundle = try loadCourse().bundle
        let members = lessonID("l-family-learn-members")
        var finished: Set<LessonID> = []
        let fresh = try #require(LearnList.make(
            for: members,
            in: bundle,
            finishedLessonIDs: finished,
            audioItemIDs: []
        ))
        #expect(fresh.wordCount == 7)
        #expect(fresh.completedCount == 0)
        #expect(fresh.countLabel == "0 of 7 words")
        #expect(fresh.viewed() == fresh)
        #expect(finished.isEmpty)

        let viewedAsFinished = try #require(LearnList.make(
            for: members,
            in: bundle,
            finishedLessonIDs: [members],
            audioItemIDs: []
        ))
        #expect(viewedAsFinished.completedCount == 0)
        #expect(viewedAsFinished.countLabel == "0 of 7 words")

        finished = [lessonID("l-family-1")]
        let onePractice = try #require(LearnList.make(
            for: members,
            in: bundle,
            finishedLessonIDs: finished,
            audioItemIDs: []
        ))
        #expect(onePractice.completedCount == 6)
        #expect(onePractice.countLabel == "6 of 7 words")
        #expect(onePractice.viewed().completedCount == 6)
        #expect(finished == [lessonID("l-family-1")])

        finished.insert(lessonID("l-family-2"))
        let both = try #require(LearnList.make(
            for: members,
            in: bundle,
            finishedLessonIDs: finished,
            audioItemIDs: []
        ))
        #expect(both.completedCount == 7)
        #expect(both.countLabel == "7 of 7 words")
        #expect(both.practiceLessonID == lessonID("l-family-1"))

        let numbers = try #require(LearnList.make(
            for: lessonID("l-numbers-learn-one-to-five"),
            in: bundle,
            finishedLessonIDs: [lessonID("l-numbers-1")],
            audioItemIDs: []
        ))
        #expect(numbers.wordCount == 5)
        #expect(numbers.completedCount == 5)
        #expect(numbers.countLabel == "5 of 5 words")
        let numbersViewed = try #require(LearnList.make(
            for: lessonID("l-numbers-learn-one-to-five"),
            in: bundle,
            finishedLessonIDs: [lessonID("l-numbers-learn-one-to-five")],
            audioItemIDs: []
        ))
        #expect(numbersViewed.completedCount == 0)
    }

    @Test func renderedPronunciationEqualsTheStoredField() throws {
        let bundle = try loadCourse().bundle
        var itemsByID: [ItemID: ContentItem] = [:]
        for item in bundle.items where itemsByID[item.id] == nil {
            itemsByID[item.id] = item
        }
        var sawHyphen = false
        var sawLearn = false
        for unit in bundle.units {
            for lesson in unit.lessons where lesson.kind == .learn {
                sawLearn = true
                let list = try #require(LearnList.make(
                    for: lesson.id,
                    in: bundle,
                    finishedLessonIDs: [],
                    audioItemIDs: []
                ))
                #expect(list.rows.count == lesson.items.filter { $0.role == .present }.count)
                for row in list.rows {
                    let item = try #require(itemsByID[row.itemID])
                    #expect(row.pronunciation == item.pronunciation)
                    #expect(LearnListPronunciation.stored(fromDisplayed: row.displayedPronunciation) == item.pronunciation)
                    #expect(row.displayedPronunciation != item.translit || item.pronunciation == item.translit)
                    if item.pronunciation != item.translit {
                        #expect(row.pronunciation != item.translit)
                    }
                    if item.pronunciation.contains("-") {
                        sawHyphen = true
                        #expect(!row.displayedPronunciation.contains("-"))
                        #expect(row.displayedPronunciation.contains(LearnListPronunciation.nonBreakingHyphen))
                    } else {
                        #expect(row.displayedPronunciation == item.pronunciation)
                    }
                }
            }
        }
        #expect(sawLearn)
        #expect(sawHyphen)

        let members = try #require(LearnList.make(
            for: lessonID("l-family-learn-members"),
            in: bundle,
            finishedLessonIDs: [],
            audioItemIDs: []
        ))
        let father = try #require(members.rows.first { $0.itemID.rawValue == "e-plar" })
        #expect(father.pronunciation == "plaar")
        #expect(father.displayedPronunciation == "plaar")
        #expect(father.pronunciation != "Plar")
        let family = try #require(members.rows.first { $0.itemID.rawValue == "e-koraney" })
        #expect(family.pronunciation == "ko-ra-NAY")
        #expect(family.displayedPronunciation == "ko\u{2011}ra\u{2011}NAY")
        #expect(LearnListPronunciation.stored(fromDisplayed: family.displayedPronunciation) == "ko-ra-NAY")
    }

    @Test func taxiPictureIsTownOnlyOnTheList() throws {
        let bundle = try loadCourse().bundle
        let travel = try #require(LearnList.make(
            for: lessonID("l-travel-learn-around"),
            in: bundle,
            finishedLessonIDs: [],
            audioItemIDs: []
        ))
        let travelTaxi = try #require(travel.rows.first { $0.itemID.rawValue == "e-tak-see" })
        #expect(travelTaxi.picture == nil)
        #expect(travel.rows.contains { $0.picture != nil })

        let town = try #require(LearnList.make(
            for: lessonID("l-town-learn-transport"),
            in: bundle,
            finishedLessonIDs: [],
            audioItemIDs: []
        ))
        let townTaxi = try #require(town.rows.first { $0.itemID.rawValue == "e-tak-see" })
        #expect(townTaxi.picture?.assetName == "e-tak-see")
        #expect(townTaxi.picture?.accessibilityLabel == "taxi")
    }

    @Test func everyLearnLessonIncludingTheNewCategoriesHasAList() throws {
        let bundle = try loadCourse().bundle
        let expected = [
            "u-numbers", "u-food", "u-town", "u-conversation",
            "u-basics", "u-greetings", "u-introductions", "u-family", "u-travel", "u-time",
        ]
        var learnUnits: Set<String> = []
        for unit in bundle.units {
            for lesson in unit.lessons {
                let list = LearnList.make(
                    for: lesson.id,
                    in: bundle,
                    finishedLessonIDs: [],
                    audioItemIDs: []
                )
                if lesson.kind == .learn {
                    let rows = try #require(list)
                    #expect(!rows.rows.isEmpty)
                    #expect(rows.title == lesson.title)
                    #expect(rows.unitID == unit.id)
                    learnUnits.insert(unit.id.rawValue)
                } else {
                    #expect(list == nil)
                }
            }
        }
        #expect(learnUnits == Set(expected))
        let sounds = try #require(bundle.units.first { $0.id.rawValue == "u-sounds" })
        #expect(sounds.lessons.allSatisfy { $0.kind == .practice })
    }

    @Test func favouritesPersistBesideTheStoreAndDoNotFinishALesson() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("learn-list-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("Progress.store")
        #expect(FavouriteWordStore.load(beside: store).isEmpty)

        let mother = try #require(ItemID(rawValue: "e-mor"))
        let father = try #require(ItemID(rawValue: "e-plar"))
        var saved = FavouriteWordStore.toggle(mother, in: [])
        let finished: Set<LessonID> = [lessonID("l-family-1")]
        let before = finished
        saved = FavouriteWordStore.toggle(father, in: saved)
        #expect(finished == before)
        try FavouriteWordStore.save(saved, beside: store)
        #expect(FavouriteWordStore.load(beside: store) == [mother, father])

        let file = FavouriteWordStore.fileURL(beside: store)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("\"e-mor\""))
        #expect(text.contains("\"e-plar\""))

        saved = FavouriteWordStore.toggle(mother, in: saved)
        try FavouriteWordStore.save(saved, beside: store)
        #expect(FavouriteWordStore.load(beside: store) == [father])

        try Data("not json".utf8).write(to: file)
        #expect(FavouriteWordStore.load(beside: store).isEmpty)
        FavouriteWordStore.reset(beside: store)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(finished == before)
    }

    @Test func theListScreenDrawsStoredPronunciationWithoutClippingPashto() throws {
        let screen = try String(
            contentsOf: repositoryRoot().appendingPathComponent("PashtoApp/Quiz/StudyCardScreen.swift"),
            encoding: .utf8
        )
        let list = try #require(screen.range(of: "struct LearnListScreen"))
        let body = String(screen[list.lowerBound...])
        #expect(body.contains("row.displayedPronunciation"))
        #expect(body.contains("row.pronunciation"))
        #expect(body.contains("row.picture"))
        #expect(!body.contains(".translit"))
        #expect(!body.contains("textCase"))
        #expect(!body.contains("Tap to view examples"))
        #expect(!body.contains("lineLimit"))
        #expect(!body.contains("frame(height:"))
        #expect(body.contains("lineSpacing"))
        #expect(body.contains("ModuleCopy.practiceLesson"))
        #expect(body.contains("ModuleCopy.flashcards"))
        #expect(body.contains("clipPlayer.play"))
        #expect(!body.contains("onAppear"))
        let markers = ["æ", "ø", "å", "Æ", "Ø", "Å", "Bekreftet"]
        for marker in markers where body.contains(marker) {
            Issue.record("Learn list contains \(marker)")
        }
    }

    private func audioItemIDs() throws -> Set<ItemID> {
        let directory = repositoryRoot().appendingPathComponent("PashtoApp/Audio")
        let names = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "m4a" }
            .map { $0.deletingPathExtension().lastPathComponent }
        var ids: Set<ItemID> = []
        for name in names {
            ids.insert(try #require(ItemID(rawValue: name)))
        }
        #expect(ids.count == 19)
        return ids
    }

    private func loadCourse() throws -> BundledCourse {
        let root = repositoryRoot()
        let content = try Data(contentsOf: root.appendingPathComponent("content/content.json"))
        let release = try Data(contentsOf: root.appendingPathComponent("content/release-units.json"))
        guard case .ready(let course) = BundledCourseLoader.load(content: content, releaseUnits: release) else {
            Issue.record("The bundled course did not decode")
            throw LearnListTestError.missing
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
}

private enum LearnListTestError: Error {
    case missing
}
