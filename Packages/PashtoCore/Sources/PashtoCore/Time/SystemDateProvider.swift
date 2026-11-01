import Foundation

/// The process clock.
///
/// `scripts/linux-guard.sh` allows this file to read that clock. Every other
/// type takes a `DateProvider`, usually `FixedDateProvider` in tests.
public struct SystemDateProvider: DateProvider {
    public init() {}

    public var now: Date {
        Date()
    }
}
