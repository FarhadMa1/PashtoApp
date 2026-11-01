import Foundation
import Testing
@testable import PashtoCore

struct ReviewScheduleTests {
    private let today = LocalDay(year: 2026, month: 11, day: 1)

    @Test func newCardStartsAtTheSM2Defaults() {
        let card = ReviewCard.introduced(itemID: itemID("e-salam"), on: today)

        #expect(card.itemID == itemID("e-salam"))
        #expect(card.easeFactor == ReviewCard.initialEaseFactor)
        #expect(card.easeFactor == 2.5)
        #expect(ReviewCard.minimumEaseFactor == 1.3)
        #expect(card.intervalDays == 0)
        #expect(card.repetitions == 0)
        #expect(card.lapses == 0)
        #expect(card.dueDay == today)
        #expect(card.lastReviewedDay == nil)
        #expect(card.state == .active)
        #expect(card.source == .lesson)
    }

    @Test func placementCardUsesTheSameStartingSchedule() {
        let card = ReviewCard.introduced(itemID: itemID("e-salam"), on: today, source: .placement)

        #expect(card.source == .placement)
        #expect(card.easeFactor == 2.5)
        #expect(card.repetitions == 0)
        #expect(card.state == .active)
    }

    @Test func quizGradesMapToSM2Qualities() {
        #expect(reviewQuality(result: .correct, isRepeat: false) == .firstAttempt)
        #expect(reviewQuality(result: .correct, isRepeat: false).value == 4)
        #expect(reviewQuality(result: .correct, isRepeat: true) == .afterRetry)
        #expect(reviewQuality(result: .correct, isRepeat: true).value == 3)
        #expect(reviewQuality(result: .incorrect, isRepeat: false).value == 1)
        #expect(reviewQuality(result: .incorrect, isRepeat: true).value == 1)

        let repeated = SessionAnswer(
            task: sessionTask(isRepeat: true),
            answer: .choice(itemID("e-salam")),
            result: .correct
        )
        let first = SessionAnswer(
            task: sessionTask(isRepeat: false),
            answer: .choice(itemID("e-salam")),
            result: .incorrect
        )
        #expect(reviewQuality(for: repeated) == .afterRetry)
        #expect(reviewQuality(for: first) == .incorrect)
    }

    @Test func successfulReviewsFollowOneDayThenSixThenEase() {
        var card = ReviewCard.introduced(itemID: itemID("e-salam"), on: today)
        let expected = [1, 6, 15, 38, 95, 238]
        var day = today

        for (index, interval) in expected.enumerated() {
            let original = card
            card = review(card, quality: .firstAttempt, on: day)
            #expect(original.repetitions == index)
            #expect(card.intervalDays == interval)
            #expect(card.repetitions == index + 1)
            #expect(card.lapses == 0)
            #expect(easeThousandths(card.easeFactor) == 2_500)
            #expect(card.dueDay == day.adding(days: interval))
            #expect(card.lastReviewedDay == day)
            #expect(card.dueDay >= day.adding(days: 1))
            day = card.dueDay
        }
    }

    @Test func qualityThreeLowersEaseAndDoesNotLapse() {
        var card = ReviewCard.introduced(itemID: itemID("e-salam"), on: today)
        var day = today
        let expectedEase = [2_360, 2_220, 2_080]
        let expectedIntervals = [1, 6, 13]

        for index in expectedEase.indices {
            card = review(card, quality: .afterRetry, on: day)
            #expect(card.intervalDays == expectedIntervals[index])
            #expect(card.repetitions == index + 1)
            #expect(card.lapses == 0)
            #expect(easeThousandths(card.easeFactor) == expectedEase[index])
            day = card.dueDay
        }

        // The third step used ease 2.22, from before this review. 6 × 2.08 would be 12.
        #expect(card.intervalDays == 13)
    }

