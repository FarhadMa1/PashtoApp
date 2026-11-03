import Foundation
import Testing
@testable import PashtoCore

struct CelebrationMotionTests {
    @Test func celebrationTimingsMatchTheDemoAndStayUnderTheCap() {
        #expect(CelebrationMotion.star == 0.55)
        #expect(CelebrationMotion.starDamping == 0.62)
        #expect(CelebrationMotion.girih == 0.8)
        #expect(CelebrationMotion.countUp == 0.6)
        #expect(CelebrationMotion.lessonFinishMaximum == 1.4)
        #expect(CelebrationMotion.lessonFinishDuration == 0.8)
        #expect(CelebrationMotion.lessonFinishDuration <= CelebrationMotion.lessonFinishMaximum)
        #expect(CelebrationMotion.streakPulse == 0.45)
        #expect(CelebrationMotion.pathFill == 0.5)
        #expect(CelebrationMotion.pathPulse == 1.6)
        #expect(CelebrationMotion.goalSpringResponse == 0.6)
        #expect(CelebrationMotion.goalSpringDamping == 0.8)
        #expect(CelebrationMotion.goalCheck == 0.35)
    }

    @Test func reduceMotionSwapsMovementForAFadeOrAStillState() {
        #expect(LessonStarStyle.style(reduceMotion: false) == .unfold)
        #expect(LessonStarStyle.style(reduceMotion: true) == .fade)
        #expect(GirihEntrance.style(reduceMotion: false) == .fadeIn)
        #expect(GirihEntrance.style(reduceMotion: true) == .still)
        #expect(StreakPulseStyle.style(reduceMotion: false) == .pulse)
        #expect(StreakPulseStyle.style(reduceMotion: true) == .fade)
        #expect(CoursePathMotion.NodeStyle.style(reduceMotion: false) == .pulse)
        #expect(CoursePathMotion.NodeStyle.style(reduceMotion: true) == .ring)
        #expect(CoursePathMotion.FillStyle.style(reduceMotion: false) == .ease)
        #expect(CoursePathMotion.FillStyle.style(reduceMotion: true) == .jump)
    }

    @Test func countersShowTheFinalValueForReduceMotionVoiceOverAndSkip() {
        let moving = CounterPlan.plan(target: 9, reduceMotion: false, voiceOver: false, skipped: false)
        #expect(moving == CounterPlan(start: 0, end: 9, animates: true, spoken: 9))

        let quiet = CounterPlan.plan(target: 9, reduceMotion: true, voiceOver: false, skipped: false)
        #expect(quiet.start == 9)
        #expect(quiet.animates == false)
        #expect(quiet.spoken == 9)

        let spoken = CounterPlan.plan(target: 9, reduceMotion: false, voiceOver: true, skipped: false)
        #expect(spoken.start == 9)
        #expect(spoken.animates == false)
        #expect(spoken.spoken == 9)

        let skipped = CounterPlan.plan(target: 9, reduceMotion: false, voiceOver: false, skipped: true)
        #expect(skipped.start == 9)
        #expect(skipped.animates == false)

        let empty = CounterPlan.plan(target: 0, reduceMotion: false, voiceOver: false, skipped: false)
        #expect(empty.animates == false)
        #expect(empty.spoken == 0)
    }

    @Test func lessonFinishStatsCountTheFirstTryOnly() {
        let door = itemID("e-door")
        let first = answer(id: door, correct: true, repeated: false)
        let missed = answer(id: door, correct: false, repeated: false)
        let again = answer(id: door, correct: true, repeated: true)
        let session = LessonSession(
            lessonID: lessonID("l-home"),
            tasks: [],
            answers: [first, missed, again]
        )
        #expect(LessonFinishStats.measure(session) == LessonFinishStats(answered: 2, correct: 1))
    }

