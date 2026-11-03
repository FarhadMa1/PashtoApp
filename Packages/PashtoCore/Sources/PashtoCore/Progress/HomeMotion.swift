import Foundation

/// From-values the home plays after a lesson is finished.
///
/// The streak and the daily goal start at these counts. `lessonID` is the
/// segment that fills. The views move to the live counts, then `HomeMotionCue`
/// drops this value. A relaunch builds an empty cue, so nothing replays.
public struct PendingHomeMotion: Equatable, Sendable {
    public var id: UUID
    public var streakFrom: Int
    public var goalFrom: Int
    public var lessonID: LessonID?

    public init(id: UUID, streakFrom: Int, goalFrom: Int, lessonID: LessonID?) {
        self.id = id
        self.streakFrom = streakFrom
        self.goalFrom = goalFrom
        self.lessonID = lessonID
    }
}

/// One home animation waiting to play.
///
/// `stage` keeps the latest finish. `consume` returns that finish once and
/// clears it. The next `consume` returns nil, including on a cue that was
/// never given a finish.
public struct HomeMotionCue: Equatable, Sendable {
    public private(set) var pending: PendingHomeMotion?

    public init() {}

    /// Replaces a finish that is still waiting.
    public mutating func stage(_ motion: PendingHomeMotion) {
        pending = motion
    }

    /// The waiting finish, then nothing. A second call returns nil.
    public mutating func consume() -> PendingHomeMotion? {
        defer { pending = nil }
        return pending
    }
}

/// When the daily-goal success haptic is allowed to play.
///
/// The ring is the new-item count over the stored limit of 5, 10, or 15.
/// The haptic plays when that count crosses from below the limit to the
/// limit or above it. A later increase does not play it again. The drawn
/// fraction never passes a full circle.
public enum DailyGoalCrossing {
    public static func reached(from: Int, to: Int, limit: Int) -> Bool {
        let cap = max(limit, 0)
        guard cap > 0 else { return false }
        return max(0, from) < cap && max(0, to) >= cap
    }

    /// `value / limit`, clamped to 0...1. A limit of 0 draws nothing.
    public static func fraction(_ value: Int, limit: Int) -> Double {
        let cap = max(limit, 0)
        guard cap > 0 else { return 0 }
        return min(1, Double(max(0, value)) / Double(cap))
    }
}
