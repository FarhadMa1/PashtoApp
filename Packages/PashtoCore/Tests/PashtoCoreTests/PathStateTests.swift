import Foundation
import Testing
@testable import PashtoCore

struct PathStateTests {
    private let today = LocalDay(year: 2026, month: 11, day: 1)
    private let greetings = lessonID("l-greetings-1")
    private let family = lessonID("l-family-1")
    /// Sorts before the other lesson ids and comes last in the course.
    private let last = lessonID("l-aaa-last")
    private let itemsPerLesson = 8

    @Test func noDueAndNoNewItemsOffersTheFirstLesson() {
        #expect(state() == .lesson(greetings))
        // A later lesson that is already finished does not move the path past
        // an earlier one. Order is the bundle, not the lesson id.
        let laterFinished = state(finished: [family, last])
        #expect(laterFinished == .lesson(greetings))
    }

    @Test func tenDueCardsAreReviewThenALesson() {
        let due = dueCards(10)
        #expect(state(cards: due) == .review(dueCount: 10))

        let cleared = due.map { review($0, quality: .firstAttempt, on: today) }
        #expect(state(cards: cleared) == .lesson(greetings))
    }

    @Test func aLessonStartsBelowTheCapEvenWhenItRunsOver() {
        let goal = DailyGoal.light
        let shown = goal.newItemLimit - 1
        #expect(itemsPerLesson > goal.newItemLimit - shown)
        #expect(state(shown: shown, goal: goal) == .lesson(greetings))
    }

    @Test func reachingTheCapOffersTheNextLesson() {
        let capped = state(finished: [greetings], shown: itemsPerLesson, goal: .light)
        #expect(capped == .doneForToday(learnMore: family))
    }

    @Test func oneExtraLessonThenDoneForTodayWithTheNewNext() {
        let before = state(finished: [greetings], shown: itemsPerLesson, goal: .light)
        #expect(before == .doneForToday(learnMore: family))

        // The extra lesson's introduced items count as shown today.
        let after = state(
            finished: [greetings, family],
            shown: itemsPerLesson * 2,
            goal: .light
        )
        #expect(after == .doneForToday(learnMore: last))
    }

    @Test func exactlyFiftyDueShowsLearnMoreWhenTheQueueIsEmpty() {
        let due = dueCards(50)
        #expect(state(cards: due, shown: 10, goal: .regular) == .review(dueCount: 50))

        let cleared = due.map { review($0, quality: .firstAttempt, on: today) }
        let open = state(cards: cleared, shown: 10, goal: .regular)
        #expect(open == .doneForToday(learnMore: greetings))
    }

    @Test func fiftyOneDueIsReviewWithoutLearnMore() {
        let due = dueCards(51)
        #expect(state(cards: due, shown: 0, goal: .serious) == .review(dueCount: 51))
        // The new-item cap is already reached. Learn more stays hidden.
        #expect(state(cards: due, shown: 15, goal: .serious) == .review(dueCount: 51))

        let queued = dailyPlan(
            cards: due,
            knownItemIDs: Set(due.map(\.itemID)),
            goal: .serious,
            newItemsShownToday: 15,
            on: today
        ).reviews.map(\.itemID)
        let reviewed = Set(queued)
        let after = due.map { card in
            reviewed.contains(card.itemID) ? review(card, quality: .firstAttempt, on: today) : card
        }
        #expect(state(cards: after, shown: 15, goal: .serious) == .review(dueCount: 1))
    }

    @Test func theNextCivilDayResetsTheCapAndOffersALesson() {
        // 23:59 and 00:01 are two civil days. The path takes the day, not a
        // clock time. The morning count is zero because introductions belong
        // to the day they happened. Nothing is due, so the new cap offers the
        // lesson. Cards from a lesson finished the day before are due this
        // morning and are review first; that is the due-card case.
        let content = sampleCourse()
        let evening = PathProgress(cards: [], finishedLessonIDs: [], newItemsShownToday: 10)
        let morning = PathProgress(cards: [], finishedLessonIDs: [], newItemsShownToday: 0)
        let late = today
        let early = today.adding(days: 1)

        let beforeMidnight = pathState(progress: evening, content: content, goal: .regular, today: late)
        #expect(beforeMidnight == .doneForToday(learnMore: greetings))

        let afterMidnight = pathState(progress: morning, content: content, goal: .regular, today: early)
        #expect(afterMidnight == .lesson(greetings))
    }

    @Test func loweringTheGoalAfterTenNewItemsIsDoneForToday() {
        let progress = PathProgress(cards: [], finishedLessonIDs: [], newItemsShownToday: 10)
        let content = sampleCourse()

        let open = pathState(progress: progress, content: content, goal: .serious, today: today)
        #expect(open == .lesson(greetings))

        let tightened = pathState(progress: progress, content: content, goal: .light, today: today)
        #expect(tightened == .doneForToday(learnMore: greetings))
        #expect(progress.newItemsShownToday == 10)
    }

    @Test func finishingEveryLessonIsCourseFinished() {
        let all = [greetings, family, last]
        #expect(state(finished: all) == .courseFinished)
        #expect(state(finished: all, shown: 20, goal: .light) == .courseFinished)

        let due = dueCards(3)
        #expect(state(cards: due, finished: all) == .review(dueCount: 3))
    }