    @Test func theStreakRollsUnlessMotionOrVoiceOverAsksForTheFinalNumber() {
        let roll = StreakRoll.plan(from: 5, to: 6, reduceMotion: false, voiceOver: false)
        #expect(roll == StreakRoll(from: 5, to: 6, animates: true, spoken: 6))
        let quiet = StreakRoll.plan(from: 5, to: 6, reduceMotion: true, voiceOver: false)
        #expect(quiet.from == 6)
        #expect(quiet.animates == false)
        #expect(quiet.spoken == 6)
        let spoken = StreakRoll.plan(from: 5, to: 6, reduceMotion: false, voiceOver: true)
        #expect(spoken.from == 6)
        #expect(spoken.spoken == 6)
        #expect(spoken.animates == false)
        let same = StreakRoll.plan(from: 6, to: 6, reduceMotion: false, voiceOver: false)
        #expect(same.animates == false)
    }

    @Test func theGoalRingFillsTowardTheStoredLimitAndSpeaksTheFinalFraction() {
        let demo = GoalRingPlan.plan(from: 2, to: 3, goal: 3, reduceMotion: false, voiceOver: false)
        #expect(demo.fromFraction == 2.0 / 3.0)
        #expect(demo.toFraction == 1)
        #expect(demo.fromCount == 2)
        #expect(demo.toCount == 3)
        #expect(demo.animates)
        #expect(demo.showsCheck)
        #expect(demo.spoken == "3/3")

        let items = GoalRingPlan.plan(from: 2, to: 3, goal: 10, reduceMotion: false, voiceOver: false)
        #expect(items.fromFraction == 0.2)
        #expect(items.toFraction == 0.3)
        #expect(items.showsCheck == false)
        #expect(items.spoken == "3/10")

        let quiet = GoalRingPlan.plan(from: 2, to: 3, goal: 10, reduceMotion: true, voiceOver: false)
        #expect(quiet.fromFraction == quiet.toFraction)
        #expect(quiet.fromCount == 3)
        #expect(quiet.animates == false)
        #expect(quiet.spoken == "3/10")

        let spoken = GoalRingPlan.plan(from: 2, to: 3, goal: 3, reduceMotion: false, voiceOver: true)
        #expect(spoken.fromCount == 3)
        #expect(spoken.animates == false)
        #expect(spoken.showsCheck)
        #expect(spoken.spoken == "3/3")

        let none = GoalRingPlan.plan(from: 1, to: 1, goal: 0, reduceMotion: false, voiceOver: false)
        #expect(none.toFraction == 0)
        #expect(none.showsCheck == false)
        #expect(none.animates == false)
    }

    @Test func theNextLessonIsTheFirstUnfinishedOne() {
        let home = lessonID("l-home")
        let other = lessonID("l-other")
        let hello = lessonID("l-salam")
        #expect(CoursePathMotion.next(in: [home, other, hello], finished: [home]) == other)
        #expect(CoursePathMotion.next(in: [home, other], finished: [home, other]) == nil)
        #expect(CoursePathMotion.next(in: [], finished: []) == nil)
    }

    @Test func everyGradeUsesTheSameHapticKind() {
        #expect(AnswerHaptic.kind(for: .correct) == .success)
        #expect(AnswerHaptic.kind(for: .incorrect) == .error)
    }

    @Test func oneTapSkipsTheLessonFinishToTheFinalNumbers() {
        let stats = LessonFinishStats(answered: 6, correct: 4)
        let frame = LessonFinishSkip.afterOneTap(stats)
        #expect(frame.starAtRest)
        #expect(frame.girihVisible)
        #expect(frame.correct == 4)
        #expect(frame.answered == 6)
        #expect(frame.correct == stats.correct)
        #expect(frame.answered == stats.answered)

        let counting = CounterPlan.plan(target: 4, reduceMotion: false, voiceOver: false, skipped: false)
        #expect(counting.start == 0)
        #expect(counting.animates)
        #expect(frame.correct == counting.end)
    }

