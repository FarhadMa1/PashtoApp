import Foundation

/// Why opening the progress store failed.
///
/// A newer schema, snapshot, or session payload is `newerVersion`. Every
/// other failure, including an older snapshot this build cannot migrate, is
/// `other`. The app uses this to choose a screen. It does not open the store.
public enum ProgressOpenFailure: Equatable, Sendable {
    /// The store or the lesson in progress was written by a newer version.
    case newerVersion
    /// The store could not be opened or read for any other reason.
    case other
}

/// The screen the app shows for progress.
///
/// `updateNeeded` is a newer store. That screen does not move or delete the
/// file. `storageError` is every other open failure, and it is the only one
/// that can offer Start over. `welcomeBack` is a break the held freezes do
/// not cover. `ready` is an ordinary open.
public enum ProgressScreen: Equatable, Sendable {
    case updateNeeded
    case storageError
    case welcomeBack
    case ready

    /// Start over moves the store aside. A newer store must not offer it.
    public var canStartOver: Bool {
        self == .storageError
    }
}

/// The screen for a store that could not be opened.
public func progressScreen(for failure: ProgressOpenFailure) -> ProgressScreen {
    switch failure {
    case .newerVersion:
        return .updateNeeded
    case .other:
        return .storageError
    }
}

/// The screen after a store has loaded.
///
/// Welcome back when a completed session on `day` would reset the streak
/// because the missed days are more than the freezes still held. The streak
/// value is not changed here. Opening the app still spends nothing.
/// Freezes stay where `streak(_:after:on:)` leaves them, at most two.
public func progressScreen(streak state: StreakState, on day: LocalDay) -> ProgressScreen {
    streakWouldReset(state, on: day) ? .welcomeBack : .ready
}

/// True when a completed session on `day` starts the streak over.
///
/// The gap is the same one `streak(_:after:on:)` uses. A freeze that covers
/// the gap is not a reset. A day with no earlier session is not a reset.
/// Calling this does not write a new streak.
public func streakWouldReset(_ state: StreakState, on day: LocalDay) -> Bool {
    guard let lastActiveDay = state.lastActiveDay else { return false }
    let missed = day.days(from: lastActiveDay) - 1
    let available = min(max(state.freezes, 0), StreakState.maximumFreezes)
    guard missed > available else { return false }
    let next = streak(state, after: .completedSession, on: day)
    return next.current == 1 && next.freezes == available && next.lastActiveDay == day
}