    @Test func qualityFiveUsesTheEaseFromBeforeTheReview() {
        var card = ReviewCard(
            itemID: itemID("e-salam"),
            easeFactor: 2.5,
            intervalDays: 6,
            repetitions: 2,
            lapses: 0,
            dueDay: today,
            lastReviewedDay: today,
            state: .active,
            source: .lesson
        )
        card = review(card, quality: ReviewQuality(5), on: today)

        #expect(card.intervalDays == 15)
        #expect(easeThousandths(card.easeFactor) == 2_600)
        #expect(card.repetitions == 3)
        #expect(card.lapses == 0)
    }

    @Test func intervalRoundingUsesHalfAwayFromZero() {
        #expect(reviewedInterval(days: 5, ease: 2.5) == 13)
        #expect(reviewedInterval(days: 7, ease: 2.5) == 18)
        #expect(reviewedInterval(days: 6, ease: 2.5) == 15)
        #expect(reviewedInterval(days: 1, ease: 1.5) == 2)
        #expect(reviewedInterval(days: 9, ease: 1.3) == 12)
        #expect(reviewedInterval(days: 2, ease: 2.5) == 5)
    }

    @Test func lapseResetsTheRunAndLowersEase() {
        var card = ReviewCard.introduced(itemID: itemID("e-salam"), on: today)
        card = review(card, quality: .firstAttempt, on: today)
        card = review(card, quality: .firstAttempt, on: card.dueDay)
        #expect(card.repetitions == 2)
        #expect(card.intervalDays == 6)

        let failed = review(card, quality: .incorrect, on: card.dueDay)
        #expect(failed.repetitions == 0)
        #expect(failed.intervalDays == 1)
        #expect(failed.lapses == 1)
        #expect(easeThousandths(failed.easeFactor) == 1_960)
        #expect(failed.dueDay == card.dueDay.adding(days: 1))

        let again = review(failed, quality: .firstAttempt, on: failed.dueDay)
        #expect(again.repetitions == 1)
        #expect(again.intervalDays == 1)
        #expect(again.lapses == 1)
        #expect(easeThousandths(again.easeFactor) == 1_960)

        let second = review(again, quality: .firstAttempt, on: again.dueDay)
        #expect(second.repetitions == 2)
        #expect(second.intervalDays == 6)
        #expect(second.lapses == 1)
    }

    @Test func easeNeverDropsBelowTheFloor() {
        var card = ReviewCard.introduced(itemID: itemID("e-salam"), on: today)
        let expected = [1_960, 1_420, 1_300, 1_300]
        for ease in expected {
            card = review(card, quality: .incorrect, on: card.dueDay)
            #expect(easeThousandths(card.easeFactor) == ease)
            #expect(card.easeFactor >= ReviewCard.minimumEaseFactor)
            #expect(card.intervalDays == 1)
            #expect(card.repetitions == 0)
        }
        #expect(card.lapses == expected.count)

        let stillFloored = review(card, quality: .afterRetry, on: card.dueDay)
        #expect(easeThousandths(stillFloored.easeFactor) == 1_300)
        #expect(stillFloored.repetitions == 1)
        #expect(stillFloored.lapses == expected.count)

        let zero = review(card, quality: ReviewQuality(0), on: card.dueDay)
        #expect(easeThousandths(zero.easeFactor) == 1_300)
        #expect(zero.lapses == expected.count + 1)
    }

    @Test func largeIntervalAndEaseStopAtTheCap() {
        let capped = review(scheduledCard(interval: 30_000, ease: 10), quality: .firstAttempt, on: today)

        #expect(ReviewCard.maximumIntervalDays == 36_500)
        #expect(capped.intervalDays == 36_500)
        #expect(capped.dueDay == today.adding(days: 36_500))
        #expect(capped.repetitions == 3)
        #expect(capped.lapses == 0)
        #expect(easeThousandths(capped.easeFactor) == 10_000)

        let stillUnder = review(scheduledCard(interval: 10_000, ease: 2.5), quality: .firstAttempt, on: today)
        #expect(stillUnder.intervalDays == 25_000)
    }

