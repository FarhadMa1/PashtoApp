import Foundation
import Testing
@testable import PashtoCore

struct DailyPlanTests {
    private let today = LocalDay(year: 2026, month: 11, day: 1)

    @Test func goalsAreFiveTenAndFifteen() {
        #expect(DailyGoal.light.newItemLimit == 5)
        #expect(DailyGoal.regular.newItemLimit == 10)
        #expect(DailyGoal.serious.newItemLimit == 15)
        #expect(DailyGoal.allCases.map(\.newItemLimit) == [5, 10, 15])
        #expect(DailyPlan.maximumReviews == 50)
    }

    @Test func noDueCardsOfferTheWholeGoal() {
        for goal in DailyGoal.allCases {
            let plan = plan(goal: goal, cards: [])
            #expect(plan.dueCount == 0)
            #expect(plan.reviews.isEmpty)
            #expect(plan.newItemsRemaining == goal.newItemLimit)
            #expect(plan.canStartLesson)
        }
    }

    @Test func fiftyDueCardsStillAllowNewItemsAndFiftyOneDoNot() {
        let fifty = plan(goal: .serious, cards: dueCards(50, on: today))
        #expect(fifty.dueCount == 50)
        #expect(fifty.reviews.count == 50)
        #expect(fifty.newItemsRemaining == 15)
        #expect(fifty.canStartLesson)

        let blocked = plan(goal: .light, cards: dueCards(51, on: today))
        #expect(blocked.dueCount == 51)
        #expect(blocked.reviews.count == DailyPlan.maximumReviews)
        #expect(blocked.newItemsRemaining == 0)
        #expect(!blocked.canStartLesson)
        #expect(blocked.reviews.map(\.itemID.rawValue).last == "e-due-050")
        #expect(!blocked.reviews.contains { $0.itemID.rawValue == "e-due-051" })
    }

    @Test func changingTheGoalKeepsItemsAlreadyShown() {
        let cards = dueCards(4, on: today)

        let tightened = plan(goal: .light, cards: cards, shown: 10)
        #expect(tightened.newItemsRemaining == 0)
        #expect(!tightened.canStartLesson)

        let raised = plan(goal: .serious, cards: cards, shown: 10)
        #expect(raised.newItemsRemaining == 5)
        #expect(raised.canStartLesson)

        let oneLeft = plan(goal: .regular, cards: cards, shown: 9)
        #expect(oneLeft.newItemsRemaining == 1)
        #expect(oneLeft.canStartLesson)

        let exact = plan(goal: .regular, cards: cards, shown: 10)
        #expect(exact.newItemsRemaining == 0)
        #expect(!exact.canStartLesson)

        let negativeShown = plan(goal: .light, cards: cards, shown: -3)
        #expect(negativeShown.newItemsRemaining == 5)
    }

    @Test func aFullReviewQueueBlocksNewItemsEvenWhenNoneWereShown() {
        let blocked = plan(goal: .serious, cards: dueCards(60, on: today), shown: 0)
        #expect(blocked.dueCount == 60)
        #expect(blocked.reviews.count == 50)
        #expect(blocked.newItemsRemaining == 0)
    }

    @Test func equalDueDaysAreSortedByItemID() {
        let ids = ["e-m", "e-z", "e-a", "e-b"]
        let cards = ids.map { makeCard($0, due: today) }
        let plan = plan(goal: .regular, cards: cards)

        #expect(plan.reviews.map(\.itemID.rawValue) == ["e-a", "e-b", "e-m", "e-z"])
        #expect(plan.dueCount == 4)
        #expect(plan.newItemsRemaining == 10)
    }

    @Test func oldestDueDayComesFirstWhenMoreThanFiftyAreDue() {
        let ancient = [
            makeCard("e-z", due: today.adding(days: -80)),
            makeCard("e-a", due: today.adding(days: -80)),
            makeCard("e-m", due: today.adding(days: -80)),
        ]
        let backlog = (1...60).map { index in
            makeCard(String(format: "e-back-%03d", index), due: today.adding(days: -10))
        }
        let plan = plan(goal: .regular, cards: backlog + ancient)

        #expect(plan.dueCount == 63)
        #expect(plan.reviews.count == 50)
        #expect(plan.newItemsRemaining == 0)
        #expect(plan.reviews.prefix(3).map(\.itemID.rawValue) == ["e-a", "e-m", "e-z"])
        let backlogIDs = plan.reviews.dropFirst(3).map(\.itemID.rawValue)
        #expect(backlogIDs == (1...47).map { String(format: "e-back-%03d", $0) })
        #expect(plan.reviews.last?.dueDay == today.adding(days: -10))
    }

