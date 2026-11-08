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

/// What the home does with one cue.
///
/// `holdFrom` draws the from-values and leaves the cue pending. `animateToFinal`
/// and `jumpToFinal` are the only actions that may consume it, and only after
/// the screen is already showing the live values. Clearing the cue then changes
/// nothing on screen, so the from-to change is not cut off.
public enum HomeMotionAction: Equatable, Sendable {
    case none
    case holdFrom(PendingHomeMotion)
    case animateToFinal(PendingHomeMotion)
    case jumpToFinal(PendingHomeMotion)

    /// True only after the live values are what the screen shows.
    public var consumesCue: Bool {
        switch self {
        case .animateToFinal, .jumpToFinal:
            true
        case .none, .holdFrom:
            false
        }
    }
}

/// The order in which the home plays one finish.
///
/// The from-values are shown first. The live values replace them on a later
/// step, and only that step may consume the cue. A cue that has already
/// reached the live values is not played again. Reduce Motion and VoiceOver
/// go straight to the live values.
public struct HomeMotionPlayback: Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        case idle
        case atFrom(PendingHomeMotion)
        case atFinal(PendingHomeMotion)
    }

    public private(set) var stage: Stage = .idle
    /// True only for the step that moves from the from-values to the live ones.
    public private(set) var animates = false
    private var playedID: UUID?

    public init() {}

    /// The first step for `pending`.
    ///
    /// An empty cue, and a cue that already played, do nothing. Reduce Motion
    /// and VoiceOver show the live values immediately.
    public mutating func prepare(
        _ pending: PendingHomeMotion?,
        reduceMotion: Bool,
        voiceOver: Bool
    ) -> HomeMotionAction {
        guard let pending else { return .none }
        if playedID == pending.id { return .none }
        if reduceMotion || voiceOver {
            animates = false
            stage = .atFinal(pending)
            playedID = pending.id
            return .jumpToFinal(pending)
        }
        if case .atFrom(let current) = stage, current.id == pending.id {
            animates = false
            return .holdFrom(current)
        }
        animates = false
        stage = .atFrom(pending)
        return .holdFrom(pending)
    }

    /// The step after the from-values have been drawn.
    ///
    /// `animated` is false when Reduce Motion or VoiceOver turned on while
    /// those from-values were waiting. A different id, or a cue that already
    /// finished, does nothing.
    public mutating func advance(afterRenderingFrom id: UUID, animated: Bool) -> HomeMotionAction {
        guard case .atFrom(let motion) = stage, motion.id == id, playedID != id else {
            return .none
        }
        animates = animated
        stage = .atFinal(motion)
        playedID = id
        return animated ? .animateToFinal(motion) : .jumpToFinal(motion)
    }

    /// The streak number on screen.
    ///
    /// Reduce Motion and VoiceOver use `live`. So does a cue that has reached
    /// its final step. Until then the from-value is what is shown, including
    /// on the first frame before `prepare`.
    public func displayedStreak(
        live: Int,
        pending: PendingHomeMotion?,
        reduceMotion: Bool,
        voiceOver: Bool
    ) -> Int {
        displayed(live: live, from: \.streakFrom, pending: pending, reduceMotion: reduceMotion, voiceOver: voiceOver)
    }

    /// The daily-goal count on screen. The same rules as `displayedStreak`.
    public func displayedGoal(
        live: Int,
        pending: PendingHomeMotion?,
        reduceMotion: Bool,
        voiceOver: Bool
    ) -> Int {
        displayed(live: live, from: \.goalFrom, pending: pending, reduceMotion: reduceMotion, voiceOver: voiceOver)
    }

    /// The lesson whose path segment is still empty.
    ///
    /// Nil once the live path is shown, and nil for Reduce Motion and VoiceOver.
    public func waitingLessonID(
        pending: PendingHomeMotion?,
        reduceMotion: Bool,
        voiceOver: Bool
    ) -> LessonID? {
        if reduceMotion || voiceOver { return nil }
        switch stage {
        case .idle:
            return pending?.lessonID
        case .atFrom(let motion):
            return motion.lessonID
        case .atFinal:
            return nil
        }
    }

    private func displayed(
        live: Int,
        from keyPath: KeyPath<PendingHomeMotion, Int>,
        pending: PendingHomeMotion?,
        reduceMotion: Bool,
        voiceOver: Bool
    ) -> Int {
        if reduceMotion || voiceOver { return live }
        switch stage {
        case .idle:
            return pending.map { $0[keyPath: keyPath] } ?? live
        case .atFrom(let motion):
            return motion[keyPath: keyPath]
        case .atFinal:
            return live
        }
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
