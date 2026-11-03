import Foundation
import Testing
import PashtoCoreTesting
@testable import PashtoCore

struct LessonAttemptTests {
    private let day = LocalDay(year: 2026, month: 11, day: 2)
    private let sessionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    @Test func aFinishedLessonSavesTheRowTheCardsAndTheStreak() async throws {
        let store = RecordingProgressStore(contentVersion: "2026.11.0")
        let settings = UserSettings(
            dailyGoal: .light,
            showTransliteration: false,
            placementTakenDay: day.adding(days: -2)
        )
        try await store.updateSettings(settings)
        let attempt = LessonAttempt(
            sessionID: sessionID,
            lessonID: lessonID("l-greetings-1"),
            startedDay: day.adding(days: -1),
            contentVersion: "2026.11.0"
        )
        let saved = try await attempt.save(
            finished(lesson: "l-greetings-1", answers: [correct("e-salam")]),
            answeredOn: day,
            in: course,
            to: store
        )

        #expect(await store.commitCount == 1)
        #expect(saved.contentVersion == "2026.11.0")
        #expect(saved.settings == settings)
        #expect(saved.activeSession == nil)
        #expect(saved.lessonProgress.map(\.lessonID) == [lessonID("l-greetings-1")])
        #expect(saved.lessonProgress[0].source == .completed)
        #expect(saved.lessonProgress[0].firstCompletedDay == day)
        #expect(saved.lessonProgress[0].bestScorePercent == 100)
        #expect(saved.cards.map(\.itemID) == [itemID("e-salam")])
        #expect(saved.cards[0].source == .lesson)
        #expect(saved.cards[0].createdDay == day)
        #expect(saved.cards[0].lastReviewedDay == day)
        #expect(saved.cards[0].dueDay > day)
        #expect(!saved.cards.contains { $0.itemID == itemID("e-sound") })
        #expect(saved.streak.lastActiveDay == day)
        #expect(saved.streak.current == 1)
        #expect(saved.completedSessions.map(\.sessionID) == [sessionID])
        #expect(saved.completedSessions[0].completedDay == day)
        #expect(saved.completedSessions[0].questionCount == 1)
        #expect(saved.completedSessions[0].firstTryCorrect == 1)
    }

