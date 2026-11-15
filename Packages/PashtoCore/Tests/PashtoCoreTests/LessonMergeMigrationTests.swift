import Foundation
import Testing
@testable import PashtoCore

struct LessonMergeMigrationTests {
    private let day = LocalDay(year: 2026, month: 11, day: 2)
    private let earlier = LocalDay(year: 2026, month: 10, day: 20)

    @Test func learnAndPhrasesLessonsAreTwentyEightAndOldItemsStay() throws {
        let bundle = try loadMergedCourse()
        let cardLessons = bundle.units.flatMap(\.lessons).filter { $0.kind == .learn || $0.kind == .phrases }
        #expect(cardLessons.count == 28)

        var presented: [String: [String]] = [:]
        for lesson in cardLessons {
            for reference in lesson.items where reference.role == .present {
                presented[reference.item.rawValue, default: []].append(lesson.id.rawValue)
            }
        }
        let old = try oldPresentationCounts()
        let toBe: Set<String> = ["e-yam", "e-ye", "e-day", "e-da", "e-yast"]
        for (id, count) in old {
            if toBe.contains(id) {
                #expect(presented[id] == nil)
            } else {
                #expect(presented[id]?.count == count, "\(id)")
            }
        }
        #expect(Set(presented.keys).subtracting(old.keys).isEmpty)

        let polite = ["e-ho", "e-na", "e-xa", "e-mehrabani-wakray", "e-manana", "e-baxana-ghwaram"]
        for id in polite {
            #expect(presented[id] == ["l-basics-learn-polite"])
            #expect(presented[id]?.allSatisfy { !$0.contains("greetings") } == true)
        }

        var introduced: [String: [String]] = [:]
        for lesson in bundle.units.flatMap(\.lessons) where lesson.kind == .practice {
            for reference in lesson.items where reference.role == .introduce {
                introduced[reference.item.rawValue, default: []].append(lesson.id.rawValue)
            }
        }
        for id in toBe {
            #expect(bundle.items.contains { $0.id.rawValue == id })
            #expect(introduced[id] == ["l-basics-verbs"])
        }
        for id in polite {
            #expect(introduced[id] == ["l-basics-polite"])
        }
    }

    @Test func aMergedLessonStaysStartedAndMovedWordsKeepTheirProgress() throws {
        let bundle = try loadMergedCourse()
        let familyDone = try lesson("l-family-1", in: bundle)
        let familyHalf = ["e-koraney", "e-daa"]
        let greetingsDone = LessonMergeMigration.retiredIntroductions[lessonID("l-greetings-2")] ?? []
        let greetingsHalf = ["e-ho"]

        var cards: [ReviewCard] = []
        cards.append(contentsOf: reviewCards(introducedIn: familyDone, on: earlier))
        for id in familyHalf + greetingsDone.map(\.rawValue) + greetingsHalf {
            cards.append(.introduced(itemID: itemID(id), on: earlier))
        }
        let streak = StreakState(
            current: 4,
            longest: 6,
            lastActiveDay: earlier,
            freezes: 1,
            daysTowardNextFreeze: 2,
            freezeUsedDays: []
        )
        let settings = UserSettings(dailyGoal: .serious, showTransliteration: true, placementTakenDay: nil)
        let snapshot = ProgressSnapshot(
            contentVersion: bundle.contentVersion,
            cards: cards,
            lessonProgress: [
                LessonProgress(
                    lessonID: lessonID("l-family-1"),
                    source: .completed,
                    firstCompletedDay: earlier,
                    bestScorePercent: 100
                ),
                LessonProgress(
                    lessonID: lessonID("l-greetings-2"),
                    source: .completed,
                    firstCompletedDay: earlier,
                    bestScorePercent: 80
                ),
            ],
            streak: streak,
            settings: settings,
            activeSession: nil,
            completedSessions: [],
            lastReconciledContentVersion: nil,
            latestObservedDay: earlier
        )

        let outcome = LessonMergeMigration.apply(snapshot, to: bundle)
        #expect(outcome.snapshot == snapshot)
        #expect(outcome.wordsLearned == cards.count)
        #expect(outcome.snapshot.cards.count == cards.count)
        #expect(outcome.snapshot.streak == streak)
        #expect(outcome.snapshot.streak.current == 4)
        #expect(outcome.snapshot.settings.dailyGoal == .serious)
        #expect(newItemsShown(on: day, in: outcome.snapshot.cards) == newItemsShown(on: day, in: snapshot.cards))
        #expect(newItemsShown(on: day, in: outcome.snapshot.cards) == 0)

        #expect(outcome.statuses[lessonID("l-family-1")] == .done)
        #expect(outcome.statuses[lessonID("l-family-2")] == .started)
        #expect(outcome.statuses[lessonID("l-family-learn-members")] == .started)
        #expect(outcome.statuses[lessonID("l-basics-learn-polite")] == .started)
        #expect(outcome.statuses[lessonID("l-basics-polite")] == .started)
        #expect(outcome.statuses[lessonID("l-greetings-phrases-how")] == .started)
        #expect(outcome.statuses[lessonID("l-greetings-how")] == .started)

        let learned = outcome.learnedItemIDs
        #expect(learned.contains(itemID("e-mor")))
        #expect(learned.contains(itemID("e-koraney")))
        #expect(!learned.contains(itemID("e-zma")))
        #expect(!learned.contains(itemID("e-sta")))
        #expect(learned.contains(itemID("e-xa")))
        #expect(learned.contains(itemID("e-manana")))
        #expect(learned.contains(itemID("e-ho")))
        #expect(!learned.contains(itemID("e-na")))
        #expect(!learned.contains(itemID("e-mehrabani-wakray")))
        #expect(!learned.contains(itemID("e-baxana-ghwaram")))
        #expect(learned.contains(itemID("e-tsanga-ye")))
        #expect(!learned.contains(itemID("e-xoday-paman")))
    }

    private func lesson(_ raw: String, in bundle: ContentBundle) throws -> Lesson {
        let id = lessonID(raw)
        let found = bundle.units.flatMap(\.lessons).first { $0.id == id }
        return try #require(found)
    }

    private func oldPresentationCounts() throws -> [String: Int] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("presented-before-learn-merge.json")
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([String: Int].self, from: data)
        #expect(decoded.count == 192)
        return decoded
    }

    private func loadMergedCourse() throws -> ContentBundle {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try Data(contentsOf: root.appendingPathComponent("content/content.json"))
        return try JSONDecoder().decode(ContentBundle.self, from: content)
    }
}
