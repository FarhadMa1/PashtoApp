import Foundation
import Testing
import PashtoCoreTesting
@testable import PashtoCore

@MainActor
struct OpenLessonTests {
    private let zone = TimeZone(secondsFromGMT: 0)!

    @Test func theHomeLessonSavesEachAnswerAndResumesInsideTheWindow() async throws {
        let store = InMemoryProgressStore(contentVersion: "test")
        let today = clock(day: 2, hour: 10).today
        let nextDay = clock(day: 3, hour: 9).today
        let dayAfter = clock(day: 4, hour: 9).today
        #expect(nextDay == today.adding(days: 1))
        #expect(dayAfter == today.adding(days: 2))

        let lesson = OpenLesson()
        let started = try start(lesson, "l-home", progress: try await store.load(), on: today, seed: 1)
        let sessionID = try #require(lesson.attempt?.sessionID)
        var answered = started
        try submit(&answered, correct: true)
        try await lesson.saveAnswer(answered, on: today, to: store)

        let saved = try await store.load()
        #expect(saved.activeSession?.sessionID == sessionID)
        #expect(saved.activeSession?.startedDay == today)
        #expect(saved.activeSession?.lastAnswerDay == today)
        #expect(saved.activeSession?.lesson == answered)
        #expect(saved.cards.isEmpty)
        #expect(saved.lessonProgress.isEmpty)
        #expect(saved.streak == .initial)
        #expect(saved.completedSessions.isEmpty)

        lesson.leave()
        #expect(lesson.session == nil)
        let kept = try await store.load()
        #expect(kept.activeSession?.lesson == answered)

        let sameDay = try await resume(store, lessonID: "l-home", on: today)
        #expect(sameDay.attempt?.sessionID == sessionID)
        #expect(sameDay.session == answered)

        _ = try await ProgressReconciler.run(store: store, content: course, on: nextDay)
        let tomorrow = try await resume(store, lessonID: "l-home", on: nextDay)
        #expect(tomorrow.attempt?.sessionID == sessionID)
        #expect(tomorrow.attempt?.startedDay == today)
        #expect(tomorrow.session == answered)

        let dropped = try await ProgressReconciler.run(store: store, content: course, on: dayAfter)
        #expect(dropped.activeSession == nil)
        #expect(dropped.cards.isEmpty)
        #expect(dropped.streak == .initial)
        let fresh = OpenLesson()
        let again = try start(fresh, "l-home", progress: dropped, on: dayAfter, seed: 3)
        #expect(again.answers.isEmpty)
        #expect(fresh.attempt?.sessionID != sessionID)
        #expect(fresh.attempt?.startedDay == dayAfter)
    }

    @Test func aLessonThatCrossesMidnightCountsOnTheLastAnswerDay() async throws {
        let store = InMemoryProgressStore(contentVersion: "test")
        let beforeMidnight = clock(day: 2, hour: 23, minute: 50)
        let afterMidnight = clock(day: 3, hour: 0, minute: 10)
        let started = beforeMidnight.today
        let finished = afterMidnight.today
        #expect(finished == started.adding(days: 1))

        try await seed(store, lesson: "l-salam", tasks: [choice("e-salam"), choice("e-manana")], on: started)
        let lesson = OpenLesson()
        var session = try start(lesson, "l-salam", progress: try await store.load(), on: started, seed: 1)
        #expect(lesson.attempt?.startedDay == started)
        try submit(&session, correct: true)
        try await lesson.saveAnswer(session, on: started, to: store)
        let halfway = try await store.load()
        #expect(halfway.activeSession?.lastAnswerDay == started)
        #expect(halfway.cards.isEmpty)
        #expect(halfway.streak == .initial)

        try submit(&session, correct: false)
        try submit(&session, correct: true)
        #expect(session.isComplete)
        let saved = try await finish(lesson, session, on: finished, to: store)
        #expect(saved.activeSession == nil)
        #expect(saved.streak.lastActiveDay == finished)
        #expect(saved.streak.current == 1)
        #expect(saved.completedSessions.map(\.completedDay) == [finished])
        #expect(saved.lessonProgress.first?.firstCompletedDay == finished)
        #expect(saved.cards.allSatisfy { $0.createdDay == finished })
        #expect(saved.cards.map(\.itemID) == [itemID("e-salam")])
        let firstTry = saved.completedSessions[0]
        #expect(firstTry.questionCount == 2)
        #expect(firstTry.firstTryCorrect == 1)
    }