    @Test func placementCardsCountTowardTheCapAndComeBeforeNewItems() {
        let lessons = dueCards(30, on: today.adding(days: -1), prefix: "e-lesson")
        let placement = dueCards(10, on: today, source: .placement, prefix: "e-place")
        let open = plan(goal: .regular, cards: placement + lessons)

        #expect(open.dueCount == 40)
        #expect(open.reviews.count == 40)
        #expect(open.reviews.prefix(30).allSatisfy { $0.source == .lesson })
        #expect(open.reviews.suffix(10).allSatisfy { $0.source == .placement })
        #expect(open.newItemsRemaining == 10)
        #expect(open.canStartLesson)

        let crowdedLessons = dueCards(45, on: today.adding(days: -1), prefix: "e-lesson")
        let crowded = plan(goal: .serious, cards: crowdedLessons + placement)
        #expect(crowded.dueCount == 55)
        #expect(crowded.reviews.count == 50)
        #expect(crowded.newItemsRemaining == 0)
        #expect(!crowded.canStartLesson)
        #expect(crowded.reviews.prefix(45).allSatisfy { $0.source == .lesson })
        #expect(crowded.reviews.suffix(5).map(\.itemID.rawValue) == (1...5).map {
            String(format: "e-place-%03d", $0)
        })
        #expect(!crowded.reviews.contains { $0.itemID.rawValue == "e-place-006" })
    }

    @Test func pausedReviewedAndFutureCardsStayOutOfTheQueue() {
        let paused = makeCard("e-paused", due: today.adding(days: -5), state: .paused)
        let reviewed = makeCard("e-done", due: today, lastReviewed: today)
        let waiting = makeCard("e-wait", due: today, lastReviewed: today.adding(days: -3))
        let later = makeCard("e-later", due: today.adding(days: 2))
        let plan = plan(goal: .light, cards: [paused, reviewed, later, waiting])

        #expect(plan.reviews.map(\.itemID.rawValue) == ["e-wait"])
        #expect(plan.dueCount == 1)
        #expect(plan.newItemsRemaining == 5)
        #expect(plan.canStartLesson)
    }

    @Test func aFutureReviewDayStaysOutUntilTheClockCatchesUp() {
        let card = makeCard(
            "e-salam",
            due: today,
            lastReviewed: LocalDay(year: 2026, month: 11, day: 10)
        )
        let stored = [card]
        let setBack = plan(goal: .regular, cards: stored)
        #expect(setBack.reviews.isEmpty)
        #expect(setBack.dueCount == 0)
        #expect(setBack.newItemsRemaining == 10)
        #expect(stored == [card])

        let onTheStoredDay = plan(
            goal: .regular,
            cards: stored,
            on: LocalDay(year: 2026, month: 11, day: 10)
        )
        #expect(onTheStoredDay.reviews.isEmpty)
        #expect(onTheStoredDay.dueCount == 0)

        let caughtUp = plan(
            goal: .regular,
            cards: stored,
            on: LocalDay(year: 2026, month: 11, day: 11)
        )
        #expect(caughtUp.reviews.map(\.itemID) == [card.itemID])
        #expect(caughtUp.dueCount == 1)

        let notDueYet = makeCard(
            "e-later",
            due: LocalDay(year: 2026, month: 11, day: 20),
            lastReviewed: LocalDay(year: 2026, month: 11, day: 10)
        )
        let beforeDue = plan(
            goal: .regular,
            cards: [notDueYet],
            on: LocalDay(year: 2026, month: 11, day: 11)
        )
        #expect(beforeDue.reviews.isEmpty)
        let onItsDueDay = plan(
            goal: .regular,
            cards: [notDueYet],
            on: LocalDay(year: 2026, month: 11, day: 20)
        )
        #expect(onItsDueDay.reviews.map(\.itemID) == [notDueYet.itemID])
    }

    @Test func emptyPlanAndUnknownItemsLeaveTheStoredCardsAlone() {
        let empty = dailyPlan(
            cards: [],
            knownItemIDs: [],
            goal: .regular,
            newItemsShownToday: 0,
            on: today
        )
        // No cards and no known items. The queue is empty. The allowance is
        // still the goal, because the cap is about due cards. Whether a lesson
        // remains in the course is left to the path.
        #expect(empty.reviews.isEmpty)
        #expect(empty.dueCount == 0)
        #expect(empty.newItemsRemaining == 10)
        #expect(empty.canStartLesson)

        let gone = makeCard("e-gone", due: today.adding(days: -30))
        let kept = makeCard("e-kept", due: today)
        let stored = [gone, kept]
        let plan = dailyPlan(
            cards: stored,
            knownItemIDs: [kept.itemID],
            goal: .regular,
            newItemsShownToday: 0,
            on: today
        )
        #expect(plan.reviews.map(\.itemID) == [kept.itemID])
        #expect(plan.dueCount == 1)
        #expect(plan.newItemsRemaining == 10)
        #expect(stored == [gone, kept])

        let orphans = dueCards(60, on: today.adding(days: -40), prefix: "e-old")
        let ignored = dailyPlan(
            cards: orphans,
            knownItemIDs: [],
            goal: .light,
            newItemsShownToday: 0,
            on: today
        )
        #expect(ignored.reviews.isEmpty)
        #expect(ignored.dueCount == 0)
        #expect(ignored.newItemsRemaining == 5)
        #expect(orphans.count == 60)
    }

    @Test func aLongPauseReturnsNewItemsOnAFixedDay() {
        let overdueSince = today.adding(days: -90)
        var cards = (1...300).map { index in
            ReviewCard.introduced(
                itemID: itemID(String(format: "e-card-%03d", index)),
                on: overdueSince
            )
        }
        #expect(cards.allSatisfy { $0.dueDay == overdueSince })

        var day = today
        var firstNewItemsDay: Int?
        for offset in 0..<20 {
            let plan = plan(goal: .regular, cards: cards, on: day)
            if plan.newItemsRemaining > 0 {
                firstNewItemsDay = offset
                #expect(plan.dueCount == 50)
                #expect(plan.reviews.count == 50)
                #expect(plan.newItemsRemaining == 10)
                #expect(plan.canStartLesson)
                #expect(plan.reviews.map(\.itemID.rawValue) == (251...300).map {
                    String(format: "e-card-%03d", $0)
                })
                break
            }
            #expect(plan.dueCount > 50)
            #expect(plan.reviews.count == 50)
            #expect(plan.newItemsRemaining == 0)
            #expect(!plan.canStartLesson)
            let reviewed = Set(plan.reviews.map(\.itemID))
            cards = cards.map { card in
                reviewed.contains(card.itemID) ? review(card, quality: .firstAttempt, on: day) : card
            }
            day = day.adding(days: 1)
        }

        // Six days give every card its first review (interval 1). The next
        // five give the oldest 250 their second review (interval 6). On the
        // following morning, 11 days after the first catch-up day, 50 cards
        // are still due, and the goal is offered again.
        #expect(firstNewItemsDay == 11)
    }

    @Test func theSameInputsReturnTheSamePlan() {
        let cards = [makeCard("e-b", due: today), makeCard("e-a", due: today.adding(days: -2))]
        let first = plan(goal: .light, cards: cards, shown: 2)
        let second = plan(goal: .light, cards: cards, shown: 2)
        #expect(first == second)
        #expect(first.reviews.map(\.itemID.rawValue) == ["e-a", "e-b"])
        let sendable = requireSendable(first)
        #expect(sendable == first)
        #expect(requireSendable(DailyGoal.regular) == .regular)
    }

    @Test func aFinishedLessonIsDueTheNextDay() throws {
        let introduced = [
            ReviewCard.introduced(itemID: itemID("e-first"), on: today),
            ReviewCard.introduced(itemID: itemID("e-retry"), on: today),
            ReviewCard.introduced(itemID: itemID("e-missed"), on: today),
        ]
        let answers = [
            choice("e-first", result: .correct, isRepeat: false),
            choice("e-first", result: .incorrect, isRepeat: false),
            choice("e-retry", result: .incorrect, isRepeat: false),
            choice("e-retry", result: .correct, isRepeat: false),
            choice("e-retry", result: .correct, isRepeat: true),
            choice("e-missed", result: .incorrect, isRepeat: false),
            choice("e-missed", result: .incorrect, isRepeat: true),
            match(including: "e-first"),
        ]

        #expect(lessonReviewQuality(for: itemID("e-first"), answers: answers) == .firstAttempt)
        #expect(lessonReviewQuality(for: itemID("e-retry"), answers: answers) == .afterRetry)
        #expect(lessonReviewQuality(for: itemID("e-missed"), answers: answers) == .incorrect)
        #expect(lessonReviewQuality(for: itemID("e-other"), answers: answers) == nil)

        let reviewed = applyLessonReviews(
            introduced,
            introducedIn: lesson("l-one", introducing: ["e-first", "e-retry", "e-missed"]),
            answers: answers,
            on: today
        )
        #expect(introduced.allSatisfy { $0.lastReviewedDay == nil })
        #expect(reviewed.map(\.itemID) == introduced.map(\.itemID))

        let first = try #require(reviewed.first { $0.itemID.rawValue == "e-first" })
        #expect(first.intervalDays == 1)
        #expect(first.repetitions == 1)
        #expect(first.lapses == 0)
        #expect(easeThousandths(first.easeFactor) == 2_500)
        #expect(first.lastReviewedDay == today)
        #expect(first.dueDay == today.adding(days: 1))

        let retry = try #require(reviewed.first { $0.itemID.rawValue == "e-retry" })
        #expect(retry.intervalDays == 1)
        #expect(retry.repetitions == 1)
        #expect(retry.lapses == 0)
        #expect(easeThousandths(retry.easeFactor) == 2_360)
        #expect(retry.dueDay == today.adding(days: 1))

        let missed = try #require(reviewed.first { $0.itemID.rawValue == "e-missed" })
        #expect(missed.intervalDays == 1)
        #expect(missed.repetitions == 0)
        #expect(missed.lapses == 1)
        #expect(easeThousandths(missed.easeFactor) == 1_960)
        #expect(missed.dueDay == today.adding(days: 1))
        #expect(reviewed.allSatisfy { $0.dueDay >= today.adding(days: 1) })

        let todayPlan = plan(goal: .regular, cards: reviewed)
        #expect(todayPlan.reviews.isEmpty)
        #expect(todayPlan.dueCount == 0)
        #expect(todayPlan.newItemsRemaining == 10)

        let tomorrow = plan(goal: .regular, cards: reviewed, on: today.adding(days: 1))
        #expect(tomorrow.reviews.map(\.itemID.rawValue) == ["e-first", "e-missed", "e-retry"])
        #expect(tomorrow.dueCount == 3)
    }

    @Test func severalAnswersProduceOneReviewAndAMatchDoesNotGradeOneItem() {
        let many = ReviewCard.introduced(itemID: itemID("e-many"), on: today)
        let answers = [
            choice("e-many", result: .correct, isRepeat: false),
            choice("e-many", result: .incorrect, isRepeat: false),
            choice("e-many", result: .incorrect, isRepeat: true),
            choice("e-many", result: .correct, isRepeat: true),
            order("e-many", result: .incorrect),
        ]
        let manyLesson = lesson("l-many", introducing: ["e-many"])
        let reviewed = applyLessonReviews([many], introducedIn: manyLesson, answers: answers, on: today)
        #expect(reviewed.count == 1)
        #expect(reviewed[0].repetitions == 1)
        #expect(reviewed[0].lapses == 0)
        #expect(easeThousandths(reviewed[0].easeFactor) == 2_500)
        #expect(applyLessonReviews(reviewed, introducedIn: manyLesson, answers: answers, on: today) == reviewed)

        let matched = ReviewCard.introduced(itemID: itemID("e-pair"), on: today)
        let onlyMatch = [match(including: "e-pair")]
        #expect(lessonReviewQuality(for: matched.itemID, answers: onlyMatch) == nil)
        let held = applyLessonReviews(
            [matched],
            introducedIn: lesson("l-match", introducing: ["e-pair"]),
            answers: onlyMatch,
            on: today
        )
        #expect(held[0].dueDay == today.adding(days: 1))
        #expect(held[0].lastReviewedDay == nil)
        #expect(held[0].repetitions == 0)
        #expect(held[0].intervalDays == 0)
        #expect(held[0].lapses == 0)
        #expect(held[0].easeFactor == matched.easeFactor)
        #expect(held[0].state == .active)
        #expect(held[0].source == .lesson)
        let heldToday = plan(goal: .regular, cards: held)
        #expect(heldToday.reviews.isEmpty)
        #expect(heldToday.dueCount == 0)
        let heldTomorrow = plan(goal: .regular, cards: held, on: today.adding(days: 1))
        #expect(heldTomorrow.reviews.map(\.itemID) == [matched.itemID])

        let ordered = ReviewCard.introduced(itemID: itemID("e-order"), on: today)
        let fromOrder = applyLessonReviews(
            [ordered],
            introducedIn: lesson("l-order", introducing: ["e-order"]),
            answers: [order("e-order", result: .correct)],
            on: today
        )
        #expect(fromOrder[0].repetitions == 1)
        #expect(fromOrder[0].lastReviewedDay == today)
        #expect(fromOrder[0].dueDay == today.adding(days: 1))
    }

    @Test func aCardWithNoGradeWaitsUntilTomorrowWithoutAReview() {
        let fresh = ReviewCard.introduced(itemID: itemID("e-pair"), on: today)
        let placement = ReviewCard.introduced(itemID: itemID("e-pair"), on: today, source: .placement)
        let otherLesson = ReviewCard.introduced(itemID: itemID("e-other"), on: today)
        let alreadyLater = ReviewCard(
            itemID: itemID("e-later"),
            easeFactor: 2.2,
            intervalDays: 6,
            repetitions: 2,
            lapses: 1,
            dueDay: today.adding(days: 4),
            lastReviewedDay: nil,
            state: .active,
            source: .lesson
        )
        let reviewedToday = ReviewCard(
            itemID: itemID("e-done"),
            easeFactor: 2.5,
            intervalDays: 1,
            repetitions: 1,
            lapses: 0,
            dueDay: today,
            lastReviewedDay: today,
            state: .active,
            source: .lesson
        )
        let stored = [fresh, placement, otherLesson, alreadyLater, reviewedToday]
        let updated = applyLessonReviews(
            stored,
            introducedIn: lesson("l-match", introducing: ["e-pair", "e-later", "e-done"]),
            answers: [
                match(including: "e-pair"),
                choice("e-other", result: .correct, isRepeat: false),
                choice("e-place", result: .correct, isRepeat: false),
            ],
            on: today
        )

        #expect(updated[0].dueDay == today.adding(days: 1))
        #expect(updated[0].lastReviewedDay == nil)
        #expect(updated[0].repetitions == fresh.repetitions)
        #expect(updated[0].intervalDays == fresh.intervalDays)
        #expect(updated[0].lapses == fresh.lapses)
        #expect(updated[0].easeFactor == fresh.easeFactor)
        #expect(updated[1] == placement)
        #expect(updated[2] == otherLesson)
        #expect(updated[3] == alreadyLater)
        #expect(updated[4] == reviewedToday)

        let todayPlan = plan(goal: .regular, cards: updated, known: Set(stored.map(\.itemID)))
        #expect(todayPlan.reviews.map(\.itemID.rawValue) == ["e-other", "e-pair"])
        #expect(!todayPlan.reviews.contains { $0.source == .lesson && $0.itemID.rawValue == "e-pair" })
    }

    /// Real lessons, built the way the app builds them. Every introduced item
    /// that can take a single-item question has one in the session, and that
    /// question is a first-answer grade. A match does not count.
    ///
    /// Three items in `l-greetings-1` cannot take one: the lesson introduces
    /// only two letters, and ستړی مه شې has fewer than two legal distractors.
    /// Those cards use the due-day safety net instead of a review.
    @Test func everyIntroducedItemHasASingleItemQuestion() throws {
        let bundle = try loadRepositoryContent()
        let lessons = bundle.units.flatMap(\.lessons)
        #expect(!lessons.isEmpty)
        let withoutALegalQuestion = ["e-letter-alif", "e-letter-be", "e-stare-ma-she"]

        for seed in UInt64(1)...8 {
            var seen: [LessonID] = []
            var uncovered: [String] = []
            var rng = SplitMix64(seed: seed)
            for lesson in lessons {
                seen.append(lesson.id)
                let session = LessonSessionBuilder.build(
                    for: lesson.id,
                    in: bundle,
                    seenLessonIDs: seen,
                    using: &rng
                )
                let introduced = Distractors.introducedItems(in: lesson.id, bundle: bundle)
                var graded: Set<ItemID> = []
                for task in session.tasks {
                    guard let target = singleItemTarget(task), !task.isRepeat else { continue }
                    graded.insert(target)
                    let answer = SessionAnswer(
                        task: task,
                        answer: .choice(target),
                        result: .correct
                    )
                    #expect(lessonReviewQuality(for: target, answers: [answer]) == .firstAttempt)
                }
                let context = QuizContext(bundle: bundle, seenLessonIDs: seen)
                for item in introduced where !graded.contains(item.id) {
                    var probe = SplitMix64(seed: seed)
                    #expect(
                        !canMakeSingleItemQuestion(for: item, in: context, using: &probe),
                        "\(lesson.id.rawValue) dropped a single-item question for \(item.id.rawValue)"
                    )
                    uncovered.append(item.id.rawValue)
                }
            }
            #expect(uncovered.sorted() == withoutALegalQuestion)
        }
    }

    @Test func greetingsItemsWithoutAQuestionAreDueTomorrowAndOtherCardsStay() throws {
        let bundle = try loadRepositoryContent()
        let course = bundle.units.flatMap(\.lessons)
        let greetings = try #require(course.first { $0.id.rawValue == "l-greetings-1" })
        var seen: [LessonID] = []
        var rng = SplitMix64(seed: 1)
        for lesson in course {
            seen.append(lesson.id)
            if lesson.id == greetings.id { break }
        }
        let session = LessonSessionBuilder.build(
            for: greetings.id,
            in: bundle,
            seenLessonIDs: seen,
            using: &rng
        )
        let day = LocalDay(year: 2026, month: 11, day: 1)
        let introduced = reviewCards(introducedIn: greetings, on: day)
        let outsider = ReviewCard.introduced(itemID: itemID("e-manana"), on: day)
        let placement = ReviewCard.introduced(itemID: itemID("e-salam"), on: day, source: .placement)
        let answers = session.tasks.map(correctAnswer)
        let updated = applyLessonReviews(
            introduced + [outsider, placement],
            introducedIn: greetings,
            answers: answers,
            on: day
        )

        let untouched = ["e-letter-alif", "e-letter-be", "e-stare-ma-she"]
        for card in updated where card.source == .lesson && card.itemID != outsider.itemID {
            #expect(card.dueDay >= day.adding(days: 1))
            if untouched.contains(card.itemID.rawValue) {
                #expect(card.lastReviewedDay == nil)
                #expect(card.repetitions == 0)
                #expect(card.intervalDays == 0)
                #expect(card.lapses == 0)
                #expect(card.easeFactor == ReviewCard.initialEaseFactor)
            } else {
                #expect(card.lastReviewedDay == day)
                #expect(card.repetitions == 1)
            }
        }
        #expect(updated.first { $0.itemID == outsider.itemID && $0.source == .lesson } == outsider)
        #expect(updated.first { $0.source == .placement } == placement)

        var lessonCards: [ReviewCard] = []
        for original in introduced {
            lessonCards.append(
                try #require(updated.first { $0.itemID == original.itemID && $0.source == .lesson })
            )
        }
        let todayPlan = dailyPlan(
            cards: lessonCards,
            knownItemIDs: Set(lessonCards.map(\.itemID)),
            goal: .regular,
            newItemsShownToday: 0,
            on: day
        )
        #expect(todayPlan.reviews.isEmpty)
        #expect(todayPlan.dueCount == 0)
    }

    private func correctAnswer(_ task: SessionTask) -> SessionAnswer {
        let answer: QuizAnswer
        switch task.payload {
        case .choice(let quiz):
            answer = .choice(quiz.targetID)
        case .orderWords(let order):
            answer = .tokenOrder(Array(order.tokens.indices))
        case .matchPairs(let match):
            answer = .matches(match.pairs.map { MatchLink(left: $0.left.itemID, right: $0.right.itemID) })
        }
        return SessionAnswer(task: task, answer: answer, result: .correct)
    }

    private func canMakeSingleItemQuestion(
        for item: ContentItem,
        in context: QuizContext,
        using rng: inout SplitMix64
    ) -> Bool {
        if PashtoToEnglishChoice().makeTask(for: item, in: context, using: &rng) != nil { return true }
        if EnglishToPashtoChoice().makeTask(for: item, in: context, using: &rng) != nil { return true }
        if TransliterationChoice().makeTask(for: item, in: context, using: &rng) != nil { return true }
        if OrderWords.makeTask(for: item, in: context, using: &rng) != nil { return true }
        if DialogResponse().makeTask(for: item, in: context, using: &rng) != nil { return true }
        return false
    }

    private func plan(
        goal: DailyGoal,
        cards: [ReviewCard],
        shown: Int = 0,
        known: Set<ItemID>? = nil,
        on day: LocalDay? = nil
    ) -> DailyPlan {
        dailyPlan(
            cards: cards,
            knownItemIDs: known ?? Set(cards.map(\.itemID)),
            goal: goal,
            newItemsShownToday: shown,
            on: day ?? today
        )
    }

    private func dueCards(
        _ count: Int,
        on due: LocalDay,
        source: ReviewCardSource = .lesson,
        prefix: String = "e-due"
    ) -> [ReviewCard] {
        (1...count).map { index in
            makeCard(String(format: "\(prefix)-%03d", index), due: due, source: source)
        }
    }

    private func makeCard(
        _ id: String,
        due: LocalDay,
        lastReviewed: LocalDay? = nil,
        state: ReviewCardState = .active,
        source: ReviewCardSource = .lesson
    ) -> ReviewCard {
        ReviewCard(
            itemID: itemID(id),
            easeFactor: ReviewCard.initialEaseFactor,
            intervalDays: 1,
            repetitions: 1,
            lapses: 0,
            dueDay: due,
            lastReviewedDay: lastReviewed ?? due.adding(days: -1),
            state: state,
            source: source
        )
    }

    private func lesson(_ id: String, introducing ids: [String]) -> Lesson {
        Lesson(
            id: lessonID(id),
            title: id,
            items: ids.map { LessonItemRef(item: itemID($0), role: .introduce) }
        )
    }

    private func singleItemTarget(_ task: SessionTask) -> ItemID? {
        switch task.payload {
        case .choice(let quiz):
            return quiz.targetID
        case .orderWords(let order):
            return order.targetID
        case .matchPairs:
            return nil
        }
    }

    private func choice(_ id: String, result: GradeResult, isRepeat: Bool) -> SessionAnswer {
        let target = itemID(id)
        return SessionAnswer(
            task: SessionTask(
                payload: .choice(QuizTask(
                    kind: .meaningPashtoToEnglish,
                    targetID: target,
                    prompt: "سلام",
                    usage: nil,
                    options: [QuizOption(itemID: target, text: "hello")]
                )),
                isRepeat: isRepeat
            ),
            answer: .choice(target),
            result: result
        )
    }

    private func order(_ id: String, result: GradeResult) -> SessionAnswer {
        let target = itemID(id)
        return SessionAnswer(
            task: SessionTask(
                payload: .orderWords(OrderWordsTask(
                    targetID: target,
                    tiles: [WordTile(index: 0, text: "سلام")],
                    fixedEnding: "",
                    tokens: ["سلام"],
                    acceptedOrders: nil
                ))
            ),
            answer: .tokenOrder([0]),
            result: result
        )
    }

    private func match(including id: String) -> SessionAnswer {
        let target = itemID(id)
        let other = itemID("e-other")
        let pairs = [
            MatchPair(
                left: MatchSide(itemID: target, text: "سلام"),
                right: MatchSide(itemID: target, text: "hello")
            ),
            MatchPair(
                left: MatchSide(itemID: other, text: "مننه"),
                right: MatchSide(itemID: other, text: "thanks")
            ),
        ]
        return SessionAnswer(
            task: SessionTask(
                payload: .matchPairs(MatchPairsTask(
                    mode: .pashtoEnglish,
                    pairs: pairs,
                    rightOrder: [1, 0]
                ))
            ),
            answer: .matches([
                MatchLink(left: target, right: target),
                MatchLink(left: other, right: other),
            ]),
            result: .correct
        )
    }

    private func easeThousandths(_ ease: Double) -> Int {
        Int((ease * 1000).rounded())
    }

    private func requireSendable<T: Sendable>(_ value: T) -> T { value }
}
