import Foundation
import Testing
@testable import PashtoCore

struct StreakTests {
    private let start = LocalDay(year: 2026, month: 3, day: 1)

    @Test func rulesMatchTheApprovedNumbers() {
        #expect(StreakState.daysPerFreeze == 7)
        #expect(StreakState.maximumFreezes == 2)
        #expect(StreakState.freezeHistoryDays == 30)
        #expect(StreakState.initial.current == 0)
        #expect(StreakState.initial.longest == 0)
        #expect(StreakState.initial.lastActiveDay == nil)
        #expect(StreakState.initial.freezes == 0)
        #expect(StreakState.initial.daysTowardNextFreeze == 0)
        #expect(StreakState.initial.freezeUsedDays.isEmpty)
    }

    @Test func firstCompletedSessionStartsTheStreak() {
        let day = start
        let state = streak(StreakState.initial, after: .completedSession, on: day)

        #expect(state.current == 1)
        #expect(state.longest == 1)
        #expect(state.lastActiveDay == day)
        #expect(state.freezes == 0)
        #expect(state.daysTowardNextFreeze == 1)
        #expect(state.freezeUsedDays.isEmpty)
    }

    @Test func theSameDayNeverCountsTwice() {
        let first = streak(StreakState.initial, after: .completedSession, on: start)
        let second = streak(first, after: .completedSession, on: start)

        #expect(second == first)
        #expect(second.current == 1)
        #expect(second.daysTowardNextFreeze == 1)
    }

    @Test func sessionJustBeforeAndAfterMidnightCountsTwoDays() throws {
        let oslo = try timeZone("Europe/Oslo")
        let late = try date(year: 2026, month: 11, day: 2, hour: 23, minute: 59, timeZone: oslo)
        let early = try date(year: 2026, month: 11, day: 3, hour: 0, minute: 1, timeZone: oslo)
        let lateDay = LocalDay(date: late, timeZone: oslo)
        let earlyDay = LocalDay(date: early, timeZone: oslo)

        #expect(lateDay == ymd(2026, 11, 2))
        #expect(earlyDay == ymd(2026, 11, 3))
        #expect(earlyDay.days(from: lateDay) == 1)
        #expect(early.timeIntervalSince(late) == 2 * 60)

        let before = streak(running(days: 4, from: ymd(2026, 10, 29)), after: .completedSession, on: lateDay)
        #expect(before.current == 5)
        #expect(before.lastActiveDay == lateDay)

        let after = streak(before, after: .completedSession, on: earlyDay)
        #expect(after.current == 6)
        #expect(after.longest == 6)
        #expect(after.lastActiveDay == earlyDay)
        #expect(after.freezes == 0)
        #expect(after.daysTowardNextFreeze == 6)
        #expect(after.freezeUsedDays.isEmpty)
    }

    @Test func osloThenKabulThenNewYorkUsesEachLocalDay() throws {
        let oslo = try timeZone("Europe/Oslo")
        let kabul = try timeZone("Asia/Kabul")
        let newYork = try timeZone("America/New_York")
        // 23:30 in Oslo is 03:00 the next day in Kabul and 17:30 the same day in New York.
        let instant = try date(year: 2026, month: 11, day: 2, hour: 23, minute: 30, timeZone: oslo)
        let osloDay = LocalDay(date: instant, timeZone: oslo)
        let kabulDay = LocalDay(date: instant, timeZone: kabul)
        let newYorkDay = LocalDay(date: instant, timeZone: newYork)

        #expect(osloDay == ymd(2026, 11, 2))
        #expect(kabulDay == ymd(2026, 11, 3))
        #expect(newYorkDay == ymd(2026, 11, 2))
        #expect(kabulDay.days(from: osloDay) == 1)
        #expect(newYorkDay.days(from: kabulDay) == -1)

        let completedInOslo = streak(StreakState.initial, after: .completedSession, on: osloDay)
        #expect(completedInOslo.current == 1)
        #expect(completedInOslo.lastActiveDay == osloDay)

        let openedInKabul = streak(completedInOslo, after: .openedApp, on: kabulDay)
        #expect(openedInKabul == completedInOslo)

        let completedInKabul = streak(completedInOslo, after: .completedSession, on: kabulDay)
        #expect(completedInKabul.current == 2)
        #expect(completedInKabul.lastActiveDay == kabulDay)
        #expect(completedInKabul.freezes == 0)
        #expect(completedInKabul.freezeUsedDays.isEmpty)

        let completedInNewYork = streak(completedInKabul, after: .completedSession, on: newYorkDay)
        #expect(completedInNewYork == completedInKabul)
        #expect(completedInNewYork.current == 2)
        #expect(completedInNewYork.freezes == 0)
        #expect(completedInNewYork.freezeUsedDays.isEmpty)
    }

