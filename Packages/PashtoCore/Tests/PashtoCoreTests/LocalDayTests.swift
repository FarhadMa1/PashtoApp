import Foundation
import Testing
@testable import PashtoCore

struct LocalDayTests {
    @Test func midnightInOsloAndKabul() throws {
        let oslo = try timeZone("Europe/Oslo")
        let kabul = try timeZone("Asia/Kabul")
        let utc = try #require(TimeZone(secondsFromGMT: 0))

        let osloMidnight = try date(year: 2026, month: 11, day: 1, timeZone: oslo)
        let beforeOsloMidnight = try date(
            year: 2026, month: 10, day: 31,
            hour: 23, minute: 59, second: 59,
            timeZone: oslo
        )
        #expect(oslo.secondsFromGMT(for: osloMidnight) == 60 * 60)
        #expect(LocalDay(date: beforeOsloMidnight, calendar: gregorian(oslo)) == ymd(2026, 10, 31))
        #expect(LocalDay(date: osloMidnight, calendar: gregorian(oslo)) == ymd(2026, 11, 1))
        #expect(LocalDay(date: osloMidnight, timeZone: oslo).days(from: LocalDay(date: beforeOsloMidnight, timeZone: oslo)) == 1)

        let kabulMidnight = try date(year: 2026, month: 11, day: 1, timeZone: kabul)
        let beforeKabulMidnight = try date(
            year: 2026, month: 10, day: 31,
            hour: 23, minute: 59, second: 59,
            timeZone: kabul
        )
        #expect(kabul.secondsFromGMT(for: kabulMidnight) == 4 * 60 * 60 + 30 * 60)
        #expect(LocalDay(date: beforeKabulMidnight, calendar: gregorian(kabul)) == ymd(2026, 10, 31))
        #expect(LocalDay(date: kabulMidnight, calendar: gregorian(kabul)) == ymd(2026, 11, 1))

        let utcParts = gregorian(utc).dateComponents([.month, .day, .hour, .minute], from: kabulMidnight)
        #expect(utcParts.month == 10)
        #expect(utcParts.day == 31)
        #expect(utcParts.hour == 19)
        #expect(utcParts.minute == 30)
        #expect(LocalDay(date: kabulMidnight, timeZone: utc) == ymd(2026, 10, 31))
    }

    @Test func daylightSavingDistanceInOslo() throws {
        let oslo = try timeZone("Europe/Oslo")

        // 2026-03-29 is the spring-forward day: local midnight to the next is 23 hours.
        let springStart = try date(year: 2026, month: 3, day: 29, timeZone: oslo)
        let springEnd = try date(year: 2026, month: 3, day: 30, timeZone: oslo)
        #expect(springEnd.timeIntervalSince(springStart) == 23 * 60 * 60)
        let springStartDay = LocalDay(date: springStart, calendar: gregorian(oslo))
        let springEndDay = LocalDay(date: springEnd, calendar: gregorian(oslo))
        #expect(springStartDay == ymd(2026, 3, 29))
        #expect(springEndDay == ymd(2026, 3, 30))
        #expect(springEndDay.days(from: springStartDay) == 1)
        #expect(springStartDay.adding(days: 1) == springEndDay)

        // 2026-10-25 is the fall-back day: local midnight to the next is 25 hours.
        let fallStart = try date(year: 2026, month: 10, day: 25, timeZone: oslo)
        let fallEnd = try date(year: 2026, month: 10, day: 26, timeZone: oslo)
        #expect(fallEnd.timeIntervalSince(fallStart) == 25 * 60 * 60)
        let fallStartDay = LocalDay(date: fallStart, timeZone: oslo)
        let fallEndDay = LocalDay(date: fallEnd, timeZone: oslo)
        #expect(fallEndDay.days(from: fallStartDay) == 1)
        #expect(fallStartDay.adding(days: 1) == fallEndDay)

        let beforeSpring = LocalDay(date: try date(year: 2026, month: 3, day: 28, timeZone: oslo), timeZone: oslo)
        #expect(springEndDay.days(from: beforeSpring) == 2)
        #expect(beforeSpring.adding(days: 2) == springEndDay)
    }

    @Test func persianCalendarStillYieldsGregorianDay() throws {
        let kabul = try timeZone("Asia/Kabul")
        let instant = try date(year: 2026, month: 11, day: 1, hour: 12, timeZone: kabul)
        var persian = Calendar(identifier: .persian)
        persian.timeZone = kabul
        persian.locale = Locale(identifier: "fa_IR")

        let persianParts = persian.dateComponents([.year, .month, .day], from: instant)
        let persianYear = try #require(persianParts.year)
        #expect(persianYear != 2026)

        let day = LocalDay(date: instant, calendar: persian)
        #expect(day == LocalDay(year: 2026, month: 11, day: 1))
        #expect(day.year != persianYear)
    }