    @Test func aWrongAnswerIsKeptAndTheRepeatDoesNotRaiseTheScore() async throws {
        let store = InMemoryProgressStore(contentVersion: "test")
        let day = clock(day: 2, hour: 12).today
        try await seed(store, lesson: "l-salam", tasks: [choice("e-salam")], on: day)
        let lesson = OpenLesson()
        var session = try start(lesson, "l-salam", progress: try await store.load(), on: day, seed: 1)
        try submit(&session, correct: false)
        #expect(session.answers.map(\.result) == [.incorrect])
        #expect(session.tasks.count == 1)
        #expect(session.current?.isRepeat == true)
        try await lesson.saveAnswer(session, on: day, to: store)

        let stored = try #require(try await store.load().activeSession?.lesson)
        #expect(stored == session)
        #expect(stored.answers[0].result == .incorrect)

        try submit(&session, correct: true)
        let saved = try await finish(lesson, session, on: day, to: store)
        #expect(saved.lessonProgress[0].bestScorePercent == 0)
        #expect(saved.completedSessions[0].questionCount == 1)
        #expect(saved.completedSessions[0].firstTryCorrect == 0)
        #expect(saved.cards.map(\.itemID) == [itemID("e-salam")])
        #expect(saved.streak.current == 1)
    }

    @Test func repeatingALessonKeepsTheFirstDayTheHigherScoreAndTheCard() async throws {
        let store = InMemoryProgressStore(contentVersion: "test")
        let day = clock(day: 2, hour: 15).today
        let firstLesson = OpenLesson()
        var first = try start(firstLesson, "l-home", progress: try await store.load(), on: day, seed: 4)
        try answerAll(&first, correct: false)
        let wrong = try await finish(firstLesson, first, on: day, to: store)
        let wrongScore = try #require(wrong.lessonProgress.first?.bestScorePercent)
        #expect(wrongScore < 100)
        #expect(wrong.lessonProgress[0].firstCompletedDay == day)
        #expect(wrong.lessonProgress[0].source == .completed)
        #expect(wrong.streak.current == 1)
        let cardIDs = wrong.cards.map(\.itemID)

        let repeated = OpenLesson()
        var second = try start(repeated, "l-home", progress: wrong, on: day, seed: 8)
        #expect(second.answers.isEmpty)
        #expect(repeated.attempt?.sessionID != firstLesson.attempt?.sessionID)
        try answerAll(&second, correct: true)
        let again = try await finish(repeated, second, on: day, to: store)
        #expect(again.lessonProgress.count == 1)
        #expect(again.lessonProgress[0].firstCompletedDay == day)
        #expect(again.lessonProgress[0].source == .completed)
        #expect(again.lessonProgress[0].bestScorePercent == 100)
        #expect(again.cards == wrong.cards)
        #expect(again.cards.map(\.itemID) == cardIDs)
        #expect(again.streak == wrong.streak)
        #expect(again.completedSessions.count == 2)

        let third = OpenLesson()
        var other = try start(third, "l-other", progress: again, on: day, seed: 9)
        try answerAll(&other, correct: true)
        let both = try await finish(third, other, on: day, to: store)
        #expect(both.streak == again.streak)
        #expect(both.streak.lastActiveDay == day)
        #expect(both.lessonProgress.map(\.lessonID).contains(lessonID("l-home")))
        #expect(both.cards.contains { cardIDs.contains($0.itemID) })
    }