    @Test func daylightSavingStillCountsOneCivilDay() throws {
        let oslo = try timeZone("Europe/Oslo")

        let springLate = try date(year: 2026, month: 3, day: 29, hour: 23, minute: 59, timeZone: oslo)
        let springEarly = try date(year: 2026, month: 3, day: 30, hour: 0, minute: 1, timeZone: oslo)
        let springMidnight = try date(year: 2026, month: 3, day: 29, timeZone: oslo)
        let nextMidnight = try date(year: 2026, month: 3, day: 30, timeZone: oslo)
        #expect(nextMidnight.timeIntervalSince(springMidnight) == 23 * 60 * 60)

        let springDay = LocalDay(date: springLate, timeZone: oslo)
        let dayAfterSpring = LocalDay(date: springEarly, timeZone: oslo)
        #expect(springDay == ymd(2026, 3, 29))
        #expect(dayAfterSpring == ymd(2026, 3, 30))
        #expect(dayAfterSpring.days(from: springDay) == 1)

        let beforeSpring = streak(StreakState.initial, after: .completedSession, on: springDay)
        let afterSpring = streak(beforeSpring, after: .completedSession, on: dayAfterSpring)
        #expect(afterSpring.current == 2)
        #expect(afterSpring.lastActiveDay == dayAfterSpring)
        #expect(afterSpring.freezeUsedDays.isEmpty)

        let fallMorning = try date(year: 2026, month: 10, day: 25, hour: 0, minute: 30, timeZone: oslo)
        let fallNight = try date(year: 2026, month: 10, day: 25, hour: 23, minute: 30, timeZone: oslo)
        let afterFall = try date(year: 2026, month: 10, day: 26, hour: 0, minute: 1, timeZone: oslo)
        let fallMidnight = try date(year: 2026, month: 10, day: 25, timeZone: oslo)
        let fallNextMidnight = try date(year: 2026, month: 10, day: 26, timeZone: oslo)
        #expect(fallNextMidnight.timeIntervalSince(fallMidnight) == 25 * 60 * 60)

        let fallDay = LocalDay(date: fallMorning, timeZone: oslo)
        let fallAgain = LocalDay(date: fallNight, timeZone: oslo)
        let dayAfterFall = LocalDay(date: afterFall, timeZone: oslo)
        #expect(fallDay == fallAgain)
        #expect(dayAfterFall.days(from: fallDay) == 1)

        let firstOnFallDay = streak(StreakState.initial, after: .completedSession, on: fallDay)
        let secondOnFallDay = streak(firstOnFallDay, after: .completedSession, on: fallAgain)
        #expect(secondOnFallDay == firstOnFallDay)
        #expect(secondOnFallDay.current == 1)

        let next = streak(secondOnFallDay, after: .completedSession, on: dayAfterFall)
        #expect(next.current == 2)
        #expect(next.lastActiveDay == dayAfterFall)
    }

    @Test func freezeIsEarnedOnDay7And14AndNotOnDay21() {
        var state = StreakState.initial
        for dayNumber in 1...21 {
            state = streak(state, after: .completedSession, on: start.adding(days: dayNumber - 1))
            #expect(state.current == dayNumber)
            #expect(state.longest == dayNumber)
            #expect(state.freezeUsedDays.isEmpty)
            if dayNumber == 6 {
                #expect(state.freezes == 0)
                #expect(state.daysTowardNextFreeze == 6)
            } else if dayNumber == 7 {
                #expect(state.freezes == 1)
                #expect(state.daysTowardNextFreeze == 0)
            } else if dayNumber == 13 {
                #expect(state.freezes == 1)
                #expect(state.daysTowardNextFreeze == 6)
            } else if dayNumber == 14 {
                #expect(state.freezes == 2)
                #expect(state.daysTowardNextFreeze == 0)
            } else if dayNumber >= 15 {
                #expect(state.freezes == 2)
                #expect(state.daysTowardNextFreeze == 0)
            }
        }
        #expect(state.freezes == 2)
        #expect(state.daysTowardNextFreeze == 0)
        #expect(state.current == 21)
    }