    @Test func corruptIntervalOrEaseDoesNotOverflow() {
        let maximum = review(scheduledCard(interval: Int.max, ease: 2.5), quality: .firstAttempt, on: today)
        #expect(maximum.intervalDays == ReviewCard.maximumIntervalDays)
        #expect(maximum.dueDay == today.adding(days: ReviewCard.maximumIntervalDays))
        #expect(maximum.repetitions == 3)

        let nearMaximum = review(
            scheduledCard(interval: Int.max - 1, ease: 2.5),
            quality: .firstAttempt,
            on: today
        )
        #expect(nearMaximum.intervalDays == 36_500)
        #expect(nearMaximum.dueDay == today.adding(days: 36_500))

        let hugeEase = review(
            scheduledCard(interval: 30_000, ease: Double.greatestFiniteMagnitude),
            quality: .firstAttempt,
            on: today
        )
        #expect(hugeEase.intervalDays == 36_500)

        let lapsed = review(scheduledCard(interval: Int.max, ease: 2.5), quality: .incorrect, on: today)
        #expect(lapsed.intervalDays == 1)
        #expect(lapsed.repetitions == 0)
        #expect(lapsed.lapses == 1)
        #expect(lapsed.dueDay == today.adding(days: 1))
    }

    @Test func aLateReviewDoesNotStretchTheInterval() {
        let introduced = ReviewCard.introduced(itemID: itemID("e-salam"), on: today)
        let reviewed = review(introduced, quality: .firstAttempt, on: today)
        let lateDay = reviewed.dueDay.adding(days: 100)
        let late = review(reviewed, quality: .firstAttempt, on: lateDay)

        #expect(late.intervalDays == 6)
        #expect(late.dueDay == lateDay.adding(days: 6))
        #expect(late.repetitions == 2)
    }

    @Test func clockSetBackDoesNotResetOrScheduleBeforeTomorrow() throws {
        let future = LocalDay(year: 2026, month: 11, day: 20)
        let card = ReviewCard(
            itemID: itemID("e-salam"),
            easeFactor: 2.5,
            intervalDays: 6,
            repetitions: 2,
            lapses: 1,
            dueDay: future.adding(days: 6),
            lastReviewedDay: future,
            state: .active,
            source: .placement
        )
        let elapsed = today.days(from: future)
        #expect(elapsed < 0)

        let reviewed = review(card, quality: .firstAttempt, on: today)

        #expect(reviewed.repetitions == 3)
        #expect(reviewed.lapses == 1)
        #expect(easeThousandths(reviewed.easeFactor) == 2_500)
        #expect(reviewed.intervalDays == 15)
        #expect(reviewed.intervalDays > 0)
        #expect(reviewed.intervalDays != elapsed)
        #expect(reviewed.dueDay == today.adding(days: 15))
        #expect(reviewed.dueDay >= today.adding(days: 1))
        #expect(reviewed.dueDay.days(from: today) >= 1)
        #expect(reviewed.lastReviewedDay == today)
        #expect(reviewed.source == .placement)
        #expect(reviewed.state == .active)
        #expect(card.repetitions == 2)
    }

    @Test func reviewDayComesFromTheDateProvider() throws {
        let kabul = try #require(TimeZone(identifier: "Asia/Kabul"))
        let later = try civilDate(year: 2026, month: 11, day: 20, hour: 15, timeZone: kabul)
        let earlier = try civilDate(year: 2026, month: 11, day: 1, hour: 9, timeZone: kabul)
        var clock = DayClock(provider: FixedDateProvider(now: later), timeZone: kabul)

        let introduced = ReviewCard.introduced(itemID: itemID("e-salam"), on: clock.today)
        let first = review(introduced, quality: reviewQuality(result: .correct, isRepeat: false), on: clock.today)
        #expect(first.lastReviewedDay == LocalDay(year: 2026, month: 11, day: 20))
        #expect(first.dueDay == LocalDay(year: 2026, month: 11, day: 21))

        clock.provider.now = earlier
        #expect(clock.today < first.lastReviewedDay!)
        let second = review(first, quality: .firstAttempt, on: clock.today)
        #expect(second.intervalDays == 6)
        #expect(second.repetitions == 2)
        #expect(second.lapses == 0)
        #expect(second.dueDay == clock.today.adding(days: 6))
        #expect(second.dueDay >= clock.today.adding(days: 1))
    }