    @Test func theGoalHapticFiresOnlyWhenTheCountCrossesTheLimit() {
        #expect(DailyGoalCrossing.reached(from: 4, to: 5, limit: 5))
        #expect(DailyGoalCrossing.reached(from: 9, to: 10, limit: 10))
        #expect(DailyGoalCrossing.reached(from: 14, to: 16, limit: 15))
        #expect(DailyGoalCrossing.reached(from: 5, to: 6, limit: 5) == false)
        #expect(DailyGoalCrossing.reached(from: 3, to: 4, limit: 10) == false)
        #expect(DailyGoalCrossing.reached(from: 15, to: 16, limit: 15) == false)
        #expect(DailyGoalCrossing.reached(from: 0, to: 0, limit: 0) == false)
        #expect(DailyGoalCrossing.reached(from: 0, to: 4, limit: 5) == false)
    }

    @Test func theGoalRingClampsAtTheFullCircle() {
        #expect(DailyGoalCrossing.fraction(16, limit: 15) == 1)
        #expect(DailyGoalCrossing.fraction(3, limit: 10) == 0.3)
        #expect(DailyGoalCrossing.fraction(0, limit: 0) == 0)
        #expect(DailyGoalCrossing.fraction(-2, limit: 10) == 0)

        let over = GoalRingPlan.plan(from: 14, to: 16, goal: 15, reduceMotion: false, voiceOver: false)
        #expect(over.toFraction == 1)
        #expect(over.showsCheck)
        #expect(over.spoken == "16/15")
    }

    @Test func pendingHomeMotionIsConsumedOnlyOnce() {
        var cue = HomeMotionCue()
        let fresh = cue.consume()
        #expect(fresh == nil)
        #expect(cue.pending == nil)

        let home = lessonID("l-home")
        let motion = PendingHomeMotion(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, streakFrom: 2, goalFrom: 4, lessonID: home)
        cue.stage(motion)
        #expect(cue.pending == motion)

        let later = PendingHomeMotion(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, streakFrom: 3, goalFrom: 5, lessonID: home)
        cue.stage(later)

        let played = cue.consume()
        #expect(played == later)
        #expect(cue.pending == nil)
        let again = cue.consume()
        #expect(again == nil)

        var relaunch = HomeMotionCue()
        let replay = relaunch.consume()
        #expect(replay == nil)
        #expect(relaunch.pending == nil)
    }

    private func answer(id: ItemID, correct: Bool, repeated: Bool) -> SessionAnswer {
        let task = SessionTask(
            payload: .choice(QuizTask(
                kind: .meaningPashtoToEnglish,
                targetID: id,
                prompt: id.rawValue,
                usage: nil,
                options: [QuizOption(itemID: id, text: id.rawValue)]
            )),
            isRepeat: repeated
        )
        let picked = correct ? id : itemID("e-other")
        return SessionAnswer(task: task, answer: .choice(picked), result: correct ? .correct : .incorrect)
    }
}

struct BackgroundSaveOrderTests {
    @Test func anEarlierEndDoesNotStopALaterSave() {
        var order = BackgroundSaveOrder()
        let first = order.begin()
        let second = order.begin()
        #expect(first == 1)
        #expect(second == 2)
        #expect(order.end(matching: first) == false)
        #expect(order.running)
        #expect(order.token == second)
        let stopped = order.end(matching: second)
        #expect(stopped)
        #expect(order.running == false)
    }

    @Test func endingTheSameTokenTwiceDoesNothing() {
        var order = BackgroundSaveOrder()
        let token = order.begin()
        #expect(order.running)
        let stopped = order.end(matching: token)
        #expect(stopped)
        #expect(order.running == false)
        #expect(order.end(matching: token) == false)
        #expect(order.running == false)
    }

    @Test func endBeforeBeginDoesNothing() {
        var order = BackgroundSaveOrder()
        #expect(order.end(matching: 1) == false)
        #expect(order.running == false)
        #expect(order.token == 0)
    }
}
