import Foundation

/// One streak event the home may show once.
///
/// The day is the civil day already stored on the streak: a covered day in
/// `freezeUsedDays`, or `lastActiveDay` when a freeze is earned. That stored
/// day is the identity. The home claims it once. A later visit, including a
/// relaunch with an empty cue, does not play it again.
public struct StreakEventID: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A freeze covered this missed day.
        case rescuedDay
        /// This counted day earned a freeze.
        case freezeEarned
    }

    public var kind: Kind
    public var day: LocalDay

    public init(kind: Kind, day: LocalDay) {
        self.kind = kind
        self.day = day
    }
}

/// Events drawn from a streak change. Nothing here reads a clock.
///
/// A rescued day is a new entry in `freezeUsedDays`. A freeze is earned only
/// when a counted day, not a reset, reaches seven days toward the next freeze
/// and the learner is still under the maximum. Spending a freeze on the same
/// day does not hide the earn. Day 21, with two freezes already held, earns
/// nothing. The same streak twice is not an event.
public enum StreakMotion {
    /// Snowflake fading in over the rescued day.
    public static let rescueFade: TimeInterval = 0.35
    /// Larger saffron star. The same family as the finished-lesson star, shorter.
    public static let freezeStar: TimeInterval = 0.45

    public static func events(before: StreakState, after: StreakState) -> [StreakEventID] {
        guard before != after else { return [] }
        let known = Set(before.freezeUsedDays)
        var result: [StreakEventID] = []
        for day in after.freezeUsedDays where !known.contains(day) {
            result.append(StreakEventID(kind: .rescuedDay, day: day))
        }
        if let day = after.lastActiveDay, earnedFreeze(before: before, after: after) {
            result.append(StreakEventID(kind: .freezeEarned, day: day))
        }
        return result
    }

    /// A counted day pushed the freeze forward. A reset starts again at one.
    private static func earnedFreeze(before: StreakState, after: StreakState) -> Bool {
        let continued = before.current < Int.max
            && after.current == before.current + 1
            && after.lastActiveDay != before.lastActiveDay
        guard continued else { return false }
        let known = Set(before.freezeUsedDays)
        let rescued = after.freezeUsedDays.reduce(into: 0) { count, day in
            if !known.contains(day) { count += 1 }
        }
        let held = min(max(before.freezes, 0), StreakState.maximumFreezes) - rescued
        guard held < StreakState.maximumFreezes else { return false }
        return max(0, before.daysTowardNextFreeze) + 1 >= StreakState.daysPerFreeze
    }
}

/// The snowflake. Reduce Motion shows it. It has no words.
public enum RescueMotion: Equatable, Sendable {
    case fade
    case shown

    public static func style(reduceMotion: Bool) -> RescueMotion {
        reduceMotion ? .shown : .fade
    }

    public var duration: TimeInterval {
        switch self {
        case .fade:
            StreakMotion.rescueFade
        case .shown:
            0
        }
    }
}

/// The freeze star. Reduce Motion, VoiceOver, and a tap show the resting star.
public enum FreezeStarMotion: Equatable, Sendable {
    case unfold
    case final

    public static func style(reduceMotion: Bool, voiceOver: Bool, skipped: Bool) -> FreezeStarMotion {
        (reduceMotion || voiceOver || skipped) ? .final : .unfold
    }

    public var duration: TimeInterval {
        switch self {
        case .unfold:
            StreakMotion.freezeStar
        case .final:
            0
        }
    }
}

/// What VoiceOver is given for the freeze star.
///
/// The label is the streak sentence already on the home. The star does not
/// post another announcement and does not add words.
public enum FreezeStarSpeech {
    public static let postsAnnouncement = false

    public static func label(count: Int, dayStreak: String = CelebrationCopy.dayStreak) -> String {
        CelebrationCopy.streakSpoken(count, label: dayStreak)
    }
}

/// Rescue and freeze events waiting to play.
///
/// `stage` keeps an identity once. `claim` returns that kind and remembers it.
/// A second claim, a later stage of the same day, and a new empty cue all
/// return nothing, so coming back to the home does not replay the event.
public struct StreakMotionCue: Equatable, Sendable {
    public private(set) var pending: [StreakEventID] = []
    private var played: Set<StreakEventID> = []

    public init() {}

    public mutating func stage(_ events: [StreakEventID]) {
        for event in events where !played.contains(event) && !pending.contains(event) {
            pending.append(event)
        }
    }

    /// The waiting events of `kind`, then nothing.
    public mutating func claim(_ kind: StreakEventID.Kind) -> [StreakEventID] {
        let claimed = pending.filter { $0.kind == kind }
        guard !claimed.isEmpty else { return [] }
        pending.removeAll { $0.kind == kind }
        played.formUnion(claimed)
        return claimed
    }
}