    @Test func dueDayFollowsCivilDatesAcrossMonthAndLeapDay() {
        let january = LocalDay(year: 2026, month: 1, day: 31)
        let reviewed = review(
            ReviewCard.introduced(itemID: itemID("e-salam"), on: january),
            quality: .firstAttempt,
            on: january
        )
        #expect(reviewed.dueDay == LocalDay(year: 2026, month: 2, day: 1))

        let leap = LocalDay(year: 2024, month: 2, day: 28)
        let leapReview = review(
            ReviewCard.introduced(itemID: itemID("e-salam"), on: leap),
            quality: .firstAttempt,
            on: leap
        )
        #expect(leapReview.dueDay == LocalDay(year: 2024, month: 2, day: 29))
    }

    @Test func pausedStateIsLeftAlone() {
        let card = ReviewCard(
            itemID: itemID("e-salam"),
            easeFactor: 2.5,
            intervalDays: 0,
            repetitions: 0,
            lapses: 0,
            dueDay: today,
            lastReviewedDay: nil,
            state: .paused,
            source: .lesson
        )
        let reviewed = review(card, quality: .incorrect, on: today)
        #expect(reviewed.state == .paused)
        #expect(reviewed.lapses == 1)
    }

    @Test func theSameInputsReturnTheSameCard() {
        let card = ReviewCard.introduced(itemID: itemID("e-salam"), on: today)
        let first = review(card, quality: .firstAttempt, on: today)
        let second = review(card, quality: .firstAttempt, on: today)
        #expect(first == second)
        #expect(card == ReviewCard.introduced(itemID: itemID("e-salam"), on: today))
    }

