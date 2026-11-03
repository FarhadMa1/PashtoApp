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

/// The screen when the finished lesson still cannot be saved.
///
/// One answer that fails does not use this screen: the quiz stays up and the
/// save is tried again. This is the existing storage error. It does not
/// choose a new message, and it does not remove progress the store already kept.
public func screenAfterFailedLessonSave() -> ProgressScreen {
    .storageError
}

/// Why the storage error is on screen.
///
/// The screen is the same in every case. The reason chooses Start over and
/// what Try again does.
public enum StorageErrorReason: Equatable, Sendable {
    /// The course files are missing or cannot be decoded.
    case courseUnreadable
    /// The progress store could not be opened or read at launch.
    case progressUnreadable
    /// The finished lesson could not be saved.
    case lessonSaveFailed
    /// The progress store could not be read while a lesson was opening.
    case lessonOpenUnreadable
}

/// What the storage error offers for `reason`.
///
/// A missing course, a failed lesson save, and a failed read while opening a
/// lesson offer Try again only. A progress store that cannot be opened at
/// launch also offers Start over. Try again reloads the course and the store,
/// except after a failed lesson save, where it retries that save.
public struct StorageErrorActions: Equatable, Sendable {
    public var showsStartOver: Bool
    /// True when Try again retries the finished lesson. False when it reloads.
    public var retriesLessonSave: Bool

    public init(showsStartOver: Bool, retriesLessonSave: Bool) {
        self.showsStartOver = showsStartOver
        self.retriesLessonSave = retriesLessonSave
    }
}

/// The buttons and the Try again action for `reason`.
public func storageErrorActions(for reason: StorageErrorReason) -> StorageErrorActions {
    switch reason {
    case .courseUnreadable:
        StorageErrorActions(showsStartOver: false, retriesLessonSave: false)
    case .progressUnreadable:
        StorageErrorActions(showsStartOver: true, retriesLessonSave: false)
    case .lessonSaveFailed:
        StorageErrorActions(showsStartOver: false, retriesLessonSave: true)
    case .lessonOpenUnreadable:
        StorageErrorActions(showsStartOver: false, retriesLessonSave: false)
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

/// The streak number the home shows on `day`.
///
/// Freezes that still cover the missed days leave the stored count on screen.
/// A gap those freezes cannot cover shows 0. The stored streak is not written,
/// and opening the app still spends nothing. `streakWouldReset` is the gap.
public func displayedStreakCount(_ state: StreakState, on day: LocalDay) -> Int {
    guard !streakWouldReset(state, on: day) else { return 0 }
    return max(0, state.current)
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
