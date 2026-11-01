import Foundation

/// A clock. Scheduling and tests take one of these instead of reading the
/// process clock themselves.
public protocol DateProvider: Sendable {
    var now: Date { get }
}

/// A clock fixed at one instant.
///
/// Tests assign `now` to move time, including setting the clock backwards.
public struct FixedDateProvider: DateProvider {
    public var now: Date

    public init(now: Date) {
        self.now = now
    }
}

/// Today's `LocalDay` for a clock and a time zone.
///
/// The calendar identifier is not stored. `today` is the Gregorian date in
/// `timeZone` at `provider.now`.
public struct DayClock<Provider: DateProvider>: Sendable {
    public var provider: Provider
    public var timeZone: TimeZone

    public init(provider: Provider, timeZone: TimeZone) {
        self.provider = provider
        self.timeZone = timeZone
    }

    /// Keeps `calendar.timeZone` and drops its identifier.
    public init(provider: Provider, calendar: Calendar) {
        self.init(provider: provider, timeZone: calendar.timeZone)
    }

    public var today: LocalDay {
        LocalDay(date: provider.now, timeZone: timeZone)
    }

    /// Elapsed civil days from `stored` to `today`, never negative.
    ///
    /// See `LocalDay.nonNegativeDays(from:to:)`.
    public func nonNegativeDays(since stored: LocalDay) -> Int {
        LocalDay.nonNegativeDays(from: stored, to: today)
    }
}