    @Test func sameInstantDiffersAcrossTimeZones() throws {
        let oslo = try timeZone("Europe/Oslo")
        let kabul = try timeZone("Asia/Kabul")
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        // 20:00 UTC is 21:00 in Oslo (UTC+1) and 00:30 the next day in Kabul (UTC+4:30).
        let instant = try date(year: 2026, month: 11, day: 1, hour: 20, timeZone: utc)

        let osloDay = LocalDay(date: instant, calendar: gregorian(oslo))
        let kabulDay = LocalDay(date: instant, calendar: gregorian(kabul))
        #expect(osloDay == ymd(2026, 11, 1))
        #expect(kabulDay == ymd(2026, 11, 2))
        #expect(osloDay != kabulDay)

        var clock = DayClock(provider: FixedDateProvider(now: instant), timeZone: oslo)
        #expect(clock.today == osloDay)
        clock.timeZone = kabul
        #expect(clock.today == kabulDay)
    }

    @Test func clockSetBackDoesNotProduceNegativeDistance() throws {
        let oslo = try timeZone("Europe/Oslo")
        let later = try date(year: 2026, month: 11, day: 5, hour: 15, timeZone: oslo)
        let earlier = try date(year: 2026, month: 11, day: 1, hour: 9, timeZone: oslo)

        var provider = FixedDateProvider(now: later)
        var clock = DayClock(provider: provider, calendar: gregorian(oslo))
        let stored = clock.today
        #expect(stored == ymd(2026, 11, 5))

        provider.now = earlier
        clock.provider = provider
        let today = clock.today
        #expect(today == ymd(2026, 11, 1))
        #expect(today.days(from: stored) == -4)
        #expect(LocalDay.nonNegativeDays(from: stored, to: today) == 0)
        #expect(clock.nonNegativeDays(since: stored) == 0)
        #expect(LocalDay.nonNegativeDays(from: today, to: stored) == stored.days(from: today))
        #expect(clock.nonNegativeDays(since: today.adding(days: -2)) == 2)
    }

    @Test func systemDateProviderReadsTheProcessClock() {
        let now = SystemDateProvider().now
        #expect(now > Date(timeIntervalSince1970: 1_700_000_000))
        #expect(now < Date(timeIntervalSince1970: 2_000_000_000))
    }

    @Test func codableRoundTripUsesTheStableString() throws {
        let day = LocalDay(year: 2026, month: 11, day: 1)
        #expect(day.isoDay == "2026-11-01")
        #expect(day.description == "2026-11-01")
        #expect(String(describing: day) == "2026-11-01")

        let data = try JSONEncoder().encode(day)
        #expect(String(decoding: data, as: UTF8.self) == "\"2026-11-01\"")
        let decoded = try JSONDecoder().decode(LocalDay.self, from: data)
        #expect(decoded == day)

        let padded = LocalDay(year: 2026, month: 1, day: 2)
        #expect(padded.isoDay == "2026-01-02")
        let paddedData = try JSONEncoder().encode(padded)
        #expect(try JSONDecoder().decode(LocalDay.self, from: paddedData) == padded)

        let leap = LocalDay(year: 2024, month: 2, day: 29)
        #expect(leap.isoDay == "2024-02-29")
        #expect(try JSONDecoder().decode(LocalDay.self, from: JSONEncoder().encode(leap)) == leap)

        let rejected = [
            "2026-11-1",
            "2026-11-01T00:00:00Z",
            "2023-02-29",
            "1900-02-29",
            "2026-13-01",
            "2026-00-01",
            "2026-11-00",
            "26-11-01",
            "2026/11/01",
            "",
        ]
        for text in rejected {
            let payload = Data("\"\(text)\"".utf8)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(LocalDay.self, from: payload)
            }
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LocalDay.self, from: Data("20261101".utf8))
        }

        #expect(day > ymd(2026, 10, 31))
        #expect(Set([day, day, padded]).count == 2)
    }

    @Test func leapDayAndYearBoundary() {
        let leap = ymd(2024, 2, 28)
        #expect(leap.adding(days: 1) == ymd(2024, 2, 29))
        #expect(leap.adding(days: 2) == ymd(2024, 3, 1))
        #expect(ymd(2024, 3, 1).days(from: leap) == 2)
        #expect(ymd(2024, 2, 29).adding(days: 0) == ymd(2024, 2, 29))

        #expect(ymd(2023, 2, 28).adding(days: 1) == ymd(2023, 3, 1))
        #expect(ymd(1900, 2, 28).adding(days: 1) == ymd(1900, 3, 1))
        #expect(ymd(2000, 2, 28).adding(days: 1) == ymd(2000, 2, 29))
        #expect(ymd(2000, 2, 29).adding(days: 1) == ymd(2000, 3, 1))

        let newYearsEve = ymd(2025, 12, 31)
        let newYearsDay = ymd(2026, 1, 1)
        #expect(newYearsEve.adding(days: 1) == newYearsDay)
        #expect(newYearsDay.adding(days: -1) == newYearsEve)
        #expect(newYearsDay.days(from: newYearsEve) == 1)
        #expect(newYearsEve.days(from: newYearsDay) == -1)
        #expect(newYearsEve < newYearsDay)
        #expect(newYearsDay.days(from: newYearsDay) == 0)
        #expect(LocalDay.nonNegativeDays(from: newYearsDay, to: newYearsEve) == 0)
        #expect(LocalDay.nonNegativeDays(from: newYearsEve, to: newYearsDay) == 1)
    }

    private func ymd(_ year: Int, _ month: Int, _ day: Int) -> LocalDay {
        LocalDay(year: year, month: month, day: day)
    }

    private func timeZone(_ identifier: String) throws -> TimeZone {
        try #require(TimeZone(identifier: identifier))
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
