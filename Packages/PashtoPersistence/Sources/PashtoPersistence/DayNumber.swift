import Foundation
import PashtoCore

/// `LocalDay` stored as a day count.
///
/// `LocalDay` has no `dayNumber` property. The count is the user's local
/// calendar day as days since 1970-01-01, the same number `days(from:)`
/// returns in PashtoCore. It is not the UTC date of an instant. The core
/// counts those civil dates with a Gregorian calendar fixed to UTC only so
/// a 23-hour or 25-hour local day still counts as one. A number outside
/// year 1...9999 throws instead of trapping.
enum DayNumber {
    static let epoch = LocalDay(year: 1970, month: 1, day: 1)

    private static let earliest = LocalDay(year: 1, month: 1, day: 1).days(from: epoch)
    private static let latest = LocalDay(year: 9999, month: 12, day: 31).days(from: epoch)

    static func encode(_ day: LocalDay) -> Int {
        day.days(from: epoch)
    }

    static func decode(_ number: Int) throws -> LocalDay {
        guard (earliest...latest).contains(number) else {
            throw ProgressPersistenceError.invalidDayNumber(number)
        }
        return epoch.adding(days: number)
    }
}
