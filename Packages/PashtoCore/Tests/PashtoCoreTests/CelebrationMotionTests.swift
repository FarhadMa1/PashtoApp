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

    @Test func theHomeCueStaysPendingUntilTheFinalValuesAreShown() {
        let home = lessonID("l-home")
        let motion = PendingHomeMotion(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            streakFrom: 4,
            goalFrom: 9,
            lessonID: home
        )
        var cue = HomeMotionCue()
        cue.stage(motion)
        var playback = HomeMotionPlayback()

        let held = playback.prepare(cue.pending, reduceMotion: false, voiceOver: false)
        #expect(held == .holdFrom(motion))
        #expect(held.consumesCue == false)
        #expect(playback.displayedStreak(live: 5, pending: cue.pending, reduceMotion: false, voiceOver: false) == 4)
        #expect(playback.displayedGoal(live: 10, pending: cue.pending, reduceMotion: false, voiceOver: false) == 9)
        #expect(playback.waitingLessonID(pending: cue.pending, reduceMotion: false, voiceOver: false) == home)
        #expect(playback.animates == false)
        #expect(cue.pending == motion)

        let moving = playback.advance(afterRenderingFrom: motion.id, animated: true)
        #expect(moving == .animateToFinal(motion))
        #expect(moving.consumesCue)
        #expect(playback.animates)
        #expect(playback.displayedStreak(live: 5, pending: cue.pending, reduceMotion: false, voiceOver: false) == 5)
        #expect(playback.displayedGoal(live: 10, pending: cue.pending, reduceMotion: false, voiceOver: false) == 10)
        #expect(playback.waitingLessonID(pending: cue.pending, reduceMotion: false, voiceOver: false) == nil)
        #expect(cue.pending == motion)

        let consumed = cue.consume()
        #expect(consumed == motion)
        #expect(playback.displayedStreak(live: 5, pending: nil, reduceMotion: false, voiceOver: false) == 5)
        #expect(playback.displayedGoal(live: 10, pending: nil, reduceMotion: false, voiceOver: false) == 10)
        #expect(playback.waitingLessonID(pending: nil, reduceMotion: false, voiceOver: false) == nil)

        let reentry = playback.prepare(nil, reduceMotion: false, voiceOver: false)
        #expect(reentry == .none)
        #expect(reentry.consumesCue == false)
        cue.stage(motion)
        let sameCue = playback.prepare(cue.pending, reduceMotion: false, voiceOver: false)
        #expect(sameCue == .none)
        #expect(playback.displayedStreak(live: 5, pending: cue.pending, reduceMotion: false, voiceOver: false) == 5)

        var relaunch = HomeMotionPlayback()
        let quiet = HomeMotionCue()
        let again = relaunch.prepare(quiet.pending, reduceMotion: false, voiceOver: false)
        #expect(again == .none)
        #expect(relaunch.displayedStreak(live: 5, pending: nil, reduceMotion: false, voiceOver: false) == 5)
        #expect(relaunch.advance(afterRenderingFrom: motion.id, animated: true) == .none)
    }

    @Test func theSecondFinishedLessonStartsOnItsOwnFromValues() {
        let firstLesson = lessonID("l-a")
        let secondLesson = lessonID("l-b")
        let first = PendingHomeMotion(
            id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            streakFrom: 1,
            goalFrom: 4,
            lessonID: firstLesson
        )
        let second = PendingHomeMotion(
            id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            streakFrom: 2,
            goalFrom: 5,
            lessonID: secondLesson
        )
        var playback = HomeMotionPlayback()

        #expect(playback.displayedStreak(live: 2, pending: first, reduceMotion: false, voiceOver: false) == 1)
        #expect(playback.displayedGoal(live: 5, pending: first, reduceMotion: false, voiceOver: false) == 4)
        #expect(playback.waitingLessonID(pending: first, reduceMotion: false, voiceOver: false) == firstLesson)

        let opening = playback.prepare(first, reduceMotion: false, voiceOver: false)
        #expect(opening == .holdFrom(first))
        let moving = playback.advance(afterRenderingFrom: first.id, animated: true)
        #expect(moving == .animateToFinal(first))
        #expect(playback.stage == .atFinal(first))
        #expect(playback.displayedStreak(live: 2, pending: nil, reduceMotion: false, voiceOver: false) == 2)
        #expect(playback.displayedGoal(live: 5, pending: nil, reduceMotion: false, voiceOver: false) == 5)

        #expect(playback.displayedStreak(live: 3, pending: second, reduceMotion: false, voiceOver: false) == 2)
        #expect(playback.displayedGoal(live: 9, pending: second, reduceMotion: false, voiceOver: false) == 5)
        #expect(playback.waitingLessonID(pending: second, reduceMotion: false, voiceOver: false) == secondLesson)
        #expect(playback.stage == .atFinal(first))
        #expect(playback.displayedStreak(live: 3, pending: second, reduceMotion: true, voiceOver: false) == 3)
        #expect(playback.displayedGoal(live: 9, pending: second, reduceMotion: true, voiceOver: false) == 9)
        #expect(playback.waitingLessonID(pending: second, reduceMotion: true, voiceOver: false) == nil)
        #expect(playback.displayedStreak(live: 3, pending: second, reduceMotion: false, voiceOver: true) == 3)
        #expect(playback.displayedGoal(live: 9, pending: second, reduceMotion: false, voiceOver: true) == 9)
        #expect(playback.waitingLessonID(pending: second, reduceMotion: false, voiceOver: true) == nil)

        var reduced = playback
        let jumped = reduced.prepare(second, reduceMotion: true, voiceOver: false)
        #expect(jumped == .jumpToFinal(second))
        #expect(jumped.consumesCue)
        #expect(reduced.animates == false)
        #expect(reduced.displayedStreak(live: 3, pending: second, reduceMotion: true, voiceOver: false) == 3)
        #expect(reduced.displayedGoal(live: 9, pending: second, reduceMotion: true, voiceOver: false) == 9)
        #expect(reduced.waitingLessonID(pending: second, reduceMotion: true, voiceOver: false) == nil)
        var spoken = playback
        let read = spoken.prepare(second, reduceMotion: false, voiceOver: true)
        #expect(read == .jumpToFinal(second))
        #expect(spoken.displayedStreak(live: 3, pending: second, reduceMotion: false, voiceOver: true) == 3)
        #expect(spoken.displayedGoal(live: 9, pending: second, reduceMotion: false, voiceOver: true) == 9)
        #expect(spoken.waitingLessonID(pending: second, reduceMotion: false, voiceOver: true) == nil)

        let secondOpening = playback.prepare(second, reduceMotion: false, voiceOver: false)
        #expect(secondOpening == .holdFrom(second))
        #expect(secondOpening.consumesCue == false)
        #expect(playback.displayedStreak(live: 3, pending: second, reduceMotion: false, voiceOver: false) == 2)
        #expect(playback.displayedGoal(live: 9, pending: second, reduceMotion: false, voiceOver: false) == 5)
        let secondMove = playback.advance(afterRenderingFrom: second.id, animated: true)
        #expect(secondMove == .animateToFinal(second))
        #expect(playback.displayedStreak(live: 3, pending: second, reduceMotion: false, voiceOver: false) == 3)
        #expect(playback.displayedGoal(live: 9, pending: second, reduceMotion: false, voiceOver: false) == 9)
        #expect(playback.waitingLessonID(pending: second, reduceMotion: false, voiceOver: false) == nil)

        let replay = playback.prepare(second, reduceMotion: false, voiceOver: false)
        #expect(replay == .none)
        #expect(playback.displayedStreak(live: 3, pending: second, reduceMotion: false, voiceOver: false) == 3)
        #expect(playback.displayedGoal(live: 9, pending: second, reduceMotion: false, voiceOver: false) == 9)
        #expect(playback.waitingLessonID(pending: second, reduceMotion: false, voiceOver: false) == nil)
    }

    @Test func reduceMotionAndVoiceOverShowTheFinalHomeValuesBeforeTheCueIsConsumed() {
        let motion = PendingHomeMotion(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            streakFrom: 2,
            goalFrom: 3,
            lessonID: lessonID("l-home")
        )
        var reduced = HomeMotionPlayback()
        let jumped = reduced.prepare(motion, reduceMotion: true, voiceOver: false)
        #expect(jumped == .jumpToFinal(motion))
        #expect(jumped.consumesCue)
        #expect(reduced.animates == false)
        #expect(reduced.displayedStreak(live: 3, pending: motion, reduceMotion: true, voiceOver: false) == 3)
        #expect(reduced.displayedGoal(live: 4, pending: motion, reduceMotion: true, voiceOver: false) == 4)
        #expect(reduced.waitingLessonID(pending: motion, reduceMotion: true, voiceOver: false) == nil)

        var spoken = HomeMotionPlayback()
        let read = spoken.prepare(motion, reduceMotion: false, voiceOver: true)
        #expect(read == .jumpToFinal(motion))
        #expect(spoken.displayedStreak(live: 3, pending: motion, reduceMotion: false, voiceOver: true) == 3)
        #expect(spoken.displayedGoal(live: 4, pending: motion, reduceMotion: false, voiceOver: true) == 4)
        #expect(spoken.waitingLessonID(pending: motion, reduceMotion: false, voiceOver: true) == nil)
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
