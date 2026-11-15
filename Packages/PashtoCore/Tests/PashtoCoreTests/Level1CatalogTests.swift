import Foundation
import Testing
@testable import PashtoCore

struct Level1CatalogTests {
    private let level1Counts = [
        1: 49, 2: 36, 3: 39, 4: 35, 5: 50, 6: 48, 7: 51, 8: 31, 9: 57, 10: 48,
    ]

    @Test func levelOneHas431ItemsAndTheApprovedCategoryCounts() throws {
        let bundle = try loadCourse()
        var counts: [Int: Int] = [:]
        var level1: Set<ItemID> = []
        for membership in bundle.memberships where membership.category <= 10 {
            counts[membership.category, default: 0] += 1
            level1.insert(membership.item)
        }
        #expect(counts == level1Counts)
        #expect(level1.count == 431)
        let items = Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id, $0) })
        for id in level1 {
            let item = try #require(items[id])
            #expect(item.verification.status == .verified)
            #expect(item.verified == true)
            #expect(item.level == 1)
            #expect(item.dialect == "eastern")
        }
        #expect(items[itemID("e-naash-ta")] == nil)
        #expect(items[itemID("e-za-pa-roon-bukht-wam")] == nil)
        let breakfast = try #require(items[itemID("e-gaiz-ma-ray")])
        #expect(breakfast.pashto == "ګهیځ مړۍ")
        #expect(breakfast.pronunciation == "gaiz ma-RAY")
        #expect(breakfast.en == "Breakfast")
        let busy = try #require(items[itemID("e-za-pa-roon-mas-roof-wam")])
        #expect(busy.pashto == "زه پرون مصروف وم")
        #expect(busy.pronunciation == "za pa-ROON mas-ROOF wam")
        #expect(busy.en == "I was busy yesterday.")
        let juice = try #require(items[itemID("e-joos")])
        #expect(juice.pashto == "جوس")
        #expect(juice.pronunciation == "joos")
        let chicken = try #require(items[itemID("e-charga")])
        #expect(chicken.pronunciation == "char-GA")
        let drink = try #require(items[itemID("e-tsa-kal")])
        #expect(drink.pashto == "څښل")
        #expect(drink.pronunciation == "tsa-KAL")
        let tea = try #require(items[itemID("e-chaay-tsa-khey")])
        #expect(tea.pronunciation == "chaay tsa-KE?")
    }

    @Test func noColorFamilyRepeatsWithinALevel() throws {
        let bundle = try loadCourse()
        var families: [Int: Set<String>] = [:]
        var counts: [Int: Int] = [:]
        for category in bundle.categories {
            families[category.level, default: []].insert(category.colorFamily)
            counts[category.level, default: 0] += 1
        }
        for (level, count) in counts {
            #expect(families[level]?.count == count)
        }
        let hidden = bundle.categories.filter { $0.number >= 34 }
        #expect(hidden.count == 27)
        #expect(hidden.allSatisfy { categories in
            !bundle.memberships.contains { $0.category == categories.number }
        })
    }

    @Test func releaseGateHidesUnverifiedItemsAndCategories34Through60() throws {
        let item = ContentItem(
            id: itemID("e-hidden-word"),
            kind: .word,
            pashto: "کتاب",
            translit: "kitā\u{0301}b",
            pronunciation: "ki-TAAB",
            en: "Book",
            verification: Verification(status: .draft, checkedBy: nil, checkedOn: nil, comment: nil),
            verified: false
        )
        let visible = ContentItem(
            id: itemID("e-shown-word"),
            kind: .word,
            pashto: "قلم",
            translit: "qalam",
            pronunciation: "qa-LAM",
            en: "Pen",
            verification: Verification(status: .verified, checkedBy: "Farhad", checkedOn: "2026-11-15", comment: nil),
            verified: true
        )
        let lesson = Lesson(
            id: lessonID("l-hidden-1"),
            title: "Hidden",
            items: [
                LessonItemRef(item: item.id, role: .introduce),
                LessonItemRef(item: visible.id, role: .introduce),
            ],
            categoryNumber: 40
        )
        let unit = CourseUnit(id: unitID("u-basics"), track: "main", title: "Basics", lessons: [lesson])
        let bundle = ContentBundle(
            contentVersion: "test",
            variant: ContentBundle.kabulVariant,
            romanization: Romanization(table: [], difficultCharacters: [], unstressedWords: []),
            items: [item, visible],
            units: [unit],
            nonDistractorGroups: [],
            categories: [
                CourseCategory(number: 1, level: 1, title: "Greetings & Goodbyes", colorFamily: "saffron"),
                CourseCategory(number: 40, level: 5, title: "Restaurant Conversations", colorFamily: "lapis"),
            ],
            memberships: [
                CategoryMembership(category: 40, item: item.id),
                CategoryMembership(category: 40, item: visible.id),
            ]
        )
        let shown = ReleasedCatalog.showing(bundle)
        #expect(shown.categories.map(\.number) == [1])
        #expect(shown.items.map(\.id) == [visible.id])
        #expect(shown.memberships.isEmpty)
        #expect(shown.units[0].lessons[0].items.map(\.item) == [visible.id])
    }

    @Test func chiShayKeepsTheHyphenAndWhatStaysAWordInTheFilter() throws {
        let bundle = try loadCourse()
        let items = Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id, $0) })
        let what = try #require(items[itemID("e-tsa-q")])
        #expect(what.kind == .word)
        #expect(what.quizKind == .phrase)
        #expect(QuizItemType.filterType(what) == .word)
        #expect(QuizItemType.quizType(what) == .phrase)
        #expect(what.pronunciation == "chi-shay")
        #expect(TokenRules.looseMatch("chi shay", what.pronunciation))

        let name = try #require(items[itemID("e-sta-num-tsa-day")])
        #expect(name.pashto == "ستا نوم څه شی دی؟")
        #expect(name.pronunciation == "staa noom chi-shay day?")
        #expect(name.pronunciationNote == nil)
        #expect(name.tokens == ["ستا", "نوم", "څه", "شی", "دی"])
        #expect(TokenRules.looseMatch(
            (name.tokenPronunciations ?? []).joined(separator: " "),
            name.pronunciation
        ))
        let polite = try #require(items[itemID("e-staso-num-tsa-day")])
        #expect(polite.pronunciation == "STAA-so noom chi-shay day?")
        #expect(polite.pronunciationNote == nil)

        let want = try #require(items[itemID("e-tsa-ghwaa-rey")])
        #expect(want.pashto == "څه شی غواړې؟")
        #expect(want.pronunciation == "chi-shay ghwaa-REY?")
        #expect(want.pronunciationNote?.contains("څ:") == false)
        #expect(want.pronunciationNote?.contains("غ:") == true)
        #expect(want.pronunciationNote?.contains("ړ:") == true)

        let norway = try #require(items[itemID("e-za-la-narwe-tsaxa-yam")])
        #expect(norway.pashto == "زه د ناروې یم")
        #expect(norway.pronunciation == "za da naar-WEY yam")
        #expect(norway.translit == "zə də nārwe\u{0301} yəm")
        #expect(norway.pronunciationNote == nil)
    }

    @Test func distractorsDoNotSharePashtoPronunciationOrEnglish() throws {
        let bundle = try loadCourse()
        let items = Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id, $0) })
        let bus = try #require(items[itemID("e-bas")])
        let enough = try #require(items[itemID("e-bas-2")])
        #expect(excluded(enough, target: bus, groups: bundle.nonDistractorGroups))
        let informal = try #require(items[itemID("e-sta-num-tsa-day")])
        let polite = try #require(items[itemID("e-staso-num-tsa-day")])
        #expect(excluded(polite, target: informal, groups: bundle.nonDistractorGroups))
    }

    @Test func aChangedLineWithoutAClipHasNoPlayButton() throws {
        let bundle = try loadCourse()
        let changed = try #require(bundle.items.first { $0.id == itemID("e-sta-num-tsa-day") })
        #expect(changed.pashto == "ستا نوم څه شی دی؟")
        let without = LearnList.make(
            for: lessonID("l-c1-phrases-1"),
            in: bundle,
            finishedLessonIDs: [],
            audioItemIDs: []
        )
        // Phrases are not learn lists. The learn row is the play-button rule.
        let learn = try #require(LearnList.make(
            for: lessonID("l-c1-learn-1"),
            in: bundle,
            finishedLessonIDs: [],
            audioItemIDs: []
        ))
        #expect(learn.rows.allSatisfy { !$0.showsPlayButton })
        let sample = try #require(learn.rows.first?.itemID)
        let withClip = try #require(LearnList.make(
            for: lessonID("l-c1-learn-1"),
            in: bundle,
            finishedLessonIDs: [],
            audioItemIDs: [sample]
        ))
        #expect(withClip.rows.allSatisfy { $0.showsPlayButton == ($0.itemID == sample) })
        #expect(without == nil)
    }

    @Test func townTravelAndConversationKeepTheirLessonsAndLearnedItems() throws {
        let bundle = try loadCourse()
        let town = bundle.units.flatMap(\.lessons).filter { $0.categoryNumber == 14 }
        #expect(town.map(\.id.rawValue).contains("l-town-1"))
        #expect(town.map(\.id.rawValue).contains("l-travel-1"))
        let money = bundle.units.flatMap(\.lessons).filter { $0.categoryNumber == 13 }
        #expect(money.map(\.id.rawValue) == ["l-travel-2"])
        let work = bundle.units.flatMap(\.lessons).first { $0.id == lessonID("l-conversation-phrases-work") }
        #expect(work?.categoryNumber == 18)
        let today = bundle.units.flatMap(\.lessons).first { $0.id == lessonID("l-conversation-1") }
        #expect(today?.categoryNumber == 7)
        #expect(!bundle.categories.map(\.title).contains("Putting it together"))

        let finished = Set([
            lessonID("l-town-1"), lessonID("l-town-2"),
            lessonID("l-travel-1"), lessonID("l-travel-2"),
            lessonID("l-conversation-1"), lessonID("l-conversation-2"), lessonID("l-conversation-3"),
        ])
        let before = snapshot(finished: finished)
        let outcome = LessonMergeMigration.apply(before, to: bundle)
        #expect(outcome.snapshot == before)
        #expect(outcome.wordsLearned == before.cards.count)
        #expect(outcome.snapshot.streak == before.streak)
        for lesson in bundle.units.flatMap(\.lessons) where finished.contains(lesson.id) {
            #expect(outcome.statuses[lesson.id] == .done)
            for ref in lesson.items where ref.role == .introduce {
                #expect(outcome.learnedItemIDs.contains(ref.item))
            }
        }
        let items = Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id, $0) })
        let townItem = try #require(items[itemID("e-bas")])
        #expect(bundle.memberships.contains { $0.item == townItem.id && $0.category == 14 })
        #expect(bundle.categories.first { $0.number == 14 }?.level == 2)
    }

    private func snapshot(finished: Set<LessonID>) -> ProgressSnapshot {
        let day = LocalDay(year: 2026, month: 11, day: 15)
        let lessons = finished.map { id in
            LessonProgress(lessonID: id, source: .completed, firstCompletedDay: day, bestScorePercent: 100)
        }
        return ProgressSnapshot(
            contentVersion: "2026.11.0",
            cards: [],
            lessonProgress: lessons,
            streak: StreakState(
                current: 3,
                longest: 3,
                lastActiveDay: day,
                freezes: 1,
                daysTowardNextFreeze: 3,
                freezeUsedDays: []
            ),
            settings: .initial,
            activeSession: nil,
            completedSessions: [],
            lastReconciledContentVersion: nil,
            latestObservedDay: day
        )
    }

    private func loadCourse() throws -> ContentBundle {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("content/content.json"))
        return try JSONDecoder().decode(ContentBundle.self, from: data)
    }
}
