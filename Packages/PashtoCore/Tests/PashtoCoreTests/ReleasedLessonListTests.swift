import Foundation
import Testing
@testable import PashtoCore

struct ReleasedLessonListTests {
    private let day = LocalDay(year: 2026, month: 11, day: 2)

    @Test func theListRefreshesWhenTheSnapshotChanges() {
        let bundle = course()
        var list = ReleasedLessonList()
        list.setCourse(bundle, releasedUnitIDs: [unitID("u-home")])
        #expect(list.lessons.map(\.id) == [lessonID("l-first")])
        let built = list.rebuildCount

        let unchanged = list.snapshot
        list.snapshot = unchanged
        #expect(list.rebuildCount == built)
        #expect(list.lessons.map(\.id) == [lessonID("l-first")])

        list.snapshot = progress(seen: [], transliteration: false)
        #expect(list.rebuildCount == built + 1)
        #expect(list.lessons.map(\.id) == [lessonID("l-first")])

        let streakOnly = progress(seen: [], transliteration: false, streak: 3)
        list.snapshot = streakOnly
        #expect(list.rebuildCount == built + 1)

        list.snapshot = progress(seen: [lessonID("l-first")], transliteration: false)
        #expect(list.lessons.map(\.id) == [lessonID("l-first"), lessonID("l-second")])
        #expect(list.rebuildCount == built + 2)

        list.snapshot = progress(seen: [lessonID("l-first")], transliteration: false)
        #expect(list.rebuildCount == built + 2)

        list.snapshot = nil
        #expect(list.lessons.map(\.id) == [lessonID("l-first")])
        #expect(list.rebuildCount == built + 3)
    }

    @Test func startupDecodesTheSameBytesOnce() throws {
        let content = try JSONEncoder().encode(makeBundle(items: [makeItem()]))
        let release = Data(#"{"units":["u-greetings"],"note":"authors"}"#.utf8)
        let first = BundledCourseDecode(content: content, releaseUnits: release)
        #expect(first.decodeCount == 1)
        #expect(first.installedContentVersion == "test")
        #expect(first.load.blockingScreen == nil)

        let second = first.replacing(content: content, releaseUnits: release)
        #expect(second.decodeCount == 1)
        #expect(second == first)

        let broken = second.replacing(content: Data("[]".utf8), releaseUnits: release)
        #expect(broken.decodeCount == 2)
        #expect(broken.installedContentVersion == nil)
        #expect(broken.load == .unavailable)

        let missing = BundledCourseDecode(content: nil, releaseUnits: nil)
        let stillMissing = missing.replacing(content: nil, releaseUnits: nil)
        #expect(stillMissing.decodeCount == 1)
        #expect(stillMissing.load == .unavailable)
        #expect(stillMissing.installedContentVersion == nil)
    }

    private func course() -> ContentBundle {
        let first = [
            word("e-salam", "سلام", "hello", "sa-LAAM"),
            word("e-manana", "مننه", "thanks", "ma-NA-na"),
            word("e-obuh", "اوبه", "water", "OO-buh"),
        ]
        let second = word("e-dodai", "ډوډۍ", "bread", "DO-day")
        let early = Lesson(
            id: lessonID("l-first"),
            title: "First",
            items: first.map { LessonItemRef(item: $0.id, role: .introduce) }
        )
        let later = Lesson(
            id: lessonID("l-second"),
            title: "Second",
            items: [LessonItemRef(item: second.id, role: .introduce)]
        )
        return makeBundle(
            items: first + [second],
            units: [
                CourseUnit(id: unitID("u-home"), track: "main", title: "Home", lessons: [early, later]),
            ]
        )
    }

    private func progress(
        seen: [LessonID],
        transliteration: Bool,
        streak: Int = 0
    ) -> ProgressSnapshot {
        ProgressSnapshot(
            contentVersion: "test",
            cards: [],
            lessonProgress: seen.map {
                LessonProgress(
                    lessonID: $0,
                    source: .completed,
                    firstCompletedDay: day,
                    bestScorePercent: 100
                )
            },
            streak: StreakState(
                current: streak,
                longest: streak,
                lastActiveDay: streak == 0 ? nil : day,
                freezes: 0,
                daysTowardNextFreeze: 0,
                freezeUsedDays: []
            ),
            settings: UserSettings(
                dailyGoal: .regular,
                showTransliteration: transliteration,
                placementTakenDay: nil
            ),
            activeSession: nil,
            completedSessions: [],
            lastReconciledContentVersion: nil,
            latestObservedDay: nil
        )
    }

    private func word(_ id: String, _ pashto: String, _ en: String, _ pronunciation: String) -> ContentItem {
        makeItem(id, pashto: pashto, translit: en, pronunciation: pronunciation, en: en        )
    }
}
