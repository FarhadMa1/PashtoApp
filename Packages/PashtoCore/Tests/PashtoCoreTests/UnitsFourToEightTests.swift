import Foundation
import Testing
@testable import PashtoCore

/// Units 4–8 follow the approved Learn / Phrases / Practice split.
struct UnitsFourToEightTests {
    private let newUnitIDs = ["u-numbers", "u-food", "u-town", "u-conversation"]

    @Test func releaseListIncludesTheNewUnitsInCourseOrder() throws {
        let course = try loadCourse()
        #expect(course.releasedUnitIDs.map(\.rawValue) == [
            "u-basics", "u-greetings", "u-introductions", "u-family", "u-travel", "u-time",
            "u-numbers", "u-food", "u-town", "u-conversation",
        ])
        #expect(course.bundle.units.map(\.id.rawValue) == ["u-sounds"] + course.releasedUnitIDs.map(\.rawValue))
        let ids = course.bundle.items.map(\.id.rawValue)
        #expect(ids.count == Set(ids).count)
        let lessonIDs = course.bundle.units.flatMap { $0.lessons.map(\.id.rawValue) }
        #expect(lessonIDs.count == Set(lessonIDs).count)
    }

    @Test func lessonsMatchTheApprovedSplit() throws {
        let bundle = try loadCourse().bundle
        let numbers = try unit("u-numbers", in: bundle)
        let food = try unit("u-food", in: bundle)
        let town = try unit("u-town", in: bundle)
        let conversation = try unit("u-conversation", in: bundle)
        #expect(numbers.title == "Numbers")
        #expect(food.title == "Food and drink")
        #expect(town.title == "Around town")
        #expect(conversation.title == "Putting it together")

        expectLesson("l-numbers-learn-one-to-five", "One to five", .learn, ["e-yaw", "e-dwa", "e-drey", "e-tsa-lor", "e-pin-dza"], .present, in: numbers)
        expectLesson("l-numbers-learn-six-to-ten", "Six to ten and age", .learn, ["e-shpag", "e-o-wa", "e-a-ta", "e-na-ha", "e-las", "e-o-mar"], .present, in: numbers)
        expectLesson("l-numbers-learn-eleven-to-fifteen", "Eleven to fifteen", .learn, ["e-yaw-wo-las", "e-dwo-las", "e-dyaar-las", "e-tswaar-las", "e-pin-dza-las"], .present, in: numbers)
        expectLesson("l-numbers-learn-sixteen-to-twenty", "Sixteen to twenty", .learn, ["e-shpaa-ras", "e-o-wa-las", "e-a-ta-las", "e-no-las", "e-shal"], .present, in: numbers)
        expectLesson("l-numbers-learn-years-old", "Years old", .learn, ["e-ka-lan", "e-ka-la-na"], .present, in: numbers)
        expectLesson("l-numbers-phrases-how-old", "How old are you?", .phrases, ["e-o-mar-dey-tso-day", "e-za-shal-ka-lan-yam", "e-za-shal-ka-la-na-yam"], .present, in: numbers)
        expectLesson("l-numbers-1", "Practice: One to ten", .practice, ["e-yaw", "e-dwa", "e-drey", "e-tsa-lor", "e-pin-dza", "e-shpag", "e-o-wa", "e-a-ta", "e-na-ha", "e-las", "e-o-mar"], .introduce, in: numbers)
        expectLesson("l-numbers-2", "Practice: Eleven to twenty", .practice, ["e-yaw-wo-las", "e-dwo-las", "e-dyaar-las", "e-tswaar-las", "e-pin-dza-las", "e-shpaa-ras", "e-o-wa-las", "e-a-ta-las", "e-no-las", "e-shal"], .introduce, in: numbers)
        expectLesson("l-numbers-3", "Practice: How old are you?", .practice, ["e-ka-lan", "e-ka-la-na", "e-o-mar-dey-tso-day", "e-za-shal-ka-lan-yam", "e-za-shal-ka-la-na-yam"], .introduce, in: numbers)

        expectLesson("l-food-learn-food-and-water", "Food and water", .learn, ["e-o-ba", "e-do-day", "e-wri-jey", "e-gho-kha", "e-ma-na"], .present, in: food)
        expectLesson("l-food-learn-drinks", "Drinks and asking for things", .learn, ["e-chaay", "e-kah-wa", "e-shee-dey", "e-ghwaa-ram", "e-shta", "e-na-shta"], .present, in: food)
        expectLesson("l-food-phrases-want", "Saying what you want", .phrases, ["e-tsa-ghwaa-rey", "e-za-o-ba-ghwaa-ram", "e-za-chaay-ghwaa-ram", "e-daa-ma-na-da"], .present, in: food)
        expectLesson("l-food-phrases-available", "Asking what is available", .phrases, ["e-daa-do-day-da", "e-chaay-shta", "e-ho-chaay-shta", "e-na-chaay-na-shta"], .present, in: food)
        expectLesson("l-food-1", "Practice: Food and water", .practice, ["e-o-ba", "e-do-day", "e-wri-jey", "e-gho-kha", "e-ma-na", "e-daa-ma-na-da", "e-daa-do-day-da", "e-za-o-ba-ghwaa-ram"], .introduce, in: food)
        expectLesson("l-food-2", "Practice: Drinks and asking", .practice, ["e-chaay", "e-kah-wa", "e-shee-dey", "e-ghwaa-ram", "e-shta", "e-na-shta", "e-tsa-ghwaa-rey", "e-za-chaay-ghwaa-ram", "e-chaay-shta", "e-ho-chaay-shta", "e-na-chaay-na-shta"], .introduce, in: food)

        expectLesson("l-town-learn-places", "Places in town", .learn, ["e-khaar", "e-baa-zaar", "e-doo-kaan", "e-rogh-toon", "e-cher-ta"], .present, in: town)
        expectLesson("l-town-learn-transport", "Transport and directions", .learn, ["e-tak-see", "e-bas", "e-sa-rak", "e-chap", "e-khee", "e-dal-ta", "e-hal-ta"], .present, in: town)
        expectLesson("l-town-phrases-where", "Asking where", .phrases, ["e-baa-zaar-cher-ta-day", "e-rogh-toon-cher-ta-day"], .present, in: town)
        expectLesson("l-town-phrases-going", "Saying where and going places", .phrases, ["e-baa-zaar-dal-ta-day", "e-rogh-toon-hal-ta-day", "e-za-baa-zaar-ta-dzam", "e-za-kor-ta-dzam"], .present, in: town)
        expectLesson("l-town-1", "Practice: Places in town", .practice, ["e-khaar", "e-baa-zaar", "e-doo-kaan", "e-rogh-toon", "e-cher-ta", "e-baa-zaar-cher-ta-day", "e-rogh-toon-cher-ta-day", "e-baa-zaar-dal-ta-day", "e-rogh-toon-hal-ta-day"], .introduce, in: town)
        expectLesson("l-town-2", "Practice: Transport and directions", .practice, ["e-tak-see", "e-bas", "e-sa-rak", "e-chap", "e-khee", "e-dal-ta", "e-hal-ta", "e-za-baa-zaar-ta-dzam", "e-za-kor-ta-dzam"], .introduce, in: town)

        expectLesson("l-conversation-learn-today", "Today and work", .learn, ["e-nan", "e-sa-baa", "e-kaar", "e-wakht"], .present, in: conversation)
        expectLesson("l-conversation-learn-languages", "Languages", .learn, ["e-zha-ba", "e-ang-lee-see", "e-kha-ba-rey"], .present, in: conversation)
        expectLesson("l-conversation-phrases-work", "I work", .phrases, ["e-za-kaar-ka-wam", "e-za-nan-kaar-ka-wam", "e-za-sa-baa-kaar-ka-wam"], .present, in: conversation)
        expectLesson("l-conversation-phrases-understanding", "Understanding each other", .phrases, ["e-za-pa-pakh-to-kha-ba-rey-ka-wam", "e-za-pa-ang-lee-see-kha-ba-rey-ka-wam", "e-za-na-po-he-gam", "e-byaa-wa-waa-yaast", "e-wro-wro"], .present, in: conversation)
        expectLesson("l-conversation-phrases-sentences", "Putting sentences together", .phrases, ["e-wro-wro-kha-ba-rey-wa-kray", "e-za-chaay-na-ghwaa-ram", "e-za-kah-wa-ghwaa-ram", "e-za-sa-baa-baa-zaar-ta-dzam"], .present, in: conversation)
        expectLesson("l-conversation-1", "Practice: Today and work", .practice, ["e-nan", "e-sa-baa", "e-kaar", "e-wakht", "e-za-kaar-ka-wam", "e-za-nan-kaar-ka-wam", "e-za-sa-baa-kaar-ka-wam"], .introduce, in: conversation)
        expectLesson("l-conversation-2", "Practice: Understanding each other", .practice, ["e-zha-ba", "e-ang-lee-see", "e-kha-ba-rey", "e-za-pa-pakh-to-kha-ba-rey-ka-wam", "e-za-pa-ang-lee-see-kha-ba-rey-ka-wam", "e-za-na-po-he-gam", "e-byaa-wa-waa-yaast", "e-wro-wro"], .introduce, in: conversation)
        expectLesson("l-conversation-3", "Practice: Putting sentences together", .practice, ["e-wro-wro-kha-ba-rey-wa-kray", "e-za-chaay-na-ghwaa-ram", "e-za-kah-wa-ghwaa-ram", "e-za-sa-baa-baa-zaar-ta-dzam"], .introduce, in: conversation)

        let group = ["e-za-shal-ka-lan-yam", "e-za-shal-ka-la-na-yam"]
        #expect(bundle.nonDistractorGroups.contains { Set($0.map(\.rawValue)) == Set(group) })
    }

    @Test func sharedTravelTownEntriesAreNotDuplicated() throws {
        let bundle = try loadCourse().bundle
        for shared in ["e-tak-see", "e-baa-zaar-cher-ta-day"] {
            #expect(bundle.items.filter { $0.id.rawValue == shared }.count == 1)
            let introductions = owners(of: shared, role: .introduce, in: bundle)
            let presentations = owners(of: shared, role: .present, in: bundle)
            #expect(introductions == ["u-town"])
            #expect(Set(presentations) == ["u-travel", "u-town"])
        }
        let around = try #require(StudyCourse.deck(for: lessonID("l-travel-learn-around"), in: bundle))
        #expect(around.title == "Getting around")
        let travelTaxi = try #require(around.cards.first { $0.itemID.rawValue == "e-tak-see" })
        #expect(FamilyPictures.picture(
            for: travelTaxi.itemID,
            english: travelTaxi.meaning,
            lessonKind: around.kind,
            unitID: around.unitID
        ) == nil)
        let transport = try #require(StudyCourse.deck(for: lessonID("l-town-learn-transport"), in: bundle))
        let townTaxi = try #require(transport.cards.first { $0.itemID.rawValue == "e-tak-see" })
        let townPicture = FamilyPictures.picture(
            for: townTaxi.itemID,
            english: townTaxi.meaning,
            lessonKind: transport.kind,
            unitID: transport.unitID
        )
        #expect(townPicture?.assetName == "e-tak-see")
        #expect(townPicture?.accessibilityLabel == "taxi")
        #expect(FamilyPictures.picture(
            for: townTaxi.itemID,
            english: "taxi",
            lessonKind: .practice,
            unitID: transport.unitID
        ) == nil)
        #expect(FamilyPictures.picture(
            for: townTaxi.itemID,
            english: "taxi",
            lessonKind: .phrases,
            unitID: transport.unitID
        ) == nil)
    }

    @Test func userFacingTextHasNoNorwegianAndNoBundledAudio() throws {
        let course = try loadCourse()
        let labels = MainMenuLabels.entries.filter { newUnitIDs.contains($0.unitID.rawValue) }.map(\.english)
        #expect(labels == ["Numbers", "Food", "Town", "Conversation"])
        var facing: [String] = labels
        for unit in course.bundle.units where newUnitIDs.contains(unit.id.rawValue) {
            facing.append(unit.title)
            for lesson in unit.lessons {
                facing.append(lesson.title)
                #expect(lesson.letters.isEmpty)
                #expect(lesson.kind == .practice ? lesson.countsForProgress : !lesson.countsForProgress)
            }
        }
        let owned = Set(course.bundle.units.filter { newUnitIDs.contains($0.id.rawValue) }.flatMap { unit in
            unit.lessons.flatMap { $0.items.map(\.item) }
        })
        for item in course.bundle.items where owned.contains(item.id) {
            facing.append(item.pronunciation)
            facing.append(contentsOf: [item.en, item.pronunciationNote, item.usage].compactMap { $0 })
            facing.append(contentsOf: item.enAlt ?? [])
            #expect(item.responseTo == nil)
            #expect(!item.hasAudio)
            #expect(!item.pronunciation.isEmpty)
        }
        let markers = ["æ", "ø", "å", "Æ", "Ø", "Å", "Bekreftet", "enhet", "uformelt"]
        for text in facing {
            for marker in markers where text.contains(marker) {
                Issue.record("\(text) contains \(marker)")
            }
        }
    }

    @Test func newCategoriesHaveTheirOwnColours() throws {
        let source = try String(contentsOf: repositoryRoot().appendingPathComponent("PashtoApp/Design/LapisStyle.swift"), encoding: .utf8)
        let colours = [
            "u-numbers": ["0xD4ECF7", "0x0B5674", "0x0F2A3A", "0x7DD3FC", "0xA2C6D6", "0x2A546A"],
            "u-food": ["0xFADDC9", "0x9A3A10", "0x3A1F12", "0xFDBA74", "0xE2B49B", "0x6B462A"],
            "u-town": ["0xDEE4EE", "0x2E4560", "0x1A2433", "0xBCCDE3", "0xB2BCCA", "0x424E5F"],
            "u-conversation": ["0xF5DAF0", "0x86198F", "0x36173A", "0xF0ABFC", "0xD9AAD8", "0x643C6A"],
        ]
        for (unit, hexes) in colours {
            let marker = "case \"\(unit)\":"
            let start = try #require(source.range(of: marker))
            let rest = source[start.upperBound...]
            let end = rest.range(of: "case \"")?.lowerBound ?? rest.range(of: "default:")?.lowerBound ?? rest.endIndex
            let block = String(rest[..<end])
            for hex in hexes where !block.contains(hex) {
                Issue.record("\(unit) missing \(hex)")
            }
        }
        #expect(source.contains("0xE6DDF7"))
        #expect(source.contains("0xDDEBCF"))
    }

    @Test func quizzesUseSameShapeDistractorsAndSkipAShortPool() throws {
        let course = try loadCourse()
        let bundle = course.bundle
        let items = Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id, $0) })
        let seen = bundle.units.flatMap(\.lessons).map(\.id)
        let practice = bundle.units
            .filter { newUnitIDs.contains($0.id.rawValue) }
            .flatMap(\.lessons)
            .filter { $0.kind == .practice }
        #expect(practice.count == 10)
        for lesson in practice {
            var rng = SplitMix64(seed: 1)
            let session = LessonSessionBuilder.build(
                for: lesson.id,
                in: bundle,
                seenLessonIDs: seen,
                releasedUnitIDs: course.releasedUnitIDs,
                using: &rng
            )
            if session.tasks.isEmpty {
                Issue.record("\(lesson.id.rawValue) became empty")
            }
            let context = QuizContext(
                bundle: bundle,
                seenLessonIDs: seen,
                releasedUnitIDs: course.releasedUnitIDs
            )
            for task in session.tasks {
                guard case .choice(let choice) = task.payload else { continue }
                let target = try #require(items[choice.targetID])
                let shape = DialogResponse.replyShape(of: target)
                let distractors = choice.options.filter { $0.itemID != choice.targetID }
                if distractors.count < 3 {
                    Issue.record("\(lesson.id.rawValue) \(choice.targetID.rawValue) has \(distractors.count) distractors")
                }
                for option in distractors {
                    let item = try #require(items[option.itemID])
                    #expect(DialogResponse.replyShape(of: item) == shape)
                }
            }
            for reference in lesson.items where reference.role == .introduce {
                let item = try #require(items[reference.item])
                #expect(DialogResponse.eligibleDistractors(for: item, in: context).isEmpty)
            }
        }
    }
}