    @Test func soundExampleDoesNotCreateACard() {
        let sounds = Lesson(
            id: lessonID("l-sounds-1"),
            title: "Sounds",
            items: [
                LessonItemRef(item: itemID("e-tol"), role: .soundExample, sound: "ṭ"),
                LessonItemRef(item: itemID("e-tol"), role: .soundExample, sound: "ṭ"),
            ],
            letters: [itemID("e-letter-alif")]
        )
        let soundCards = reviewCards(introducedIn: sounds, on: today)
        #expect(soundCards.map(\.itemID) == [itemID("e-letter-alif")])
        #expect(soundCards.allSatisfy { $0.source == .lesson })

        let greetings = Lesson(
            id: lessonID("l-greetings-1"),
            title: "Hello",
            items: [
                LessonItemRef(item: itemID("e-tol"), role: .soundExample, sound: "ṭ"),
                LessonItemRef(item: itemID("e-tol"), role: .introduce),
                LessonItemRef(item: itemID("e-manana"), role: .introduce),
                LessonItemRef(item: itemID("e-manana"), role: .introduce),
            ],
            letters: [itemID("e-tol")]
        )
        let greetingCards = reviewCards(introducedIn: greetings, on: today)
        #expect(greetingCards.map(\.itemID) == [itemID("e-tol"), itemID("e-manana")])

        let bundle = makeBundle(items: [], units: [
            CourseUnit(id: unitID("u-sounds"), track: "main", title: "Sounds", lessons: [sounds]),
            CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [greetings]),
        ])
        let cards = reviewCards(introducedIn: bundle, on: today)
        #expect(cards.map(\.itemID) == [
            itemID("e-letter-alif"),
            itemID("e-tol"),
            itemID("e-manana"),
        ])
        #expect(cards.allSatisfy { $0.lastReviewedDay == nil && $0.easeFactor == 2.5 })

        let onlyExample = Lesson(
            id: lessonID("l-sounds-2"),
            title: "Example only",
            items: [LessonItemRef(item: itemID("e-kha"), role: .soundExample, sound: "kh")]
        )
        #expect(reviewCards(introducedIn: onlyExample, on: today).isEmpty)
        let exampleBundle = makeBundle(items: [], units: [
            CourseUnit(id: unitID("u-sounds"), track: "main", title: "Sounds", lessons: [onlyExample]),
        ])
        #expect(reviewCards(introducedIn: exampleBundle, on: today).isEmpty)
    }

    @Test func cardRoundTripsThroughJSON() throws {
        let fresh = ReviewCard.introduced(itemID: itemID("e-salam"), on: today)
        let freshAgain = try JSONDecoder().decode(ReviewCard.self, from: JSONEncoder().encode(fresh))
        #expect(freshAgain == fresh)

        let reviewed = review(
            review(fresh, quality: .incorrect, on: today),
            quality: .afterRetry,
            on: today.adding(days: 1)
        )
        let paused = ReviewCard(
            itemID: reviewed.itemID,
            easeFactor: reviewed.easeFactor,
            intervalDays: reviewed.intervalDays,
            repetitions: reviewed.repetitions,
            lapses: reviewed.lapses,
            dueDay: reviewed.dueDay,
            lastReviewedDay: reviewed.lastReviewedDay,
            state: .paused,
            source: .placement
        )
        let data = try JSONEncoder().encode(paused)
        let decoded = try JSONDecoder().decode(ReviewCard.self, from: data)
        #expect(decoded == paused)

        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["itemID"] as? String == "e-salam")
        #expect(json["intervalDays"] as? Int == paused.intervalDays)
        #expect(json["repetitions"] as? Int == paused.repetitions)
        #expect(json["lapses"] as? Int == paused.lapses)
        #expect(json["dueDay"] as? String == paused.dueDay.isoDay)
        #expect(json["lastReviewedDay"] as? String == "2026-11-02")
        #expect(json["state"] as? String == "paused")
        #expect(json["source"] as? String == "placement")
        #expect(easeThousandths(json["easeFactor"] as? Double ?? 0) == easeThousandths(paused.easeFactor))

        let encodedFresh = try JSONEncoder().encode(fresh)
        let freshJSON = try #require(JSONSerialization.jsonObject(with: encodedFresh) as? [String: Any])
        #expect(freshJSON["lastReviewedDay"] == nil)
        #expect(freshJSON["dueDay"] as? String == "2026-11-01")
        #expect(freshJSON["easeFactor"] as? Double == 2.5)
        #expect(freshJSON["state"] as? String == "active")
        #expect(freshJSON["source"] as? String == "lesson")

        let withNull = """
        {"itemID":"e-salam","easeFactor":2.5,"intervalDays":0,"repetitions":0,"lapses":0,"dueDay":"2026-11-01","lastReviewedDay":null,"state":"active","source":"lesson"}
        """
        let fromNull = try JSONDecoder().decode(ReviewCard.self, from: Data(withNull.utf8))
        #expect(fromNull == fresh)
    }

    private func scheduledCard(interval: Int, ease: Double) -> ReviewCard {
        ReviewCard(
            itemID: itemID("e-salam"),
            easeFactor: ease,
            intervalDays: interval,
            repetitions: 2,
            lapses: 0,
            dueDay: today,
            lastReviewedDay: today,
            state: .active,
            source: .lesson
        )
    }

    private func reviewedInterval(days: Int, ease: Double) -> Int {
        let card = ReviewCard(
            itemID: itemID("e-salam"),
            easeFactor: ease,
            intervalDays: days,
            repetitions: 2,
            lapses: 0,
            dueDay: today,
            lastReviewedDay: today,
            state: .active,
            source: .lesson
        )
        return review(card, quality: .firstAttempt, on: today).intervalDays
    }

    private func sessionTask(isRepeat: Bool) -> SessionTask {
        SessionTask(
            payload: .choice(QuizTask(
                kind: .meaningPashtoToEnglish,
                targetID: itemID("e-salam"),
                prompt: "سلام",
                usage: nil,
                options: [QuizOption(itemID: itemID("e-salam"), text: "hello")]
            )),
            isRepeat: isRepeat
        )
    }

    private func easeThousandths(_ ease: Double) -> Int {
        Int((ease * 1000).rounded())
    }

    private func civilDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        timeZone: TimeZone
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return try #require(calendar.date(from: components))
    }
}
