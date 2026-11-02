import Foundation
import Testing
import PashtoCore

struct SessionCommitTests {
    private let dayN = LocalDay(year: 2026, month: 11, day: 2)

    @Test func finishedLessonUsesTheLastAnswerDay() async throws {
        let dayAfter = dayN.adding(days: 1)
        let active = finishedSession(started: dayN, lastAnswer: dayN, answers: [correct("e-salam")])
        #expect(canResume(active, on: dayAfter, contentVersion: "2026.11.0"))
        #expect(canResume(active, on: dayN, contentVersion: "2026.11.0"))
        #expect(!canResume(active, on: dayAfter.adding(days: 1), contentVersion: "2026.11.0"))

        let commit = try #require(sessionCommit(
            for: active,
            lesson: greetings,
            cards: [],
            lessonProgress: nil,
            streak: .initial
        ))
        #expect(commit.completed.completedDay == dayN)
        #expect(commit.streak.lastActiveDay == dayN)
        #expect(commit.cards.count == 1)
        #expect(commit.cards[0].itemID == item("e-salam"))
        #expect(commit.cards[0].createdDay == dayN)
        #expect(commit.cards[0].source == .lesson)
        #expect(commit.lessonProgress?.firstCompletedDay == dayN)

        let store = InMemoryProgressStore(contentVersion: "2026.11.0")
        try await store.saveActiveSession(active)
        let midway = try await store.load()
        #expect(midway.cards.isEmpty)
        try await store.commit(commit)
        let loaded = try await store.load()
        #expect(loaded.activeSession == nil)
        #expect(loaded.cards.map(\.createdDay) == [dayN])
        #expect(loaded.streak.lastActiveDay == dayN)
        #expect(loaded.completedSessions.map(\.completedDay) == [dayN])
    }

    @Test func lastAnswerDayWinsOverTheStartDay() throws {
        let started = dayN.adding(days: -1)
        let active = finishedSession(started: started, lastAnswer: dayN, answers: [correct("e-salam")])
        let commit = try #require(sessionCommit(
            for: active,
            lesson: greetings,
            cards: [],
            lessonProgress: nil,
            streak: .initial
        ))
        #expect(commit.completed.completedDay == dayN)
        #expect(commit.cards[0].createdDay == dayN)
        #expect(commit.streak.lastActiveDay == dayN)
    }

    @Test func noAnswerUsesTheStartDay() throws {
        let active = finishedSession(started: dayN, lastAnswer: nil, answers: [])
        let commit = try #require(sessionCommit(
            for: active,
            lesson: greetings,
            cards: [],
            lessonProgress: nil,
            streak: .initial
        ))
        #expect(commit.completed.completedDay == dayN)
        #expect(commit.cards[0].createdDay == dayN)
    }

    @Test func anUnfinishedLessonMakesNoCommit() {
        let active = ActiveSessionSnapshot(
            sessionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            kind: .lesson,
            lessonID: lesson("l-greetings-1"),
            startedDay: dayN,
            lastAnswerDay: dayN,
            contentVersion: "2026.11.0",
            lesson: LessonSession(lessonID: lesson("l-greetings-1"), tasks: [choice("e-salam")])
        )
        #expect(sessionCommit(
            for: active,
            lesson: greetings,
            cards: [],
            lessonProgress: nil,
            streak: .initial
        ) == nil)
    }

    @Test func soundExamplesAndExistingCardsAreNotCreatedAgain() throws {
        let existing = ReviewCard.introduced(itemID: item("e-salam"), on: dayN.adding(days: -3), source: .placement)
        let commit = try #require(sessionCommit(
            for: finishedSession(started: dayN, lastAnswer: dayN, answers: [correct("e-salam")]),
            lesson: greetings,
            cards: [existing],
            lessonProgress: nil,
            streak: .initial
        ))
        #expect(commit.cards.isEmpty)
    }

    @Test func aRepeatedLessonKeepsTheBestScoreAndTheFirstDay() throws {
        let firstDay = dayN.adding(days: -5)
        let existing = LessonProgress(
            lessonID: lesson("l-greetings-1"),
            source: .placement,
            firstCompletedDay: firstDay,
            bestScorePercent: 90
        )
        let answers = [correct("e-salam"), incorrect("e-salam"), retry("e-salam")]
        let commit = try #require(sessionCommit(
            for: finishedSession(started: dayN, lastAnswer: dayN, answers: answers),
            lesson: greetings,
            cards: [],
            lessonProgress: existing,
            streak: .initial
        ))
        #expect(commit.lessonProgress?.bestScorePercent == 90)
        #expect(commit.lessonProgress?.firstCompletedDay == firstDay)
        #expect(commit.lessonProgress?.source == .placement)
        #expect(commit.completed.questionCount == 2)
        #expect(commit.completed.firstTryCorrect == 1)
    }

    @Test func anInterruptedLessonContinuesAfterItIsStored() throws {
        let start = LessonSession(
            lessonID: lesson("l-greetings-1"),
            tasks: [choice("e-one"), choice("e-two")]
        )
        var direct = start
        var stored = start
        var firstRNG = SplitMix64(seed: 1)
        var storedRNG = SplitMix64(seed: 1)
        direct.submit(.choice(item("e-wrong")), using: &firstRNG)
        stored.submit(.choice(item("e-wrong")), using: &storedRNG)

        let data = try JSONEncoder().encode(stored)
        var restored = try JSONDecoder().decode(LessonSession.self, from: data)
        #expect(restored.tasks == stored.tasks)
        #expect(restored.answers == stored.answers)

        var directRNG = SplitMix64(seed: 2)
        var restoredRNG = SplitMix64(seed: 2)
        while let task = direct.current {
            let answer = correctAnswer(for: task)
            direct.submit(answer, using: &directRNG)
            restored.submit(answer, using: &restoredRNG)
        }
        #expect(restored.isComplete)
        #expect(restored.answers == direct.answers)
    }

    @Test func resumeRejectsTheWrongVersionOrContent() {
        let active = finishedSession(started: dayN, lastAnswer: dayN, answers: [])
        #expect(!canResume(active, on: dayN, contentVersion: "2026.12.0"))
        let stale = ActiveSessionSnapshot(
            sessionID: active.sessionID,
            kind: .lesson,
            lessonID: active.lessonID,
            startedDay: dayN,
            lastAnswerDay: dayN,
            contentVersion: "2026.11.0",
            payloadVersion: 2,
            lesson: active.lesson
        )
        #expect(!canResume(stale, on: dayN, contentVersion: "2026.11.0"))
        let review = ActiveSessionSnapshot(
            sessionID: active.sessionID,
            kind: .review,
            lessonID: nil,
            startedDay: dayN,
            lastAnswerDay: dayN,
            contentVersion: "2026.11.0",
            lesson: nil
        )
        #expect(!canResume(review, on: dayN, contentVersion: "2026.11.0"))
    }

    private var greetings: Lesson {
        Lesson(
            id: lesson("l-greetings-1"),
            title: "Hello",
            items: [
                LessonItemRef(item: item("e-salam"), role: .introduce),
                LessonItemRef(item: item("e-sound"), role: .soundExample, sound: "s"),
            ]
        )
    }

    private func finishedSession(
        started: LocalDay,
        lastAnswer: LocalDay?,
        answers: [SessionAnswer]
    ) -> ActiveSessionSnapshot {
        ActiveSessionSnapshot(
            sessionID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            kind: .lesson,
            lessonID: lesson("l-greetings-1"),
            startedDay: started,
            lastAnswerDay: lastAnswer,
            contentVersion: "2026.11.0",
            lesson: LessonSession(lessonID: lesson("l-greetings-1"), tasks: [], answers: answers)
        )
    }

    private func correct(_ id: String) -> SessionAnswer {
        answer(id, result: .correct, isRepeat: false)
    }

    private func incorrect(_ id: String) -> SessionAnswer {
        answer(id, result: .incorrect, isRepeat: false)
    }

    private func retry(_ id: String) -> SessionAnswer {
        answer(id, result: .correct, isRepeat: true)
    }

    private func answer(_ id: String, result: GradeResult, isRepeat: Bool) -> SessionAnswer {
        SessionAnswer(task: choice(id, isRepeat: isRepeat), answer: .choice(item(id)), result: result)
    }

    private func choice(_ id: String, isRepeat: Bool = false) -> SessionTask {
        let target = item(id)
        return SessionTask(
            payload: .choice(QuizTask(
                kind: .meaningPashtoToEnglish,
                targetID: target,
                prompt: "hello",
                usage: nil,
                options: [
                    QuizOption(itemID: target, text: "hello"),
                    QuizOption(itemID: item("e-other"), text: "other"),
                ]
            )),
            isRepeat: isRepeat
        )
    }

    private func correctAnswer(for task: SessionTask) -> QuizAnswer {
        switch task.payload {
        case .choice(let quiz):
            return .choice(quiz.targetID)
        case .matchPairs(let match):
            return .matches(match.pairs.map { MatchLink(left: $0.left.itemID, right: $0.right.itemID) })
        case .orderWords(let order):
            return .tokenOrder(Array(order.tokens.indices))
        }
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