    @Test func todaysPlacementCardsAreReviewBeforeALesson() {
        let due = dueCards(4, source: .placement, prefix: "e-place")
        #expect(state(cards: due) == .review(dueCount: 4))

        let cleared = due.map { review($0, quality: .firstAttempt, on: today) }
        #expect(state(cards: cleared) == .lesson(greetings))

        let tomorrow = [
            ReviewCard.introduced(
                itemID: itemID("e-place-later"),
                on: today.adding(days: 1),
                source: .placement
            ),
        ]
        #expect(state(cards: tomorrow) == .lesson(greetings))
    }

    @Test func itemsMissingFromTheBundleAreNotDue() {
        let cards = dueCards(60)
        let progress = PathProgress(cards: cards, finishedLessonIDs: [], newItemsShownToday: 0)
        let open = pathState(progress: progress, content: sampleCourse(), goal: .light, today: today)
        #expect(open == .lesson(greetings))
    }

    @Test func theSameInputReturnsTheSamePath() {
        let cards = [
            ReviewCard.introduced(itemID: itemID("e-b"), on: today),
            ReviewCard.introduced(itemID: itemID("e-a"), on: today.adding(days: -2)),
        ]
        let progress = PathProgress(
            cards: cards,
            finishedLessonIDs: [greetings],
            newItemsShownToday: 3
        )
        let content = sampleCourse(extraItemIDs: cards.map(\.itemID))
        let first = pathState(progress: progress, content: content, goal: .regular, today: today)
        let second = pathState(progress: progress, content: content, goal: .regular, today: today)
        #expect(first == second)
        #expect(first == .review(dueCount: 2))

        let reversed = PathProgress(
            cards: Array(cards.reversed()),
            finishedLessonIDs: [last, greetings],
            newItemsShownToday: 3
        )
        let again = pathState(progress: reversed, content: content, goal: .regular, today: today)
        #expect(again == first)

        let lessonProgress = PathProgress(cards: [], finishedLessonIDs: [greetings], newItemsShownToday: 0)
        let lessonFirst = pathState(progress: lessonProgress, content: content, goal: .regular, today: today)
        let lessonSecond = pathState(progress: lessonProgress, content: content, goal: .regular, today: today)
        #expect(lessonFirst == .lesson(family))
        #expect(lessonSecond == lessonFirst)

        #expect(requireSendable(first) == first)
        #expect(requireSendable(progress) == progress)
        #expect(requireSendable(DailyGoal.regular) == .regular)
    }

    private func state(
        cards: [ReviewCard] = [],
        finished: [LessonID] = [],
        shown: Int = 0,
        goal: DailyGoal = .regular,
        on day: LocalDay? = nil,
        course: ContentBundle? = nil
    ) -> PathState {
        let content = courseIncluding(course ?? sampleCourse(), itemIDs: cards.map(\.itemID))
        return pathState(
            progress: PathProgress(
                cards: cards,
                finishedLessonIDs: Set(finished),
                newItemsShownToday: shown
            ),
            content: content,
            goal: goal,
            today: day ?? today
        )
    }

    private func sampleCourse(extraItemIDs: [ItemID] = []) -> ContentBundle {
        let specs: [(lesson: String, prefix: String)] = [
            ("l-greetings-1", "e-greet"),
            ("l-family-1", "e-family"),
            ("l-aaa-last", "e-last"),
        ]
        var items: [ContentItem] = []
        var lessons: [Lesson] = []
        for spec in specs {
            var refs: [LessonItemRef] = []
            for index in 1...itemsPerLesson {
                let id = String(format: "\(spec.prefix)-%02d", index)
                items.append(makeItem(id, en: id))
                refs.append(LessonItemRef(item: itemID(id), role: .introduce))
            }
            lessons.append(Lesson(id: lessonID(spec.lesson), title: spec.lesson, items: refs))
        }
        return courseIncluding(
            makeBundle(
                items: items,
                units: [
                    CourseUnit(
                        id: unitID("u-greetings"),
                        track: "main",
                        title: "Greetings",
                        lessons: [lessons[0]]
                    ),
                    CourseUnit(
                        id: unitID("u-family"),
                        track: "main",
                        title: "Family",
                        lessons: [lessons[1], lessons[2]]
                    ),
                ]
            ),
            itemIDs: extraItemIDs
        )
    }

    private func courseIncluding(_ course: ContentBundle, itemIDs: [ItemID]) -> ContentBundle {
        var items = course.items
        var seen = Set(items.map(\.id))
        for id in itemIDs where seen.insert(id).inserted {
            items.append(makeItem(id.rawValue, en: id.rawValue))
        }
        return makeBundle(items: items, units: course.units)
    }

    private func dueCards(
        _ count: Int,
        source: ReviewCardSource = .lesson,
        prefix: String = "e-due"
    ) -> [ReviewCard] {
        (1...count).map { index in
            ReviewCard.introduced(
                itemID: itemID(String(format: "\(prefix)-%03d", index)),
                on: today,
                source: source
            )
        }
    }

    private func requireSendable<T: Sendable>(_ value: T) -> T { value }
}