    @Test func oneFreezeCoversOneMissedDay() {
        let earned = running(days: 7, from: start)
        #expect(earned.freezes == 1)
        #expect(earned.current == 7)
        let missed = start.adding(days: 7)
        let returnDay = start.adding(days: 8)

        let saved = streak(earned, after: .completedSession, on: returnDay)

        #expect(saved.current == 8)
        #expect(saved.freezes == 0)
        #expect(saved.daysTowardNextFreeze == 1)
        #expect(saved.lastActiveDay == returnDay)
        #expect(saved.freezeUsedDays == [missed])
        #expect(saved.longest == 8)
    }

    @Test func aCoveredDayDoesNotCountTowardTheNextFreeze() {
        let before = running(days: 12, from: start)
        #expect(before.current == 12)
        #expect(before.freezes == 1)
        #expect(before.daysTowardNextFreeze == 5)

        let missed = start.adding(days: 12)
        let returnDay = start.adding(days: 13)
        let saved = streak(before, after: .completedSession, on: returnDay)

        #expect(saved.current == 13)
        #expect(saved.freezes == 0)
        #expect(saved.daysTowardNextFreeze == 6)
        #expect(saved.freezeUsedDays == [missed])
        #expect(saved.longest == 13)
    }

    @Test func twoDayGapWithTwoFreezesIsSaved() throws {
        let before = running(days: 14, from: start)
        #expect(before.freezes == 2)
        #expect(before.current == 14)
        #expect(before.daysTowardNextFreeze == 0)
        // Last session is 14 March. 15 and 16 March are missed. 17 March is completed.
        let last = try #require(before.lastActiveDay)
        let firstMissed = start.adding(days: 14)
        let secondMissed = start.adding(days: 15)
        let returnDay = start.adding(days: 16)
        #expect(last == ymd(2026, 3, 14))
        #expect(firstMissed == ymd(2026, 3, 15))
        #expect(secondMissed == ymd(2026, 3, 16))
        #expect(returnDay == ymd(2026, 3, 17))
        #expect(returnDay.days(from: last) - 1 == 2)

        let opened = streak(before, after: .openedApp, on: returnDay)
        #expect(opened == before)

        let saved = streak(before, after: .completedSession, on: returnDay)
        #expect(saved.current == 15)
        #expect(saved.longest == 15)
        #expect(saved.freezes == 0)
        #expect(saved.daysTowardNextFreeze == 1)
        #expect(saved.lastActiveDay == returnDay)
        #expect(saved.freezeUsedDays == [firstMissed, secondMissed])
    }

    @Test func twoDayGapWithOneFreezeResetsAndKeepsTheFreeze() throws {
        let covered = start.adding(days: 7)
        let afterCover = streak(running(days: 7, from: start), after: .completedSession, on: start.adding(days: 8))
        #expect(afterCover.freezes == 0)
        #expect(afterCover.freezeUsedDays == [covered])

        var before = afterCover
        for offset in 1...6 {
            before = streak(before, after: .completedSession, on: start.adding(days: 8 + offset))
        }
        let last = try #require(before.lastActiveDay)
        let returnDay = last.adding(days: 3)
        #expect(last == ymd(2026, 3, 15))
        #expect(returnDay == ymd(2026, 3, 18))
        #expect(returnDay.days(from: last) - 1 == 2)
        #expect(before.current == 14)
        #expect(before.longest == 14)
        #expect(before.freezes == 1)
        #expect(before.daysTowardNextFreeze == 0)
        #expect(before.freezeUsedDays == [covered])

        let reset = streak(before, after: .completedSession, on: returnDay)

        #expect(reset.current == 1)
        #expect(reset.freezes == 1)
        #expect(reset.daysTowardNextFreeze == 1)
        #expect(reset.longest == 14)
        #expect(reset.freezeUsedDays == before.freezeUsedDays)
        #expect(reset.lastActiveDay == returnDay)
    }

    @Test func threeDayGapResetsEvenWithTwoFreezes() throws {
        let covered = start.adding(days: 7)
        var before = streak(running(days: 7, from: start), after: .completedSession, on: start.adding(days: 8))
        #expect(before.freezeUsedDays == [covered])
        for offset in 1...13 {
            before = streak(before, after: .completedSession, on: start.adding(days: 8 + offset))
        }
        let last = try #require(before.lastActiveDay)
        let returnDay = last.adding(days: 4)
        #expect(last == ymd(2026, 3, 22))
        #expect(returnDay == ymd(2026, 3, 26))
        #expect(returnDay.days(from: last) - 1 == 3)
        #expect(before.current == 21)
        #expect(before.longest == 21)
        #expect(before.freezes == 2)
        #expect(before.daysTowardNextFreeze == 0)
        #expect(before.freezeUsedDays == [covered])

        let reset = streak(before, after: .completedSession, on: returnDay)

        #expect(reset.current == 1)
        #expect(reset.freezes == 2)
        #expect(reset.daysTowardNextFreeze == 0)
        #expect(reset.longest == 21)
        #expect(reset.freezeUsedDays == before.freezeUsedDays)
        #expect(reset.lastActiveDay == returnDay)

        var held = reset
        for offset in 1...7 {
            held = streak(held, after: .completedSession, on: returnDay.adding(days: offset))
            #expect(held.freezes == 2)
            #expect(held.daysTowardNextFreeze == 0)
        }
        #expect(held.current == 8)
    }

