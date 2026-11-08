import Foundation
import Observation
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
        await saved(lesson, answered, on: today, to: store)

        let saved = try await store.load()
        #expect(saved.activeSession?.sessionID == sessionID)
        #expect(saved.activeSession?.startedDay == today)
        #expect(saved.activeSession?.lastAnswerDay == today)
        #expect(saved.activeSession?.lesson == answered)
        #expect(saved.cards.isEmpty)
        #expect(saved.lessonProgress.isEmpty)
        #expect(saved.streak == .initial)
        #expect(saved.completedSessions.isEmpty)

        lesson.endLesson()
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
        await saved(lesson, session, on: started, to: store)
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

    @Test func theLastAnswerIsStoredBeforeTheCelebrationIsDismissed() async throws {
        let store = InMemoryProgressStore(contentVersion: "test")
        let day = clock(day: 2, hour: 18).today
        try await seed(store, lesson: "l-salam", tasks: [choice("e-salam"), choice("e-manana")], on: day)
        let lesson = OpenLesson()
        var session = try start(lesson, "l-salam", progress: try await store.load(), on: day, seed: 1)
        try submit(&session, correct: true)
        await saved(lesson, session, on: day, to: store)
        let halfway = try await store.load()
        #expect(halfway.activeSession?.lesson?.answers.count == 1)
        #expect(halfway.lessonProgress.isEmpty)

        try submit(&session, correct: true)
        #expect(session.isComplete)
        lesson.showFinishedSession(session)
        #expect(lesson.session?.current == nil)
        #expect(lesson.session?.isComplete == true)

        let stored = try await lesson.finishLesson(session, on: day, in: course, to: store)
        #expect(stored.activeSession == nil)
        #expect(stored.completedSessions.map(\.questionCount) == [2])
        #expect(stored.lessonProgress.map(\.lessonID) == [lessonID("l-salam")])
        #expect(lesson.session?.isComplete == true)

        lesson.endLesson()
        let afterContinue = try await store.load()
        #expect(afterContinue.activeSession == nil)
        #expect(afterContinue.completedSessions.map(\.completedDay) == [day])
        #expect(afterContinue.lessonProgress.map(\.lessonID) == [lessonID("l-salam")])
        #expect(afterContinue.streak.lastActiveDay == day)
    }

    @Test func aFinishAt2359CountsOnThatDayWhenContinueIsTheNextDay() async throws {
        let store = InMemoryProgressStore(contentVersion: "test")
        let answerDay = clock(day: 2, hour: 23, minute: 59).today
        let continueDay = clock(day: 3, hour: 0, minute: 1).today
        #expect(continueDay == answerDay.adding(days: 1))

        try await seed(store, lesson: "l-salam", tasks: [choice("e-salam")], on: answerDay)
        let lesson = OpenLesson()
        var session = try start(lesson, "l-salam", progress: try await store.load(), on: answerDay, seed: 1)
        try submit(&session, correct: true)
        #expect(session.isComplete)
        let stored = try await lesson.finishLesson(session, on: answerDay, in: course, to: store)
        #expect(stored.streak.lastActiveDay == answerDay)
        #expect(stored.streak.current == 1)
        #expect(stored.completedSessions.map(\.completedDay) == [answerDay])
        #expect(stored.lessonProgress.first?.firstCompletedDay == answerDay)
        #expect(stored.cards.allSatisfy { $0.createdDay == answerDay })
        #expect(stored.streak.lastActiveDay != continueDay)

        lesson.endLesson()
        let afterContinue = try await store.load()
        #expect(afterContinue.streak.lastActiveDay == answerDay)
        #expect(afterContinue.completedSessions.map(\.completedDay) == [answerDay])
        #expect(afterContinue.cards.allSatisfy { $0.createdDay == answerDay })
        #expect(afterContinue.lessonProgress.first?.firstCompletedDay == answerDay)
    }

    @Test func leavingOnTheCelebrationLeavesTheLessonFinished() async throws {
        let store = InMemoryProgressStore(contentVersion: "test")
        let day = clock(day: 2, hour: 21).today
        try await seed(store, lesson: "l-salam", tasks: [choice("e-salam")], on: day)
        let lesson = OpenLesson()
        var session = try start(lesson, "l-salam", progress: try await store.load(), on: day, seed: 1)
        try submit(&session, correct: true)
        let stored = try await lesson.finishLesson(session, on: day, in: course, to: store)
        #expect(lesson.session != nil)
        #expect(stored.activeSession == nil)
        #expect(stored.lessonProgress.map(\.lessonID) == [lessonID("l-salam")])

        let relaunch = OpenLesson()
        let progress = try await store.load()
        #expect(relaunch.session == nil)
        #expect(progress.activeSession == nil)
        #expect(progress.lessonProgress.map(\.lessonID) == [lessonID("l-salam")])
        #expect(progress.streak.current == 1)
        #expect(progress.completedSessions.map(\.completedDay) == [day])
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
        await saved(lesson, session, on: day, to: store)

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

    @Test func aFailedAnswerSaveKeepsTheQuizAndTheNextSaveWritesItAll() async throws {
        let store = HookedStore(contentVersion: "test")
        let day = clock(day: 2, hour: 11).today
        try await seed(store, lesson: "l-salam", tasks: [choice("e-salam"), choice("e-manana")], on: day)
        let lesson = OpenLesson()
        var session = try start(lesson, "l-salam", progress: try await store.load(), on: day, seed: 1)
        try submit(&session, correct: true)
        await saved(lesson, session, on: day, to: store)
        let kept = try await store.load()
        #expect(kept.activeSession?.lesson?.answers.count == 1)

        try submit(&session, correct: false)
        let shown = session.current
        await store.failNextSave()
        await saved(lesson, session, on: day, to: store)
        #expect(lesson.hasUnsavedAnswers)
        #expect(lesson.canRetryFailedFinish == false)
        #expect(storageErrorActions(for: .lessonSaveFailed).showsStartOver == false)
        let loaded = try await store.load()
        #expect(loaded == kept)
        #expect(lesson.session == session)
        #expect(lesson.session?.current == shown)
        #expect(loaded.cards.isEmpty)
        #expect(loaded.streak == .initial)

        lesson.endLesson()
        #expect(lesson.session == nil)
        let continued = try start(lesson, "l-salam", progress: loaded, on: day, seed: 4)
        #expect(continued.answers == session.answers)

        try submit(&session, correct: true)
        await saved(lesson, session, on: day, to: store)
        #expect(lesson.hasUnsavedAnswers == false)
        let written = try await store.load()
        #expect(written.activeSession?.lesson?.answers.count == session.answers.count)
        #expect(written.activeSession?.lesson == session)
        #expect(written.cards.isEmpty)
    }

    @Test func aBackgroundRetryWritesTheAnswerTheQuizKept() async throws {
        let store = HookedStore(contentVersion: "test")
        let day = clock(day: 2, hour: 11).today
        let lesson = OpenLesson()
        var session = try start(lesson, "l-home", progress: try await store.load(), on: day, seed: 1)
        try submit(&session, correct: true)
        await store.failNextSave()
        await saved(lesson, session, on: day, to: store)
        #expect(lesson.hasUnsavedAnswers)
        #expect(try await store.load().activeSession == nil)

        lesson.retryUnsavedAnswers(to: store)
        await lesson.waitUntilSavesFinish()
        #expect(lesson.hasUnsavedAnswers == false)
        #expect(try await store.load().activeSession?.lesson == session)
        #expect(lesson.session == session)
    }

    @Test func aFailedFinishKeepsTheAnswersAndTryAgainWritesThem() async throws {
        let store = HookedStore(contentVersion: "test")
        let day = clock(day: 2, hour: 11).today
        let lesson = OpenLesson()
        var session = try start(lesson, "l-home", progress: try await store.load(), on: day, seed: 1)
        try answerAll(&session, correct: true)
        #expect(session.isComplete)
        let answers = session.answers

        await store.failNextSave()
        await #expect(throws: ProgressStoreContractError.self) {
            try await lesson.finishLesson(session, on: day, in: course, to: store)
        }
        #expect(lesson.session?.answers == answers)
        #expect(lesson.canRetryFailedFinish)
        #expect(screenAfterFailedLessonSave() == .storageError)
        #expect(storageErrorActions(for: .lessonSaveFailed).retriesLessonSave)
        #expect(try await store.load().lessonProgress.isEmpty)

        await store.failNextSave()
        await #expect(throws: ProgressStoreContractError.self) {
            try await lesson.retryFailedFinish(in: course, to: store)
        }
        #expect(lesson.session?.answers == answers)
        #expect(lesson.canRetryFailedFinish)

        let saved = try await lesson.retryFailedFinish(in: course, to: store)
        #expect(saved.lessonProgress.map(\.lessonID) == [lessonID("l-home")])
        #expect(saved.activeSession == nil)
        #expect(lesson.session?.answers == answers)
        #expect(lesson.canRetryFailedFinish == false)
        lesson.endLesson()
        #expect(lesson.session == nil)
    }

    @Test func aFailedFinishDoesNotLetAnOlderSnapshotReplaceTheSession() async throws {
        let store = HookedStore(contentVersion: "test")
        let day = clock(day: 2, hour: 11).today
        let lesson = OpenLesson()
        var session = try start(lesson, "l-home", progress: try await store.load(), on: day, seed: 1)
        try submit(&session, correct: true)
        await store.failNextSave()
        await saved(lesson, session, on: day, to: store)
        #expect(lesson.hasUnsavedAnswers)
        #expect(try await store.load().activeSession == nil)
        let partial = session.answers.count

        try answerAll(&session, correct: true)
        #expect(session.isComplete)
        let complete = session.answers.count
        #expect(complete > partial)

        await store.failNextCommit()
        await #expect(throws: ProgressStoreContractError.self) {
            try await lesson.finishLesson(session, on: day, in: course, to: store)
        }
        let held = try await store.load()
        #expect(held.activeSession?.lesson?.answers.count == complete)
        #expect(held.lessonProgress.isEmpty)
        #expect(lesson.hasUnsavedAnswers == false)
        #expect(lesson.canRetryFailedFinish)
        let writesBeforeRetry = await store.savedAnswerCounts

        lesson.retryUnsavedAnswers(to: store)
        await lesson.waitUntilSavesFinish()

        let after = try await store.load()
        #expect(after.activeSession?.lesson?.answers.count == complete)
        #expect(after.activeSession?.lesson?.answers.count != partial)
        #expect(await store.savedAnswerCounts == writesBeforeRetry)
        #expect(lesson.canRetryFailedFinish)
        #expect(lesson.session?.answers.count == complete)
    }

    @Test func aRetryDuringFinishDoesNotRestoreTheLesson() async throws {
        let pause = CommitPause()
        await pause.arm()
        let store = HookedStore(contentVersion: "test", savePause: pause)
        let day = clock(day: 2, hour: 11).today
        let lesson = OpenLesson()
        var session = try start(lesson, "l-home", progress: try await store.load(), on: day, seed: 1)
        try submit(&session, correct: true)
        await store.failNextSave()
        await saved(lesson, session, on: day, to: store)
        #expect(lesson.hasUnsavedAnswers)
        #expect(try await store.load().activeSession == nil)

        try answerAll(&session, correct: true)
        let finishing = Task { @MainActor in
            try await lesson.finishLesson(session, on: day, in: course, to: store)
        }
        await pause.waitUntilPaused()
        lesson.retryUnsavedAnswers(to: store)
        await pause.release()

        let saved = try await finishing.value
        await lesson.waitUntilSavesFinish()
        #expect(saved.activeSession == nil)
        #expect(saved.lessonProgress.map(\.lessonID) == [lessonID("l-home")])
        let stored = try await store.load()
        #expect(stored.activeSession == nil)
        #expect(stored.lessonProgress.map(\.lessonID) == [lessonID("l-home")])
    }

    @Test func anOlderAnswerCannotOverwriteANewerOne() async throws {
        let store = HookedStore(contentVersion: "test")
        let day = clock(day: 2, hour: 16).today
        let lesson = OpenLesson()
        var session = try start(lesson, "l-home", progress: try await store.load(), on: day, seed: 2)
        try submit(&session, correct: true)
        lesson.saveAnswer(session, on: day, to: store)
        try submit(&session, correct: true)
        lesson.saveAnswer(session, on: day, to: store)
        await lesson.waitUntilSavesFinish()

        let stored = try await store.load()
        #expect(stored.activeSession?.lesson?.answers.count == 2)
        #expect(stored.activeSession?.lesson == session)
        #expect(await store.activeSaveCount == 1)

        let pause = CommitPause()
        await pause.arm()
        let slowed = HookedStore(contentVersion: "test", savePause: pause)
        let resumed = OpenLesson()
        var older = try start(resumed, "l-home", progress: try await slowed.load(), on: day, seed: 3)
        try submit(&older, correct: true)
        resumed.saveAnswer(older, on: day, to: slowed)
        await pause.waitUntilPaused()
        try submit(&older, correct: true)
        resumed.saveAnswer(older, on: day, to: slowed)
        await pause.release()
        await resumed.waitUntilSavesFinish()

        let landed = try await slowed.load()
        #expect(landed.activeSession?.lesson == older)
        #expect(landed.activeSession?.lesson?.answers.count == 2)
        #expect(await slowed.savedAnswerCounts == [1, 2])
    }

    @Test func aSecondTapWhileALessonIsOpeningIsIgnored() async {
        let pause = CommitPause()
        await pause.arm()
        let opening = LessonOpening()
        let first = Task { @MainActor in
            #expect(opening.begin())
            defer { opening.end() }
            await pause.pauseIfArmed()
        }
        await pause.waitUntilPaused()
        let second = await MainActor.run { opening.begin() }
        #expect(second == false)
        #expect(await MainActor.run { opening.isOpening })
        await pause.release()
        await first.value
        let next = await MainActor.run { opening.begin() }
        #expect(next)
        #expect(await MainActor.run { opening.isOpening })
        await MainActor.run { opening.end() }
        #expect(await MainActor.run { opening.isOpening } == false)
    }

    @Test func theQuizAppearsAfterStartAndDisappearsAfterEndAndAnAnswerChangesIt() async throws {
        let host = QuizHost()
        let day = clock(day: 2, hour: 10).today
        let progress = try await InMemoryProgressStore(contentVersion: "test").load()
        #expect(host.quiz == nil)

        let opened = ChangeFlag()
        withObservationTracking {
            _ = host.quiz
        } onChange: {
            opened.fired = true
        }
        var session = try start(host.lesson, "l-home", progress: progress, on: day, seed: 1)
        #expect(host.quiz != nil)
        #expect(opened.fired)

        let closed = ChangeFlag()
        withObservationTracking {
            _ = host.quiz
        } onChange: {
            closed.fired = true
        }
        host.lesson.endLesson()
        #expect(host.quiz == nil)
        #expect(closed.fired)

        session = try start(host.lesson, "l-home", progress: progress, on: day, seed: 1)
        let shown = host.quiz?.current
        let answered = ChangeFlag()
        withObservationTracking {
            _ = host.quiz?.current
            _ = host.quiz?.answers
        } onChange: {
            answered.fired = true
        }
        try submit(&session, correct: true)
        _ = host.lesson.answerToSave(session, on: day)
        #expect(answered.fired)
        #expect(host.quiz?.answers.count == 1)
        #expect(host.quiz?.current != shown)
    }

    @Test func voiceOverRestartsALessonThatStillHasALetterQuestion() async throws {
        let store = InMemoryProgressStore(contentVersion: "test")
        let day = clock(day: 2, hour: 9).today
        let sessionID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        try await seed(
            store,
            lesson: "l-home",
            tasks: [letterTask("e-door"), choice("e-fever")],
            on: day,
            sessionID: sessionID
        )
        let blocked = OpenLesson()
        let fresh = try start(
            blocked,
            "l-home",
            progress: try await store.load(),
            on: day,
            seed: 6,
            voiceOver: true
        )
        #expect(blocked.attempt?.sessionID != sessionID)
        #expect(fresh.answers.isEmpty)
        #expect(fresh.tasks.contains { $0.kind == .findLetter } == false)

        let allowed = OpenLesson()
        let restarted = try start(
            allowed,
            "l-home",
            progress: try await store.load(),
            on: day,
            seed: 7,
            voiceOver: false
        )
        #expect(allowed.attempt?.sessionID != sessionID)
        #expect(restarted.answers.isEmpty)
        #expect(restarted.tasks.contains { $0.kind == .findLetter } == false)

        let meaningID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        try await seed(store, lesson: "l-home", tasks: [choice("e-door")], on: day, sessionID: meaningID)
        let meaning = OpenLesson()
        _ = try start(
            meaning,
            "l-home",
            progress: try await store.load(),
            on: day,
            seed: 8,
            voiceOver: true
        )
        #expect(meaning.attempt?.sessionID == meaningID)
        #expect(meaning.session?.tasks.count == 1)
        #expect(meaning.session?.answers.isEmpty == true)
    }

    @Test func aResumedLessonKeepsThePronunciationItStartedWith() async throws {
        let store = InMemoryProgressStore(contentVersion: "test")
        let day = clock(day: 2, hour: 9).today
        try await seed(
            store,
            lesson: "l-salam",
            tasks: [choice("e-salam")],
            on: day,
            showsPronunciation: false
        )
        let lesson = OpenLesson()
        let resumed = try start(
            lesson,
            "l-salam",
            progress: try await store.load(),
            on: day,
            seed: 1,
            showsPronunciation: true
        )
        #expect(resumed.showsPronunciation == false)
        #expect(lesson.attempt?.startedDay == day)
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
        lesson.endLessonIfStill(finishedID)
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
        seed: UInt64,
        voiceOver: Bool = false,
        showsPronunciation: Bool = true
    ) throws -> LessonSession {
        var rng = SplitMix64(seed: seed)
        lesson.startLesson(
            lessonID: lessonID(id),
            in: course,
            progress: progress,
            releasedUnitIDs: [unitID("u-home")],
            showsPronunciation: showsPronunciation,
            voiceOver: voiceOver,
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

    private func saved(
        _ lesson: OpenLesson,
        _ session: LessonSession,
        on day: LocalDay,
        to store: any ProgressStore
    ) async {
        lesson.saveAnswer(session, on: day, to: store)
        await lesson.waitUntilSavesFinish()
    }

    private func seed(
        _ store: any ProgressStore,
        lesson raw: String,
        tasks: [SessionTask],
        on day: LocalDay,
        sessionID: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        showsPronunciation: Bool = true
    ) async throws {
        let attempt = LessonAttempt(
            sessionID: sessionID,
            lessonID: lessonID(raw),
            startedDay: day,
            contentVersion: course.contentVersion
        )
        let session = LessonSession(
            lessonID: lessonID(raw),
            showsPronunciation: showsPronunciation,
            tasks: tasks
        )
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

    private func letterTask(_ id: String) -> SessionTask {
        let target = itemID(id)
        return SessionTask(
            payload: .choice(QuizTask(
                kind: .findLetter,
                targetID: target,
                prompt: "shape",
                usage: nil,
                options: [
                    QuizOption(itemID: target, text: id),
                    QuizOption(itemID: itemID("e-other"), text: "other"),
                ]
            ))
        )
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
    private let savePause: CommitPause?

    init(contentVersion: String, pause: CommitPause? = nil, savePause: CommitPause? = nil) {
        inner = InMemoryProgressStore(contentVersion: contentVersion)
        self.pause = pause
        self.savePause = savePause
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

    private(set) var activeSaveCount = 0
    /// How many answers each active-session write carried, in the order they landed.
    private(set) var savedAnswerCounts: [Int] = []

    func saveActiveSession(_ session: ActiveSessionSnapshot) async throws {
        if savesToFail > 0 {
            savesToFail -= 1
            throw ProgressStoreContractError.writeFailed
        }
        await savePause?.pauseIfArmed()
        activeSaveCount += 1
        savedAnswerCounts.append(session.lesson?.answers.count ?? 0)
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

/// The same shape as the app model: the quiz is read off the lesson.
@MainActor
@Observable
private final class QuizHost {
    let lesson = OpenLesson()

    var quiz: LessonSession? { lesson.session }
}

private final class ChangeFlag: @unchecked Sendable {
    var fired = false
}
