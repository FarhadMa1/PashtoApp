import Testing
import PashtoCore

struct ProgressScreenTests {
    private let last = LocalDay(year: 2026, month: 11, day: 1)

    @Test func aNewerStoreChoosesUpdateNeeded() {
        #expect(progressScreen(for: .newerVersion) == .updateNeeded)
        #expect(progressScreen(for: .newerVersion).canStartOver == false)
    }

    @Test func anyOtherOpenFailureChoosesStorageError() {
        #expect(progressScreen(for: .other) == .storageError)
        #expect(progressScreen(for: .other).canStartOver == true)
    }

    @Test func anEmptyAppStoreIDHidesTheButton() {
        #expect(showsAppStoreButton(appStoreID: "") == false)
        #expect(showsAppStoreButton(appStoreID: "   ") == false)
        #expect(showsAppStoreButton(appStoreID: "\n") == false)
        #expect(appStoreIDForListing("") == nil)
        #expect(appStoreIDForListing("   ") == nil)
    }

    @Test func aDecimalAppStoreIDShowsTheButton() {
        #expect(showsAppStoreButton(appStoreID: "1234567890") == true)
        #expect(showsAppStoreButton(appStoreID: "  1234567890  ") == true)
        #expect(appStoreIDForListing("  1234567890  ") == "1234567890")
    }

    @Test func aNonDecimalAppStoreIDStaysHidden() {
        #expect(showsAppStoreButton(appStoreID: "id123") == false)
        #expect(showsAppStoreButton(appStoreID: "123 456") == false)
        #expect(appStoreIDForListing("not-listed") == nil)
    }

    @Test func anUncoveredBreakChoosesWelcomeBackAndKeepsFreezes() {
        let today = LocalDay(year: 2026, month: 11, day: 5)
        let state = streakState(freezes: 2, daysTowardNextFreeze: 0)

        #expect(progressScreen(streak: state, on: today) == .welcomeBack)
        #expect(streakWouldReset(state, on: today) == true)

        let next = streak(state, after: .completedSession, on: today)
        #expect(next.current == 1)
        #expect(next.freezes == 2)
        #expect(next.freezes <= StreakState.maximumFreezes)
        #expect(streak(state, after: .openedApp, on: today) == state)
    }

    @Test func aGapWithNoFreezesChoosesWelcomeBack() {
        let today = last.adding(days: 2)
        let state = streakState(freezes: 0, daysTowardNextFreeze: 3)

        #expect(progressScreen(streak: state, on: today) == .welcomeBack)
        let next = streak(state, after: .completedSession, on: today)
        #expect(next.freezes == 0)
        #expect(next.current == 1)
    }

    @Test func aCoveredBreakStaysReadyAndCanSpendAFreeze() {
        let today = last.adding(days: 2)
        let state = streakState(freezes: 1, daysTowardNextFreeze: 2)

        #expect(progressScreen(streak: state, on: today) == .ready)
        #expect(streakWouldReset(state, on: today) == false)

        let next = streak(state, after: .completedSession, on: today)
        #expect(next.current == state.current + 1)
        #expect(next.freezes == 0)
        #expect(next.freezeUsedDays == [last.adding(days: 1)])
    }

    @Test func twoFreezesCoverTwoMissedDaysWithoutWelcomeBack() {
        let today = last.adding(days: 3)
        let state = streakState(freezes: 2, daysTowardNextFreeze: 0)

        #expect(progressScreen(streak: state, on: today) == .ready)
        let next = streak(state, after: .completedSession, on: today)
        #expect(next.current == state.current + 1)
        #expect(next.freezes == 0)
    }

    @Test func theSameDayAndANewLearnerStayReady() {
        #expect(progressScreen(streak: streakState(freezes: 2, daysTowardNextFreeze: 0), on: last) == .ready)
        #expect(progressScreen(streak: .initial, on: last) == .ready)
        #expect(progressScreen(streak: streakState(freezes: 0, daysTowardNextFreeze: 1), on: last.adding(days: 1)) == .ready)
    }

    @Test func aClockSetBackDoesNotChooseWelcomeBack() {
        let state = streakState(freezes: 0, daysTowardNextFreeze: 4)
        #expect(progressScreen(streak: state, on: last.adding(days: -3)) == .ready)
        #expect(streak(state, after: .completedSession, on: last.adding(days: -3)) == state)
    }

    @Test func theShortReviewIsTheCappedDailyQueue() throws {
        let today = LocalDay(year: 2026, month: 11, day: 2)
        let cards = try (1...60).map { index in
            ReviewCard.introduced(itemID: try item("e-w\(index)"), on: today.adding(days: -index))
        }
        let known = Set(cards.map(\.itemID))
        let review = shortCappedReview(
            cards: cards,
            knownItemIDs: known,
            goal: .serious,
            newItemsShownToday: 0,
            on: today
        )
        let plan = dailyPlan(
            cards: cards,
            knownItemIDs: known,
            goal: .serious,
            newItemsShownToday: 0,
            on: today
        )

        #expect(review.cards == plan.reviews)
        #expect(review.cards.count == DailyPlan.maximumReviews)
        #expect(review.cards.first?.itemID.rawValue == "e-w60")
        #expect(review.cards.last?.itemID.rawValue == "e-w11")
    }

    @Test func anUnknownItemIsLeftOutOfTheShortReview() throws {
        let today = LocalDay(year: 2026, month: 11, day: 2)
        let card = ReviewCard.introduced(itemID: try item("e-salam"), on: today)
        let review = shortCappedReview(
            cards: [card],
            knownItemIDs: [],
            goal: .regular,
            newItemsShownToday: 0,
            on: today
        )
        #expect(review.cards.isEmpty)
    }

    private func streakState(freezes: Int, daysTowardNextFreeze: Int) -> StreakState {
        StreakState(
            current: 4,
            longest: 9,
            lastActiveDay: last,
            freezes: freezes,
            daysTowardNextFreeze: daysTowardNextFreeze,
            freezeUsedDays: []
        )
    }

    private func item(_ raw: String) throws -> ItemID {
        guard let item = ItemID(rawValue: raw) else {
            Issue.record("Item id \(raw) is not valid")
            throw CancellationError()
        }
        return item
    }
}