    @Test func savingAgainKeepsWhatWasAlreadyStored() async throws {
        let store = RecordingProgressStore(contentVersion: "2026.11.0")
        let earlier = day.adding(days: -4)
        let salam = itemID("e-salam")
        let placementCard = ReviewCard.introduced(itemID: salam, on: earlier, source: .placement)
        let placementLesson = LessonProgress(
            lessonID: lessonID("l-greetings-1"),
            source: .placement,
            firstCompletedDay: earlier,
            bestScorePercent: 80
        )
        try await store.applyPlacement(PlacementCommit(
            lessonProgress: [placementLesson],
            cards: [placementCard],
            placementTakenDay: earlier
        ))
        let first = LessonAttempt(
            sessionID: sessionID,
            lessonID: lessonID("l-greetings-1"),
            startedDay: day,
            contentVersion: "2026.11.0"
        )
        let afterGreetings = try await first.save(
            finished(lesson: "l-greetings-1", answers: [incorrect("e-salam")]),
            answeredOn: day,
            in: course,
            to: store
        )
        #expect(afterGreetings.cards == [placementCard])
        let greetings = try #require(afterGreetings.lessonProgress.first { $0.lessonID == lessonID("l-greetings-1") })
        #expect(greetings.source == .placement)
        #expect(greetings.firstCompletedDay == earlier)
        #expect(greetings.bestScorePercent == 80)
        #expect(afterGreetings.settings.placementTakenDay == earlier)
        #expect(afterGreetings.streak.current == 1)

        let thanksID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let thanks = LessonAttempt(
            sessionID: thanksID,
            lessonID: lessonID("l-thanks-1"),
            startedDay: day,
            contentVersion: "2026.11.0"
        )
        let afterThanks = try await thanks.save(
            finished(lesson: "l-thanks-1", answers: [correct("e-manana")]),
            answeredOn: day,
            in: course,
            to: store
        )

        #expect(afterThanks.cards.contains(placementCard))
        #expect(afterThanks.lessonProgress.map(\.lessonID).sorted { $0.rawValue < $1.rawValue } == [
            lessonID("l-greetings-1"),
            lessonID("l-thanks-1"),
        ])
        let storedIDs = afterThanks.completedSessions.map(\.sessionID)
        #expect(storedIDs.contains(sessionID))
        #expect(storedIDs.contains(thanksID))
        #expect(storedIDs.count == 2)
        #expect(afterThanks.streak.current == 1)
        #expect(afterThanks.streak.lastActiveDay == day)

        let duplicate = try await first.save(
            finished(lesson: "l-greetings-1", answers: [correct("e-salam")]),
            answeredOn: day,
            in: course,
            to: store
        )
        #expect(duplicate == afterThanks)
        #expect(await store.commitCount == 3)
    }

    @Test func anUnfinishedLessonWritesNothing() async throws {
        let store = RecordingProgressStore(contentVersion: "2026.11.0")
        let attempt = LessonAttempt(
            sessionID: sessionID,
            lessonID: lessonID("l-greetings-1"),
            startedDay: day,
            contentVersion: "2026.11.0"
        )
        let open = LessonSession(
            lessonID: lessonID("l-greetings-1"),
            tasks: [choice("e-salam", isRepeat: false)],
            answers: [correct("e-salam")]
        )
        let saved = try await attempt.save(open, answeredOn: day, in: course, to: store)
        #expect(await store.commitCount == 0)
        #expect(saved.cards.isEmpty)
        #expect(saved.lessonProgress.isEmpty)
        #expect(saved.streak == StreakState.initial)
        #expect(saved.completedSessions.isEmpty)

        let other = LessonSession(
            lessonID: lessonID("l-thanks-1"),
            tasks: [],
            answers: [correct("e-manana")]
        )
        let ignored = try await attempt.save(other, answeredOn: day, in: course, to: store)
        #expect(ignored == saved)
        #expect(await store.commitCount == 0)
    }

    @Test func aFailedCommitLeavesThePreviousProgress() async throws {
        let store = RecordingProgressStore(contentVersion: "2026.11.0")
        let attempt = LessonAttempt(
            sessionID: sessionID,
            lessonID: lessonID("l-greetings-1"),
            startedDay: day,
            contentVersion: "2026.11.0"
        )
        let saved = try await attempt.save(
            finished(lesson: "l-greetings-1", answers: [correct("e-salam")]),
            answeredOn: day,
            in: course,
            to: store
        )
        await store.refuseNextCommit()
        let next = LessonAttempt(
            sessionID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            lessonID: lessonID("l-thanks-1"),
            startedDay: day,
            contentVersion: "2026.11.0"
        )
        await #expect(throws: ProgressStoreContractError.self) {
            try await next.save(
                finished(lesson: "l-thanks-1", answers: [correct("e-manana")]),
                answeredOn: day,
                in: course,
                to: store
            )
        }
        let loaded = try await store.load()
        #expect(loaded == saved)
        #expect(await store.commitCount == 1)
    }

    @Test func noAnswerUsesTheDayTheLessonStarted() async throws {
        let store = InMemoryProgressStore(contentVersion: "2026.11.0")
        let attempt = LessonAttempt(
            sessionID: sessionID,
            lessonID: lessonID("l-greetings-1"),
            startedDay: day,
            contentVersion: "2026.11.0"
        )
        let saved = try await attempt.save(
            finished(lesson: "l-greetings-1", answers: []),
            answeredOn: nil,
            in: course,
            to: store
        )
        #expect(saved.streak.lastActiveDay == day)
        #expect(saved.completedSessions[0].completedDay == day)
        #expect(saved.cards[0].createdDay == day)
    }

    private var course: ContentBundle {
        let salam = makeItem("e-salam", pashto: "سلام", translit: "salam", pronunciation: "sa-LAAM", en: "hello")
        let sound = makeItem("e-sound", pashto: "س", translit: "sin", pronunciation: "seen", en: "the letter seen")
        let thanks = makeItem("e-manana", pashto: "مننه", translit: "manana", pronunciation: "ma-NA-na", en: "thank you")
        let greetings = Lesson(
            id: lessonID("l-greetings-1"),
            title: "Hello",
            items: [
                LessonItemRef(item: salam.id, role: .introduce),
                LessonItemRef(item: sound.id, role: .soundExample, sound: "s"),
            ]
        )
        let thanksLesson = Lesson(
            id: lessonID("l-thanks-1"),
            title: "Thanks",
            items: [LessonItemRef(item: thanks.id, role: .introduce)]
        )
        return makeBundle(
            items: [salam, sound, thanks],
            units: [
                CourseUnit(
                    id: unitID("u-greetings"),
                    track: "main",
                    title: "Greetings",
                    lessons: [greetings, thanksLesson]
                ),
            ]
        )
    }

    private func finished(lesson raw: String, answers: [SessionAnswer]) -> LessonSession {
        LessonSession(lessonID: lessonID(raw), tasks: [], answers: answers)
    }

    private func correct(_ id: String) -> SessionAnswer {
        answer(id, result: .correct, isRepeat: false)
    }

    private func incorrect(_ id: String) -> SessionAnswer {
        answer(id, result: .incorrect, isRepeat: false)
    }

    private func answer(_ id: String, result: GradeResult, isRepeat: Bool) -> SessionAnswer {
        SessionAnswer(task: choice(id, isRepeat: isRepeat), answer: .choice(itemID(id)), result: result)
    }

    private func choice(_ id: String, isRepeat: Bool) -> SessionTask {
        let target = itemID(id)
        return SessionTask(
            payload: .choice(QuizTask(
                kind: .meaningPashtoToEnglish,
                targetID: target,
                prompt: id,
                usage: nil,
                options: [
                    QuizOption(itemID: target, text: id),
                    QuizOption(itemID: itemID("e-other"), text: "other"),
                ]
            )),
            isRepeat: isRepeat
        )
    }
}

