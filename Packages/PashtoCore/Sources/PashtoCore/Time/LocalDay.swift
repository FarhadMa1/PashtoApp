import Foundation

/// A Gregorian calendar day with no time of day and no time zone.
///
/// The value is the civil date: year, month, and day. Two instants on the
/// same local date are the same `LocalDay`, including when daylight saving
/// makes that date 23 or 25 hours long.
///
/// A day built from a `Date` always uses the Gregorian calendar in the time
/// zone of the calendar that was passed in. A Persian or other identifier
/// on that calendar does not change the year, month, or day.
///
/// The stable text form is `YYYY-MM-DD`, for example `2026-11-01`.
/// `Codable` and `description` both use it.
public struct LocalDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// `year`, `month`, and `day` must be a real Gregorian date from year 1 through 9999.
    public init(year: Int, month: Int, day: Int) {
        precondition(
            GregorianCalendar.isValid(year: year, month: month, day: day),
            "\(year)-\(month)-\(day) is not a Gregorian date in 0001...9999"
        )
        self.year = year
        self.month = month
        self.day = day
    }

    /// The Gregorian date of `date` in `calendar.timeZone`.
    ///
    /// `calendar`'s identifier is ignored. The device calendar can be Persian
    /// or anything else; the result is still the Gregorian year, month, and day.
    public init(date: Date, calendar: Calendar) {
        self.init(date: date, timeZone: calendar.timeZone)
    }

    /// The Gregorian date of `date` in `timeZone`.
    public init(date: Date, timeZone: TimeZone) {
        let parts = GregorianCalendar.parts(of: date, timeZone: timeZone)
        self.init(year: parts.year, month: parts.month, day: parts.day)
    }

    /// The day `days` civil days after this one. A negative value goes backward.
    ///
    /// This moves a Gregorian date by whole days. It does not add a fixed
    /// number of seconds, so a daylight-saving transition does not change
    /// which date comes back.
    public func adding(days: Int) -> LocalDay {
        let shifted = GregorianCalendar.adding(days: days, to: self)
        return LocalDay(year: shifted.year, month: shifted.month, day: shifted.day)
    }

    /// Signed number of civil days from `other` to this day.
    ///
    /// One means this day is the next Gregorian date after `other`. The count
    /// is whole dates, not elapsed seconds, so a 23-hour or 25-hour
    /// daylight-saving day still counts as one day. The result is negative
    /// when this day is earlier than `other`.
    public func days(from other: LocalDay) -> Int {
        GregorianCalendar.days(from: other, to: self)
    }

    /// Days from `start` to `end`, clamped at zero.
    ///
    /// `days(from:)` is a signed distance. A stored day can be later than
    /// today when the clock was set back, and that distance is then negative.
    /// Callers that want an elapsed interval use this and get zero instead.
    public static func nonNegativeDays(from start: LocalDay, to end: LocalDay) -> Int {
        max(0, end.days(from: start))
    }

    /// `YYYY-MM-DD`, for example `2026-11-01`.
    public var isoDay: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { isoDay }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let parts = Self.parseISODay(text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "LocalDay must be a Gregorian date YYYY-MM-DD. Got \"\(text)\"."
            )
        }
        self.init(year: parts.year, month: parts.month, day: parts.day)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoDay)
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static func parseISODay(_ text: String) -> (year: Int, month: Int, day: Int)? {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count == 10, scalars[4] == "-", scalars[7] == "-" else { return nil }
        guard let year = asciiInt(scalars[0..<4]),
              let month = asciiInt(scalars[5..<7]),
              let day = asciiInt(scalars[8..<10]),
              GregorianCalendar.isValid(year: year, month: month, day: day)
        else { return nil }
        return (year, month, day)
    }

    private static func asciiInt(_ scalars: ArraySlice<Unicode.Scalar>) -> Int? {
        var value = 0
        guard !scalars.isEmpty else { return nil }
        for scalar in scalars {
            guard scalar >= "0", scalar <= "9" else { return nil }
            value = value * 10 + Int(scalar.value - Unicode.Scalar("0").value)
        }
        return value
    }
}

/// Gregorian day arithmetic in UTC, so a local 23-hour or 25-hour day never
/// enters the count. Callers pass a time zone only when turning a `Date`
/// into a civil date.
private enum GregorianCalendar {
    static let utc: TimeZone = {
        guard let timeZone = TimeZone(secondsFromGMT: 0) else {
            preconditionFailure("UTC is required to count Gregorian days")
        }
        return timeZone
    }()

    static func make(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// `date(from:)` overflows an invalid day (31 February becomes March).
    /// A date counts only when the components come back unchanged.
    static func isValid(year: Int, month: Int, day: Int) -> Bool {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            return false
        }
        let calendar = make(timeZone: utc)
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return false }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == day
    }

    static func parts(of date: Date, timeZone: TimeZone) -> (year: Int, month: Int, day: Int) {
        let components = make(timeZone: timeZone).dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            preconditionFailure("Gregorian calendar did not return a year, month, and day")
        }
        return (year, month, day)
    }

    static func adding(days: Int, to day: LocalDay) -> (year: Int, month: Int, day: Int) {
        let calendar = make(timeZone: utc)
        let start = date(year: day.year, month: day.month, day: day.day, calendar: calendar)
        guard let shifted = calendar.date(byAdding: .day, value: days, to: start) else {
            preconditionFailure("Could not add \(days) days to \(day.isoDay)")
        }
        return parts(of: shifted, timeZone: utc)
    }

    static func days(from start: LocalDay, to end: LocalDay) -> Int {
        let calendar = make(timeZone: utc)
        let startDate = date(year: start.year, month: start.month, day: start.day, calendar: calendar)
        let endDate = date(year: end.year, month: end.month, day: end.day, calendar: calendar)
        guard let days = calendar.dateComponents([.day], from: startDate, to: endDate).day else {
            preconditionFailure("Could not count days from \(start.isoDay) to \(end.isoDay)")
        }
        return days
    }

    private static func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else {
            preconditionFailure("\(year)-\(month)-\(day) is not a Gregorian date")
        }
        return date
    }
}
