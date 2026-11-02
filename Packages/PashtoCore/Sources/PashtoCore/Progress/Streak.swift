import Foundation

/// How the learner met the app on one civil day.
public enum StreakActivity: Hashable, Sendable {
    /// The app was opened. No session was completed.
    case openedApp

    /// A lesson or a review session was completed.
    case completedSession
}

/// The learner's streak and freezes on a civil day.
///
/// A day counts when a session is completed, and the same day never counts
/// twice. Seven counted days earn one freeze. Two is the maximum. A freeze
/// covers one missed day and is spent only when the next session is completed.
///
/// The value is produced by `streak(_:after:on:)`. That function takes the
/// day as a `LocalDay` and does not read a clock. Nothing here is stored.
public struct StreakState: Hashable, Codable, Sendable {
    /// Counted days that earn one freeze.
    public static let daysPerFreeze = 7

    /// Freezes the learner can hold.
    public static let maximumFreezes = 2

    /// How long a covered day stays in `freezeUsedDays`.
    ///
    /// The window is this many civil days, ending on the day the session was
    /// completed. A covered day from 30 days earlier is dropped. A covered
    /// day from 29 days earlier stays.
    public static let freezeHistoryDays = 30

    /// A learner who has not completed a session.
    public static let initial = StreakState(
        current: 0,
        longest: 0,
        lastActiveDay: nil,
        freezes: 0,
        daysTowardNextFreeze: 0,
        freezeUsedDays: []
    )

    /// Counted days in the current run.
    ///
    /// A completed session on a new civil day adds one. A day covered by a
    /// freeze does not.
    public let current: Int

    /// The greatest `current` from this run or an earlier one.
    public let longest: Int

    /// The civil day of the last completed session.
    ///
    /// Nil until the first session is completed.
    public let lastActiveDay: LocalDay?

    /// Freezes still available, from 0 through 2 after a counted day.
    public let freezes: Int

    /// Counted days since the last freeze was earned.
    ///
    /// The seventh counted day earns one freeze and this returns to 0.
    /// While `freezes` is already 2, this stays 0, so a third freeze is not
    /// earned on day 21.
    public let daysTowardNextFreeze: Int

    /// Missed days a freeze covered.
    ///
    /// Each entry is a day the learner did not complete, not the day the
    /// session was completed. After a completed session on a new day, only
    /// days in the last `freezeHistoryDays` remain. Opening the app does not
    /// change the list.
    public let freezeUsedDays: [LocalDay]

    public init(
        current: Int,
        longest: Int,
        lastActiveDay: LocalDay?,
        freezes: Int,
        daysTowardNextFreeze: Int,
        freezeUsedDays: [LocalDay]
    ) {
        self.current = current
        self.longest = longest
        self.lastActiveDay = lastActiveDay
        self.freezes = freezes
        self.daysTowardNextFreeze = daysTowardNextFreeze
        self.freezeUsedDays = freezeUsedDays
    }
}

/// The streak after `activity` on `day`.
///
/// `day` is an argument. This function does not read a clock.
///
/// Opening the app returns `state` unchanged. No day is counted and no
/// freeze is spent, including when one or more days have been missed.
///
/// A completed session counts at most once per civil day. The same day, or
/// any day before `lastActiveDay`, returns `state` unchanged. A clock set
/// back is that earlier day: nothing is reset, no freeze is spent, and the
/// distance is never negative. A clock set forward is the civil day it
/// lands on. The next day continues the streak. A larger jump is a gap of
/// that many missed days.
///
/// Missed days are the civil dates strictly between `lastActiveDay` and
/// `day`. One freeze covers one of them. Two freezes cover two missed days.
/// Freezes are spent only when they cover the whole gap.
///
/// A gap that is not covered resets the streak and keeps every freeze still
/// held. A two-day gap with one freeze resets `current` and leaves that
/// freeze in place. Three or more missed days always reset the streak and
/// keep all held freezes, whether that is 0, 1, or 2. Nothing is spent, so
/// `freezeUsedDays` gains no day.
///
/// A covered day does not increase `current` and does not count toward the
/// next freeze. The completed day does both, including the day that spends
/// a freeze. After a reset the old count toward a freeze is discarded and
/// the completed day is day one of the new run. `daysTowardNextFreeze` is
/// then 1, or 0 when two freezes are still held.
///
/// `longest` becomes `current` when `current` is greater.
public func streak(_ state: StreakState, after activity: StreakActivity, on day: LocalDay) -> StreakState {
    switch activity {
    case .openedApp:
        return state
    case .completedSession:
        return completed(state, on: day)
    }
}