/// Counts commits and can refuse the next one without touching the stored progress.
private actor RecordingProgressStore: ProgressStore {
    private let inner: InMemoryProgressStore
    private var failCommit = false
    private(set) var commitCount = 0

    init(contentVersion: String) {
        inner = InMemoryProgressStore(contentVersion: contentVersion)
    }

    func refuseNextCommit() {
        failCommit = true
    }

    func load() async throws -> ProgressSnapshot {
        try await inner.load()
    }

    func saveActiveSession(_ session: ActiveSessionSnapshot) async throws {
        try await inner.saveActiveSession(session)
    }

    func discardActiveSession() async throws {
        try await inner.discardActiveSession()
    }

    func commit(_ commit: SessionCommit) async throws {
        if failCommit {
            failCommit = false
            throw ProgressStoreContractError.writeFailed
        }
        commitCount += 1
        try await inner.commit(commit)
    }

    func applyReconciliation(
        _ changes: [ReviewCard],
        reconciledContentVersion: String?
    ) async throws {
        try await inner.applyReconciliation(changes, reconciledContentVersion: reconciledContentVersion)
    }

    func applyPlacement(_ commit: PlacementCommit) async throws {
        try await inner.applyPlacement(commit)
    }

    func updateSettings(_ settings: UserSettings) async throws {
        try await inner.updateSettings(settings)
    }

    func resetAll() async throws {
        try await inner.resetAll()
    }
}