    @Test func aResetKeepsZeroOrOneFreezeAsWell() {
        let history = [ymd(2026, 4, 2)]
        let last = ymd(2026, 4, 10)
        let returnDay = ymd(2026, 4, 14)
        #expect(returnDay.days(from: last) - 1 == 3)

        for held in [0, 1] {
            let before = StreakState(
                current: 9,
                longest: 12,
                lastActiveDay: last,
                freezes: held,
                daysTowardNextFreeze: 4,
                freezeUsedDays: history
            )
            let reset = streak(before, after: .completedSession, on: returnDay)
            #expect(reset.current == 1)
            #expect(reset.freezes == held)
            #expect(reset.daysTowardNextFreeze == 1)
            #expect(reset.longest == 12)
            #expect(reset.freezeUsedDays == history)
        }
    }

    @Test func openingTheAppSpendsNothing() {
        let before = running(days: 14, from: start)
        #expect(before.freezes == 2)
        let later = start.adding(days: 20)

        let opened = streak(before, after: .openedApp, on: later)

        #expect(opened == before)
        #expect(opened.freezes == 2)
        #expect(opened.current == 14)
        #expect(opened.freezeUsedDays.isEmpty)
        #expect(opened.lastActiveDay == before.lastActiveDay)
    }

    @Test func clockSetBackChangesNothing() throws {
        let before = running(days: 5, from: start)
        #expect(before.lastActiveDay == start.adding(days: 4))
        let earlier = start.adding(days: -10)

        let last = try #require(before.lastActiveDay)
        let sameDay = streak(before, after: .completedSession, on: last)
        let backward = streak(before, after: .completedSession, on: earlier)
        let openedBackward = streak(before, after: .openedApp, on: earlier)

        #expect(sameDay == before)
        #expect(backward == before)
        #expect(openedBackward == before)
        #expect(backward.freezes == before.freezes)
        #expect(backward.current == 5)
        #expect(backward.freezeUsedDays.isEmpty)
        #expect(earlier.days(from: last) < 0)
    }

    @Test func clockSetForwardIsAcceptedAsThatDay() {
        let before = running(days: 3, from: start)
        #expect(before.current == 3)
        #expect(before.freezes == 0)
        let nextDay = start.adding(days: 3)

        let continued = streak(before, after: .completedSession, on: nextDay)
        #expect(continued.current == 4)
        #expect(continued.longest == 4)
        #expect(continued.lastActiveDay == nextDay)
        #expect(continued.freezes == 0)
        #expect(continued.daysTowardNextFreeze == 4)
        #expect(continued.freezeUsedDays.isEmpty)

        let jumped = start.adding(days: 20)
        #expect(jumped.days(from: nextDay) - 1 >= 3)
        let reset = streak(continued, after: .completedSession, on: jumped)
        #expect(reset.current == 1)
        #expect(reset.longest == 4)
        #expect(reset.freezes == 0)
        #expect(reset.daysTowardNextFreeze == 1)
        #expect(reset.lastActiveDay == jumped)
        #expect(reset.freezeUsedDays.isEmpty)

        let woundBack = streak(reset, after: .completedSession, on: nextDay)
        #expect(woundBack == reset)
    }

    @Test func longestStaysAtTheHighestCurrent() {
        let built = running(days: 9, from: start)
        #expect(built.current == 9)
        #expect(built.longest == 9)

        let resetDay = start.adding(days: 12)
        let reset = streak(built, after: .completedSession, on: resetDay)
        #expect(reset.current == 1)
        #expect(reset.longest == 9)

        var rebuilt = reset
        for offset in 1...8 {
            rebuilt = streak(rebuilt, after: .completedSession, on: resetDay.adding(days: offset))
            #expect(rebuilt.longest == 9)
        }
        #expect(rebuilt.current == 9)
        #expect(rebuilt.longest == 9)

        let past = streak(rebuilt, after: .completedSession, on: resetDay.adding(days: 9))
        #expect(past.current == 10)
        #expect(past.longest == 10)

        let alreadyLonger = StreakState(
            current: 3,
            longest: 12,
            lastActiveDay: start,
            freezes: 0,
            daysTowardNextFreeze: 3,
            freezeUsedDays: []
        )
        let next = streak(alreadyLonger, after: .completedSession, on: start.adding(days: 1))
        #expect(next.current == 4)
        #expect(next.longest == 12)
    }