    @Test func aFailedSaveKeepsTheProgressAlreadyStored() async throws {
        let store = HookedStore(contentVersion: "test")
        let day = clock(day: 2, hour: 11).today
        try await seed(store, lesson: "l-salam", tasks: [choice("e-salam"), choice("e-manana")], on: day)
        let lesson = OpenLesson()
        var session = try start(lesson, "l-salam", progress: try await store.load(), on: day, seed: 1)
        try submit(&session, correct: true)
        try await lesson.saveAnswer(session, on: day, to: store)
        let kept = try await store.load()
        #expect(kept.activeSession?.lesson?.answers.count == 1)

        try submit(&session, correct: false)
        await store.failNextSave()
        await #expect(throws: ProgressStoreContractError.self) {
            try await lesson.saveAnswer(session, on: day, to: store)
        }
        #expect(screenAfterFailedLessonSave() == .storageError)
        let loaded = try await store.load()
        #expect(loaded == kept)
        #expect(lesson.session == session)
        #expect(loaded.cards.isEmpty)
        #expect(loaded.streak == .initial)
    }

    @Test func aFailedFinishLeavesTheLessonForTheNextLaunch() async throws {
        let store = HookedStore(contentVersion: "test")
        let day = clock(day: 2, hour: 11).today
        let later = clock(day: 5, hour: 8).today
        try await seed(store, lesson: "l-salam", tasks: [choice("e-salam")], on: day)
        let earlier = OpenLesson()
        var done = try start(earlier, "l-salam", progress: try await store.load(), on: day, seed: 1)
        try submit(&done, correct: true)
        let prior = try await finish(earlier, done, on: day, to: store)
        #expect(prior.cards.map(\.itemID) == [itemID("e-salam")])

        try await seed(store, lesson: "l-other", tasks: [choice("e-book")], on: day, sessionID: otherSession)
        let lesson = OpenLesson()
        var session = try start(lesson, "l-other", progress: try await store.load(), on: day, seed: 2)
        try submit(&session, correct: false)
        try submit(&session, correct: true)
        #expect(session.isComplete)
        await store.failNextCommit()
        await #expect(throws: ProgressStoreContractError.self) {
            try await finish(lesson, session, on: day, to: store)
        }

        let held = try await store.load()
        #expect(held.lessonProgress == prior.lessonProgress)
        #expect(held.cards == prior.cards)
        #expect(held.streak == prior.streak)
        #expect(held.completedSessions == prior.completedSessions)
        #expect(held.activeSession?.sessionID == otherSession)
        #expect(held.activeSession?.lesson?.isComplete == true)

        let committed = try await ProgressReconciler.run(store: store, content: course, on: later)
        #expect(committed.activeSession == nil)
        #expect(committed.lessonProgress.map(\.lessonID).contains(lessonID("l-salam")))
        #expect(committed.lessonProgress.map(\.lessonID).contains(lessonID("l-other")))
        #expect(committed.cards.contains { $0.itemID == itemID("e-salam") })
        #expect(committed.cards.contains { $0.itemID == itemID("e-book") })
        #expect(committed.streak.lastActiveDay == day)
        #expect(committed.completedSessions.count == 2)
    }

    @Test func aLessonOpenedWhileAnotherFinishesStaysOpen() async throws {
        let pause = CommitPause()
        await pause.arm()
        let store = HookedStore(contentVersion: "test", pause: pause)
        let day = clock(day: 2, hour: 16).today
        let lesson = OpenLesson()
        var session = try start(lesson, "l-home", progress: .empty(contentVersion: "test"), on: day, seed: 1)
        let finishedID = try #require(lesson.attempt?.sessionID)
        let attempt = try #require(lesson.attempt)
        try answerAll(&session, correct: true)

        let finishing = Task { @MainActor in
            try await lesson.saveFinished(
                attempt: attempt,
                session: session,
                on: day,
                in: course,
                to: store
            )
        }
        await pause.waitUntilPaused()
        let other = try start(lesson, "l-other", progress: .empty(contentVersion: "test"), on: day, seed: 2)
        #expect(other.lessonID == lessonID("l-other"))
        #expect(lesson.attempt?.sessionID != finishedID)
        await pause.release()

        let saved = try await finishing.value
        lesson.leaveIfStill(finishedID)
        #expect(lesson.attempt?.lessonID == lessonID("l-other"))
        #expect(lesson.session?.lessonID == lessonID("l-other"))
        #expect(lesson.session?.answers.isEmpty == true)
        #expect(saved.lessonProgress.map(\.lessonID) == [lessonID("l-home")])
        #expect(saved.activeSession == nil)
    }

    @Test func theInjectedClockSuppliesTheDay() {
        let boxed = clock(day: 2, hour: 23, minute: 30)
        #expect(boxed.today == LocalDay(year: 2026, month: 11, day: 2))
        let next = DayClock(
            provider: DateProviderBox(FixedDateProvider(now: instant(day: 3, hour: 0, minute: 5))),
            timeZone: zone
        )
        #expect(next.today == LocalDay(year: 2026, month: 11, day: 3))
        #expect(next.today == boxed.today.adding(days: 1))
    }

    private var course: ContentBundle {
        let home = words([
            ("e-door", "در", "door"),
            ("e-fever", "تب", "fever"),
            ("e-on", "بر", "on"),
            ("e-water", "اوبه", "water"),
        ])
        let other = words([
            ("e-book", "کتاب", "book"),
            ("e-pen", "قلم", "pen"),
            ("e-house", "کور", "house"),
            ("e-bread", "ډوډۍ", "bread"),
        ])
        let greetings = words([
            ("e-salam", "سلام", "hello"),
            ("e-manana", "مننه", "thanks"),
        ])
        return makeBundle(
            items: home + other + greetings,
            units: [
                CourseUnit(
                    id: unitID("u-home"),
                    track: "main",
                    title: "Home",
                    lessons: [
                        introduced("l-home", "Home", home),
                        introduced("l-other", "Other", other),
                        introduced("l-salam", "Hello", [greetings[0]]),
                    ]
                ),
            ]
        )
    }

    private func start(
        _ lesson: OpenLesson,
        _ id: String,
        progress: ProgressSnapshot,
        on day: LocalDay,
        seed: UInt64
    ) throws -> LessonSession {
        var rng = SplitMix64(seed: seed)
        lesson.start(
            lessonID: lessonID(id),
            in: course,
            progress: progress,
            releasedUnitIDs: [unitID("u-home")],
            showsPronunciation: true,
            voiceOver: false,
            on: day,
            using: &rng
        )
        let session = try #require(lesson.session)
        #expect(!session.tasks.isEmpty)
        return session
    }

    private func resume(
        _ store: any ProgressStore,
        lessonID id: String,
        on day: LocalDay
    ) async throws -> OpenLesson {
        let lesson = OpenLesson()
        _ = try start(lesson, id, progress: try await store.load(), on: day, seed: 5)
        return lesson
    }

    private func finish(
        _ lesson: OpenLesson,
        _ session: LessonSession,
        on day: LocalDay,
        to store: any ProgressStore
    ) async throws -> ProgressSnapshot {
        let attempt = try #require(lesson.attempt)
        return try await lesson.saveFinished(
            attempt: attempt,
            session: session,
            on: day,
            in: course,
            to: store
        )
    }

    private func seed(
        _ store: any ProgressStore,
        lesson raw: String,
        tasks: [SessionTask],
        on day: LocalDay,
        sessionID: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    ) async throws {
        let attempt = LessonAttempt(
            sessionID: sessionID,
            lessonID: lessonID(raw),
            startedDay: day,
            contentVersion: course.contentVersion
        )
        let session = LessonSession(lessonID: lessonID(raw), tasks: tasks)
        try await attempt.saveActive(session, answeredOn: nil, to: store)
    }

    private func submit(_ session: inout LessonSession, correct: Bool) throws {
        let task = try #require(session.current)
        var rng = SplitMix64(seed: 19)
        _ = session.submit(correct ? correctAnswer(task) : wrongAnswer(task), using: &rng)
    }

    private func answerAll(_ session: inout LessonSession, correct: Bool) throws {
        var steps = 0
        while session.current != nil {
            try submit(&session, correct: correct)
            steps += 1
            #expect(steps < 80)
        }
    }

    private func correctAnswer(_ task: SessionTask) -> QuizAnswer {
        switch task.payload {
        case .choice(let quiz):
            return .choice(quiz.targetID)
        case .matchPairs(let match):
            return .matches(match.pairs.map { MatchLink(left: $0.left.itemID, right: $0.right.itemID) })
        case .orderWords(let order):
            return .tokenOrder(Array(0..<order.tokens.count))
        }
    }

    private func wrongAnswer(_ task: SessionTask) -> QuizAnswer {
        switch task.payload {
        case .choice(let quiz):
            let wrong = quiz.options.first { $0.itemID != quiz.targetID }?.itemID ?? itemID("e-nope")
            return .choice(wrong)
        case .matchPairs, .orderWords:
            return .choice(itemID("e-nope"))
        }
    }

    private func choice(_ id: String) -> SessionTask {
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
            ))
        )
    }

    private func words(_ rows: [(String, String, String)]) -> [ContentItem] {
        rows.map { makeItem($0.0, pashto: $0.1, translit: $0.2, pronunciation: $0.2, en: $0.2) }
    }

    private func introduced(_ id: String, _ title: String, _ items: [ContentItem]) -> Lesson {
        Lesson(
            id: lessonID(id),
            title: title,
            items: items.map { LessonItemRef(item: $0.id, role: .introduce) }
        )
    }

    private func clock(day: Int, hour: Int, minute: Int = 0) -> DayClock<DateProviderBox> {
        DayClock(provider: DateProviderBox(FixedDateProvider(now: instant(day: day, hour: hour, minute: minute))), timeZone: zone)
    }

    private func instant(day: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 11
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        guard let date = calendar.date(from: parts) else {
            preconditionFailure("2026-11-\(day) \(hour):\(minute) is not a time")
        }
        return date
    }

    private var otherSession: UUID {
        UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    }
}