private func completed(_ state: StreakState, on day: LocalDay) -> StreakState {
    guard let lastActiveDay = state.lastActiveDay else {
        return counted(state, on: day, spentFreezes: 0, coveredDays: [])
    }

    let distance = day.days(from: lastActiveDay)
    if distance <= 0 {
        return state
    }

    let missed = distance - 1
    let available = usableFreezes(state.freezes)
    guard missed > 0 else {
        return counted(state, on: day, spentFreezes: 0, coveredDays: [])
    }
    guard missed <= available else {
        return restarted(state, on: day)
    }

    let covered = (1...missed).map { lastActiveDay.adding(days: $0) }
    return counted(state, on: day, spentFreezes: missed, coveredDays: covered)
}

/// Counts `day` after spending `spentFreezes` on `coveredDays`.
private func counted(
    _ state: StreakState,
    on day: LocalDay,
    spentFreezes: Int,
    coveredDays: [LocalDay]
) -> StreakState {
    let current = state.current >= Int.max ? Int.max : max(0, state.current) + 1
    let held = usableFreezes(state.freezes) - spentFreezes
    let earned = nextFreeze(held: held, daysTowardNextFreeze: state.daysTowardNextFreeze)
    return StreakState(
        current: current,
        longest: max(state.longest, current),
        lastActiveDay: day,
        freezes: earned.freezes,
        daysTowardNextFreeze: earned.daysTowardNextFreeze,
        freezeUsedDays: retainedFreezeDays(state.freezeUsedDays + coveredDays, asOf: day)
    )
}

/// Counts `day` as day one of a new run.
///
/// Every freeze still held is kept. A freeze that cannot cover the gap is
/// not spent, and no covered day is recorded. The count toward the next
/// freeze starts over: 1 after this day, or 0 when two freezes are held.
private func restarted(_ state: StreakState, on day: LocalDay) -> StreakState {
    let earned = nextFreeze(held: usableFreezes(state.freezes), daysTowardNextFreeze: 0)
    let current = 1
    return StreakState(
        current: current,
        longest: max(state.longest, current),
        lastActiveDay: day,
        freezes: earned.freezes,
        daysTowardNextFreeze: earned.daysTowardNextFreeze,
        freezeUsedDays: retainedFreezeDays(state.freezeUsedDays, asOf: day)
    )
}

private struct FreezeProgress {
    var freezes: Int
    var daysTowardNextFreeze: Int
}

/// One counted day toward the next freeze.
///
/// At `maximumFreezes` the count stays 0. Otherwise it increases by one, and
/// the seventh day earns one freeze and returns the count to 0.
private func nextFreeze(held: Int, daysTowardNextFreeze: Int) -> FreezeProgress {
    if held >= StreakState.maximumFreezes {
        return FreezeProgress(freezes: StreakState.maximumFreezes, daysTowardNextFreeze: 0)
    }
    let days = max(0, daysTowardNextFreeze) + 1
    guard days >= StreakState.daysPerFreeze else {
        return FreezeProgress(freezes: held, daysTowardNextFreeze: days)
    }
    let freezes = held + 1
    if freezes >= StreakState.maximumFreezes {
        return FreezeProgress(freezes: StreakState.maximumFreezes, daysTowardNextFreeze: 0)
    }
    return FreezeProgress(freezes: freezes, daysTowardNextFreeze: 0)
}

private func usableFreezes(_ freezes: Int) -> Int {
    min(max(freezes, 0), StreakState.maximumFreezes)
}

/// Covered days in the last `freezeHistoryDays`, oldest first, without duplicates.
///
/// A day is kept when fewer than `freezeHistoryDays` civil days have passed
/// since it, including the completed day itself. Days after `today` are not
/// part of that window.
private func retainedFreezeDays(_ days: [LocalDay], asOf today: LocalDay) -> [LocalDay] {
    var kept: [LocalDay] = []
    for day in days.sorted() {
        let age = today.days(from: day)
        guard age >= 0, age < StreakState.freezeHistoryDays else { continue }
        if kept.last != day {
            kept.append(day)
        }
    }
    return kept
}
