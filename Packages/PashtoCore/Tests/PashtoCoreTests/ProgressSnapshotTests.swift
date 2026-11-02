import Foundation
import Testing
import PashtoCore

struct ProgressSnapshotTests {
    private let today = LocalDay(year: 2026, month: 11, day: 2)
    private let yesterday = LocalDay(year: 2026, month: 11, day: 1)

    @Test func newWordsShownTodayCountOnlyLessonCardsCreatedThatDay() {
        let todayCard = ReviewCard.introduced(itemID: item("e-today"), on: today)
        let paused = ReviewCard(
            itemID: item("e-paused"),
            easeFactor: 2.5,
            intervalDays: 0,
            repetitions: 0,
            lapses: 0,
            dueDay: today,
            lastReviewedDay: nil,
            createdDay: today,
            state: .paused,
            source: .lesson
        )
        let old = ReviewCard.introduced(itemID: item("e-old"), on: yesterday)
        let placement = ReviewCard.introduced(itemID: item("e-place"), on: today, source: .placement)
        let stored = ProgressSnapshot(
            contentVersion: "2026.11.0",
            cards: [todayCard, paused, old, placement, todayCard],
            lessonProgress: [
                LessonProgress(
                    lessonID: lesson("l-done"),
                    source: .completed,
                    firstCompletedDay: yesterday,
                    bestScorePercent: 100
                ),
                LessonProgress(
                    lessonID: lesson("l-skip"),
                    source: .placement,
                    firstCompletedDay: yesterday,
                    bestScorePercent: 80
                ),
            ],
            streak: .initial,
            settings: .initial,
            activeSession: nil,
            completedSessions: [],
            lastReconciledContentVersion: nil,
            latestObservedDay: nil
        )

        #expect(newItemsShown(on: today, in: stored.cards) == 2)
        let progress = pathProgress(stored, on: today)
        #expect(progress.newItemsShownToday == 2)
        #expect(progress.finishedLessonIDs == [lesson("l-done"), lesson("l-skip")])
        #expect(progress.cards.count == 5)
        #expect(newItemsShown(on: yesterday, in: stored.cards) == 1)
    }

    @Test func snapshotVersionOneRoundTrips() throws {
        let decoded = try JSONDecoder().decode(ProgressSnapshot.self, from: fixtureData("progress-snapshot-v1.json"))
        #expect(decoded == goldenSnapshot)
        let again = try JSONDecoder().decode(ProgressSnapshot.self, from: JSONEncoder().encode(decoded))
        #expect(again == decoded)
    }

    @Test func aNewerSnapshotVersionIsRejected() {
        #expect(throws: ProgressSnapshotError.newerVersion(2)) {
            try JSONDecoder().decode(ProgressSnapshot.self, from: Data(#"{"snapshotVersion":2}"#.utf8))
        }
    }

    @Test func anOlderSnapshotVersionIsRejected() {
        #expect(throws: ProgressSnapshotError.unsupportedVersion(0)) {
            try JSONDecoder().decode(ProgressSnapshot.self, from: Data(#"{"snapshotVersion":0}"#.utf8))
        }
    }

    @Test func anActiveSessionRoundTripsThroughTheSnapshot() throws {
        let target = item("e-salam")
        let task = SessionTask(
            payload: .choice(QuizTask(
                kind: .meaningPashtoToEnglish,
                targetID: target,
                prompt: "hello",
                usage: nil,
                options: [QuizOption(itemID: target, text: "hello")]
            )),
            isRepeat: false
        )
        let session = LessonSession(
            lessonID: lesson("l-greetings-1"),
            tasks: [task],
            answers: [SessionAnswer(task: task, answer: .choice(target), result: .correct)]
        )
        let active = ActiveSessionSnapshot(
            sessionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            kind: .lesson,
            lessonID: lesson("l-greetings-1"),
            startedDay: yesterday,
            lastAnswerDay: yesterday,
            contentVersion: "2026.11.0",
            lesson: session
        )
        let stored = ProgressSnapshot(
            contentVersion: "2026.11.0",
            cards: [],
            lessonProgress: [],
            streak: .initial,
            settings: .initial,
            activeSession: active,
            completedSessions: [],
            lastReconciledContentVersion: nil,
            latestObservedDay: nil
        )
        let decoded = try JSONDecoder().decode(ProgressSnapshot.self, from: JSONEncoder().encode(stored))
        #expect(decoded == stored)
        #expect(canResume(try #require(decoded.activeSession), on: today, contentVersion: "2026.11.0"))
    }

    private var goldenSnapshot: ProgressSnapshot {
        ProgressSnapshot(
            contentVersion: "2026.11.0",
            cards: [
                ReviewCard(
                    itemID: item("e-salam"),
                    easeFactor: 2.5,
                    intervalDays: 1,
                    repetitions: 1,
                    lapses: 0,
                    dueDay: today,
                    lastReviewedDay: yesterday,
                    createdDay: yesterday,
                    state: .active,
                    source: .lesson
                ),
            ],
            lessonProgress: [
                LessonProgress(
                    lessonID: lesson("l-greetings-1"),
                    source: .completed,
                    firstCompletedDay: yesterday,
                    bestScorePercent: 80
                ),
            ],
            streak: StreakState(
                current: 1,
                longest: 1,
                lastActiveDay: yesterday,
                freezes: 0,
                daysTowardNextFreeze: 1,
                freezeUsedDays: []
            ),
            settings: .initial,
            activeSession: nil,
            completedSessions: [
                CompletedSession(
                    sessionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    kind: .lesson,
                    lessonID: lesson("l-greetings-1"),
                    completedDay: yesterday,
                    questionCount: 5,
                    firstTryCorrect: 4
                ),
            ],
            lastReconciledContentVersion: nil,
            latestObservedDay: nil
        )
    }

    private func item(_ raw: String) -> ItemID {
        guard let id = ItemID(rawValue: raw) else {
            preconditionFailure("Item id \(raw) is not valid")
        }
        return id
    }

    private func lesson(_ raw: String) -> LessonID {
        guard let id = LessonID(rawValue: raw) else {
            preconditionFailure("Lesson id \(raw) is not valid")
        }
        return id
    }
}

private func fixtureData(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(name)
    return try Data(contentsOf: url)
}