/// Pauses inside `commit` so a test can open another lesson before the finish returns.
private actor CommitPause {
    private var armed = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var hold: CheckedContinuation<Void, Never>?

    func arm() {
        armed = true
    }

    func waitUntilPaused() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if hold != nil {
                continuation.resume()
                return
            }
            waiter = continuation
        }
    }

    func pauseIfArmed() async {
        guard armed else { return }
        armed = false
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            hold = continuation
            waiter?.resume()
            waiter = nil
        }
    }

    func release() {
        hold?.resume()
        hold = nil
    }
}

/// An in-memory store that can fail one save or one commit, and can pause inside the commit.
private actor HookedStore: ProgressStore {
    private let inner: InMemoryProgressStore
    private var savesToFail = 0
    private var commitsToFail = 0
    private let pause: CommitPause?

    init(contentVersion: String, pause: CommitPause? = nil) {
        inner = InMemoryProgressStore(contentVersion: contentVersion)
        self.pause = pause
    }

    func failNextSave() {
        savesToFail += 1
    }

    func failNextCommit() {
        commitsToFail += 1
    }

    func load() async throws -> ProgressSnapshot {
        try await inner.load()
    }

    func saveActiveSession(_ session: ActiveSessionSnapshot) async throws {
        if savesToFail > 0 {
            savesToFail -= 1
            throw ProgressStoreContractError.writeFailed
        }
        try await inner.saveActiveSession(session)
    }

    func discardActiveSession() async throws {
        try await inner.discardActiveSession()
    }

    func commit(_ commit: SessionCommit) async throws {
        if commitsToFail > 0 {
            commitsToFail -= 1
            throw ProgressStoreContractError.writeFailed
        }
        await pause?.pauseIfArmed()
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
