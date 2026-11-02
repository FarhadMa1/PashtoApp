import Testing
import PashtoCore

struct ProgressValidationTests {
    @Test func freezesOutsideZeroToTwoAreClamped() {
        #expect(freezes(of: -1) == 0)
        #expect(freezes(of: 0) == 0)
        #expect(freezes(of: 1) == 1)
        #expect(freezes(of: 2) == 2)
        #expect(freezes(of: 3) == 2)
        #expect(freezes(of: 100) == 2)
        let clamped = validated(snapshot(streak: streak(freezes: 5, toward: 4)))
        #expect(clamped.streak.freezes == 2)
        #expect(clamped.streak.current == 3)
    }

    @Test func dailyGoalOutsideFiveTenFifteenBecomesRegular() {
        #expect(validatedDailyGoal(5) == .light)
        #expect(validatedDailyGoal(10) == .regular)
        #expect(validatedDailyGoal(15) == .serious)
        #expect(validatedDailyGoal(0) == .regular)
        #expect(validatedDailyGoal(7) == .regular)
        #expect(validatedDailyGoal(16) == .regular)
        #expect(validatedDailyGoal(-1) == .regular)
    }

    @Test func easeBelowTheMinimumIsClamped() {
        #expect(ease(of: 1) == ReviewCard.minimumEaseFactor)
        #expect(ease(of: 0) == ReviewCard.minimumEaseFactor)
        #expect(ease(of: 1.29) == ReviewCard.minimumEaseFactor)
        #expect(ease(of: ReviewCard.minimumEaseFactor) == ReviewCard.minimumEaseFactor)
        #expect(ease(of: 2.5) == 2.5)
    }

    @Test func nonFiniteEaseResetsToTheInitialEase() {
        #expect(ease(of: .nan) == ReviewCard.initialEaseFactor)
        #expect(ease(of: .infinity) == ReviewCard.initialEaseFactor)
        #expect(ease(of: -.infinity) == ReviewCard.initialEaseFactor)
    }

    @Test func negativeEaseResetsToTheInitialEase() {
        #expect(ease(of: -0.1) == ReviewCard.initialEaseFactor)
        #expect(ease(of: -2) == ReviewCard.initialEaseFactor)
    }

    @Test func negativeIntervalResetsToZero() {
        let card = validatedCard(interval: -4, repetitions: 3)
        #expect(card.intervalDays == 0)
        #expect(card.repetitions == 3)
        #expect(validatedCard(interval: 0, repetitions: 0).intervalDays == 0)
        #expect(validatedCard(interval: 6, repetitions: 2).intervalDays == 6)
    }

    @Test func negativeRepetitionsAndLapsesBecomeZero() {
        let repaired = validated(snapshot(cards: [
            card(id: "e-counts", repetitions: -3, lapses: -1),
        ])).cards[0]
        #expect(repaired.repetitions == 0)
        #expect(repaired.lapses == 0)
        let kept = validated(snapshot(cards: [
            card(id: "e-kept", repetitions: 4, lapses: 2),
        ])).cards[0]
        #expect(kept.repetitions == 4)
        #expect(kept.lapses == 2)
    }

    @Test func scoreOutsideZeroThroughOneHundredIsClamped() {
        #expect(score(of: -1) == 0)
        #expect(score(of: 0) == 0)
        #expect(score(of: 80) == 80)
        #expect(score(of: 100) == 100)
        #expect(score(of: 101) == 100)
        #expect(score(of: 250) == 100)
    }

    @Test func daysTowardNextFreezeOutsideZeroThroughSixAreClamped() {
        #expect(daysToward(of: -1, freezes: 0) == 0)
        #expect(daysToward(of: 0, freezes: 1) == 0)
        #expect(daysToward(of: 6, freezes: 1) == 6)
        #expect(daysToward(of: 7, freezes: 0) == 6)
        #expect(daysToward(of: 40, freezes: 1) == 6)
    }

    @Test func daysTowardNextFreezeIsZeroWhenTwoFreezesAreHeld() {
        #expect(daysToward(of: 4, freezes: 2) == 0)
        #expect(daysToward(of: 0, freezes: 2) == 0)
        let clamped = validated(snapshot(streak: streak(freezes: 5, toward: 4)))
        #expect(clamped.streak.freezes == 2)
        #expect(clamped.streak.daysTowardNextFreeze == 0)
    }

    private func freezes(of value: Int) -> Int {
        validated(snapshot(streak: streak(freezes: value, toward: 0))).streak.freezes
    }

    private func ease(of value: Double) -> Double {
        validated(snapshot(cards: [card(id: "e-ease", ease: value, interval: 1)])).cards[0].easeFactor
    }

    private func score(of value: Int) -> Int {
        let stored = LessonProgress(
            lessonID: lesson("l-greetings-1"),
            source: .completed,
            firstCompletedDay: day,
            bestScorePercent: value
        )
        return validated(snapshot(lessons: [stored])).lessonProgress[0].bestScorePercent
    }

    private func daysToward(of value: Int, freezes: Int) -> Int {
        validated(snapshot(streak: streak(freezes: freezes, toward: value))).streak.daysTowardNextFreeze
    }

    private func validatedCard(interval: Int, repetitions: Int) -> ReviewCard {
        let stored = ReviewCard(
            itemID: item("e-gap"),
            easeFactor: 2.5,
            intervalDays: interval,
            repetitions: repetitions,
            lapses: 0,
            dueDay: day,
            lastReviewedDay: nil,
            createdDay: day,
            state: .active,
            source: .lesson
        )
        return validated(snapshot(cards: [stored])).cards[0]
    }

    private func streak(freezes: Int, toward: Int) -> StreakState {
        StreakState(
            current: 3,
            longest: 3,
            lastActiveDay: day,
            freezes: freezes,
            daysTowardNextFreeze: toward,
            freezeUsedDays: []
        )
    }

    private func card(
        id: String,
        ease: Double = 2.5,
        interval: Int = 1,
        repetitions: Int = 0,
        lapses: Int = 0
    ) -> ReviewCard {
        ReviewCard(
            itemID: item(id),
            easeFactor: ease,
            intervalDays: interval,
            repetitions: repetitions,
            lapses: lapses,
            dueDay: day,
            lastReviewedDay: nil,
            createdDay: day,
            state: .active,
            source: .lesson
        )
    }

    private func snapshot(
        cards: [ReviewCard] = [],
        lessons: [LessonProgress] = [],
        streak: StreakState = .initial
    ) -> ProgressSnapshot {
        ProgressSnapshot(
            contentVersion: "2026.11.0",
            cards: cards,
            lessonProgress: lessons,
            streak: streak,
            settings: .initial,
            activeSession: nil,
            completedSessions: [],
            lastReconciledContentVersion: nil,
            latestObservedDay: nil
        )
    }

    private var day: LocalDay { LocalDay(year: 2026, month: 11, day: 1) }

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