    @Test func resetStartsTheFreezeCountOver() {
        let before = running(days: 6, from: start)
        #expect(before.freezes == 0)
        #expect(before.daysTowardNextFreeze == 6)
        #expect(before.current == 6)
        let resetDay = start.adding(days: 7)

        let reset = streak(before, after: .completedSession, on: resetDay)
        #expect(reset.current == 1)
        #expect(reset.longest == 6)
        #expect(reset.freezes == 0)
        #expect(reset.daysTowardNextFreeze == 1)
        #expect(reset.freezeUsedDays.isEmpty)

        var state = reset
        for offset in 1...5 {
            state = streak(state, after: .completedSession, on: resetDay.adding(days: offset))
            #expect(state.freezes == 0)
        }
        #expect(state.current == 6)
        #expect(state.daysTowardNextFreeze == 6)

        let earned = streak(state, after: .completedSession, on: resetDay.adding(days: 6))
        #expect(earned.current == 7)
        #expect(earned.freezes == 1)
        #expect(earned.daysTowardNextFreeze == 0)
        #expect(earned.longest == 7)
    }

    @Test func freezeUsedDaysKeepsTheLastThirtyDays() {
        let today = ymd(2026, 3, 31)
        let kept = today.adding(days: -29)
        let dropped = today.adding(days: -30)
        let yesterday = today.adding(days: -1)
        #expect(today.days(from: kept) == 29)
        #expect(today.days(from: dropped) == 30)

        let before = StreakState(
            current: 4,
            longest: 4,
            lastActiveDay: yesterday,
            freezes: 0,
            daysTowardNextFreeze: 4,
            freezeUsedDays: [dropped, kept, dropped]
        )
        let next = streak(before, after: .completedSession, on: today)

        #expect(next.freezeUsedDays == [kept])
        #expect(next.current == 5)
        #expect(next.lastActiveDay == today)

        let opened = streak(before, after: .openedApp, on: today.adding(days: 40))
        #expect(opened.freezeUsedDays == before.freezeUsedDays)

        let sameDay = streak(next, after: .completedSession, on: today)
        #expect(sameDay.freezeUsedDays == [kept])
    }

    @Test func aCoveredDayDropsOutOnTheThirtiethDay() {
        let earned = running(days: 7, from: start)
        let missed = start.adding(days: 7)
        let returnDay = start.adding(days: 8)
        var state = streak(earned, after: .completedSession, on: returnDay)
        #expect(state.freezeUsedDays == [missed])
        #expect(state.freezes == 0)

        var day = returnDay
        let lastKept = missed.adding(days: 29)
        let droppedOn = missed.adding(days: 30)
        while day < droppedOn {
            day = day.adding(days: 1)
            state = streak(state, after: .completedSession, on: day)
            if day <= lastKept {
                #expect(state.freezeUsedDays == [missed])
            }
        }
        #expect(day == droppedOn)
        #expect(droppedOn.days(from: missed) == 30)
        #expect(state.freezeUsedDays.isEmpty)
        #expect(state.lastActiveDay == droppedOn)
    }

    @Test func codableRoundTripUsesCivilDays() throws {
        let state = StreakState(
            current: 8,
            longest: 11,
            lastActiveDay: ymd(2026, 3, 4),
            freezes: 1,
            daysTowardNextFreeze: 1,
            freezeUsedDays: [ymd(2026, 3, 2)]
        )
        let data = try JSONEncoder().encode(state)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"2026-03-04\""))
        #expect(json.contains("\"2026-03-02\""))
        let decoded = try JSONDecoder().decode(StreakState.self, from: data)
        #expect(decoded == state)
    }

    private func running(days: Int, from start: LocalDay) -> StreakState {
        var state = StreakState.initial
        for offset in 0..<days {
            state = streak(state, after: .completedSession, on: start.adding(days: offset))
        }
        return state
    }

    private func ymd(_ year: Int, _ month: Int, _ day: Int) -> LocalDay {
        LocalDay(year: year, month: month, day: day)
    }

    private func timeZone(_ identifier: String) throws -> TimeZone {
        try #require(TimeZone(identifier: identifier), "Time zone \(identifier) is not installed")
    }

    private func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0,
        timeZone: TimeZone
    ) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return try #require(gregorian(timeZone).date(from: components))
    }
}