private func owners(of item: String, role: LessonItemRole, in bundle: ContentBundle) -> [String] {
    bundle.units.flatMap { unit in
        unit.lessons.flatMap { lesson in
            lesson.items.filter { $0.role == role && $0.item.rawValue == item }.map { _ in unit.id.rawValue }
        }
    }
}

private func unit(_ id: String, in bundle: ContentBundle) throws -> CourseUnit {
    try #require(bundle.units.first { $0.id.rawValue == id })
}

private func expectLesson(
    _ id: String,
    _ title: String,
    _ kind: LessonKind,
    _ items: [String],
    _ role: LessonItemRole,
    in unit: CourseUnit
) {
    let lesson = unit.lessons.first { $0.id.rawValue == id }
    #expect(lesson?.title == title)
    #expect(lesson?.kind == kind)
    #expect(lesson?.items.map(\.item.rawValue) == items)
    #expect(lesson?.items.allSatisfy { $0.role == role } == true)
}

private func loadCourse() throws -> BundledCourse {
    let root = repositoryRoot()
    let content = try Data(contentsOf: root.appendingPathComponent("content/content.json"))
    let release = try Data(contentsOf: root.appendingPathComponent("content/release-units.json"))
    guard case .ready(let course) = BundledCourseLoader.load(content: content, releaseUnits: release) else {
        throw UnitsFourToEightTestError.missing
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

private enum UnitsFourToEightTestError: Error {
    case missing
}
