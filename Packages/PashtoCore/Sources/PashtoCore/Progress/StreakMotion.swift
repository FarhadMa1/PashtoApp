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
    /// The same snowflake, opacity only, when Reduce Motion is on.
    public static let rescueReduceFade: TimeInterval = QuizMotion.reduceMotionFade
    /// Larger saffron star unfolding. The same family as the finished-lesson star, shorter.
    public static let freezeStar: TimeInterval = 0.45
    /// Still time after the unfold, before the star leaves. With the unfold and the exit this is 1.5s.
    public static let freezeHold: TimeInterval = 0.70
    /// Shrink and fade toward the streak icon, then the overlay is gone.
    public static let freezeDismiss: TimeInterval = 0.35
    /// Reduce Motion fade in, and the matching fade out. Opacity only.
    public static let freezeReduceFade: TimeInterval = QuizMotion.reduceMotionFade
    /// Still time between those two fades.
    public static let freezeReduceHold: TimeInterval = 0.80
    /// The celebration, including its exit, stays within this.
    public static let freezeMaximum: TimeInterval = 1.5

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

/// The snowflake. Both motions are an opacity fade. It has no words.
public enum RescueMotion: Equatable, Sendable {
    /// 0.35s fade over the streak icon.
    case fade
    /// Reduce Motion. 0.2s opacity fade, with no other movement.
    case calm

    public static func style(reduceMotion: Bool) -> RescueMotion {
        reduceMotion ? .calm : .fade
    }

    public var duration: TimeInterval {
        switch self {
        case .fade:
            StreakMotion.rescueFade
        case .calm:
            StreakMotion.rescueReduceFade
        }
    }

    /// The glyph does not scale, turn, or travel.
    public var opacityOnly: Bool { true }
}

/// Where the snowflake is drawn, and the colours actually used.
///
/// The glyph is badge ink on a badge circle. Saffron is the streak star behind
/// that circle, not the colour under the glyph. Both badge pairs clear 3:1.
public enum RescueMark {
    public static let glyph = QuizResultPalette.badgeInk
    public static let backingLight = QuizResultPalette.badgeLight
    public static let backingDark = QuizResultPalette.badgeDark
    /// Light and dark saffron. Measured so the glyph is not put back on the star.
    public static let saffronLight: UInt32 = 0xE8A33D
    public static let saffronDark: UInt32 = 0xF2B85B

    public static let pairs: [QuizResultPalette.ContrastPair] = [
        QuizResultPalette.ContrastPair(
            name: "snowflake on the badge, light",
            foreground: glyph,
            background: backingLight,
            minimumRatio: 3
        ),
        QuizResultPalette.ContrastPair(
            name: "snowflake on the badge, dark",
            foreground: glyph,
            background: backingDark,
            minimumRatio: 3
        ),
    ]
}

/// Sizes for the freeze celebration and the snowflake.
///
/// The star is larger than the lesson-finish star and lives in its own card,
/// under the streak row. It is not drawn in the 28pt icon, so the count stays
/// clear. The snowflake badge is smaller than that icon and stays inside it.
public enum FreezeCelebrationLayout {
    /// The lesson-finish star. Larger than the streak icon.
    public static let lessonStarSide: Double = 104
    public static let starSide: Double = 128
    public static let cardHeight: Double = 220
    public static let cornerRadius: Double = 28
    public static let streakIconSide: Double = 28
    public static let rescueBadgeSide: Double = 22
    public static let rescueGlyphSide: Double = 12
    public static let hostsStarInStreakIcon = false
    public static let coversStreakLabel = false
    public static let showsGirih = true
    public static let outlineUsesRing = true

    public static var starFitsInCard: Bool {
        starSide > lessonStarSide && starSide < cardHeight
    }

    public static var rescueFitsInIcon: Bool {
        rescueGlyphSide < rescueBadgeSide && rescueBadgeSide < streakIconSide
    }
}

/// One pose of the freeze star.
public struct FreezeStarFrame: Equatable, Sendable {
    public var opacity: Double
    public var scale: Double
    public var rotationDegrees: Double
    public var offsetTowardIcon: Double
    public var girihOpacity: Double

    public init(
        opacity: Double,
        scale: Double,
        rotationDegrees: Double,
        offsetTowardIcon: Double,
        girihOpacity: Double
    ) {
        self.opacity = opacity
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.offsetTowardIcon = offsetTowardIcon
        self.girihOpacity = girihOpacity
    }

    public var showsGirih: Bool { girihOpacity > 0 }
    public var travels: Bool { offsetTowardIcon != 0 }

    /// Scale 1, no turn, and no travel. Reduce Motion stays here and only changes opacity.
    public var isStill: Bool {
        scale == 1 && rotationDegrees == 0 && offsetTowardIcon == 0
    }
}

/// One beat of the freeze celebration.
public struct FreezeStarPhase: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case unfold
        case fadeIn
        case hold
        case settle
        case fadeOut
        case gone
    }

    public var step: Step
    public var duration: TimeInterval
    public var starts: FreezeStarFrame
    public var ends: FreezeStarFrame

    public init(step: Step, duration: TimeInterval, starts: FreezeStarFrame, ends: FreezeStarFrame) {
        self.step = step
        self.duration = duration
        self.starts = starts
        self.ends = ends
    }
}

/// The whole freeze celebration.
///
/// Motion unfolds, holds, then shrinks and fades toward the streak icon.
/// Reduce Motion fades in, holds, and fades out. That path does not scale,
/// turn, or travel. A tap removes the card at once. Without VoiceOver the
/// timeline removes it too. With VoiceOver the same entrance plays and the
/// card then stays until a tap or leaving the home. Speech finishing does
/// not remove it. The card's one label is the final streak count and the
/// earned line. The phases are not spoken, and a second announcement is not posted.
public struct FreezeStarPlan: Equatable, Sendable {
    public var phases: [FreezeStarPhase]
    /// The timeline may remove the card when this is true. VoiceOver leaves it false.
    public var removesOverlay: Bool

    public init(phases: [FreezeStarPhase], removesOverlay: Bool) {
        self.phases = phases
        self.removesOverlay = removesOverlay
    }

    public var duration: TimeInterval {
        phases.reduce(0) { $0 + $1.duration }
    }

    /// No phase changes scale, rotation, or travel.
    public var opacityOnly: Bool {
        phases.allSatisfy { $0.starts.isStill && $0.ends.isStill }
    }

    /// VoiceOver uses the same entrance, then keeps the card. It does not add an exit.
    public static func make(reduceMotion: Bool, voiceOver: Bool, skipped: Bool) -> FreezeStarPlan {
        if skipped { return skippedPlan }
        if voiceOver {
            return reduceMotion ? calmHeldPlan : movingHeldPlan
        }
        return reduceMotion ? calmPlan : movingPlan
    }

    private static let rest = FreezeStarFrame(
        opacity: 1, scale: 1, rotationDegrees: 0, offsetTowardIcon: 0, girihOpacity: 1
    )
    private static let folded = FreezeStarFrame(
        opacity: 0, scale: 0.3, rotationDegrees: -45, offsetTowardIcon: 0, girihOpacity: 0
    )
    private static let stillHidden = FreezeStarFrame(
        opacity: 0, scale: 1, rotationDegrees: 0, offsetTowardIcon: 0, girihOpacity: 0
    )
    private static let settled = FreezeStarFrame(
        opacity: 0, scale: 0.35, rotationDegrees: 0, offsetTowardIcon: 40, girihOpacity: 0
    )

    private static let movingPlan = FreezeStarPlan(
        phases: [
            FreezeStarPhase(step: .unfold, duration: StreakMotion.freezeStar, starts: folded, ends: rest),
            FreezeStarPhase(step: .hold, duration: StreakMotion.freezeHold, starts: rest, ends: rest),
            FreezeStarPhase(step: .settle, duration: StreakMotion.freezeDismiss, starts: rest, ends: settled),
        ],
        removesOverlay: true
    )

    private static let calmPlan = FreezeStarPlan(
        phases: [
            FreezeStarPhase(step: .fadeIn, duration: StreakMotion.freezeReduceFade, starts: stillHidden, ends: rest),
            FreezeStarPhase(step: .hold, duration: StreakMotion.freezeReduceHold, starts: rest, ends: rest),
            FreezeStarPhase(step: .fadeOut, duration: StreakMotion.freezeReduceFade, starts: rest, ends: stillHidden),
        ],
        removesOverlay: true
    )

    /// Unfold and hold, still showing. No settle, and the timeline does not remove the card.
    private static let movingHeldPlan = FreezeStarPlan(
        phases: [
            FreezeStarPhase(step: .unfold, duration: StreakMotion.freezeStar, starts: folded, ends: rest),
            FreezeStarPhase(step: .hold, duration: StreakMotion.freezeHold, starts: rest, ends: rest),
        ],
        removesOverlay: false
    )

    /// Fade in and hold, still showing. No fade out, and the timeline does not remove the card.
    private static let calmHeldPlan = FreezeStarPlan(
        phases: [
            FreezeStarPhase(step: .fadeIn, duration: StreakMotion.freezeReduceFade, starts: stillHidden, ends: rest),
            FreezeStarPhase(step: .hold, duration: StreakMotion.freezeReduceHold, starts: rest, ends: rest),
        ],
        removesOverlay: false
    )

    private static let skippedPlan = FreezeStarPlan(
        phases: [
            FreezeStarPhase(step: .gone, duration: 0, starts: stillHidden, ends: stillHidden),
        ],
        removesOverlay: true
    )
}

/// Whether the freeze card is on screen.
///
/// `begin` shows it. Without VoiceOver, `finish` clears it when the timeline ends.
/// With VoiceOver, `finish` leaves it up: speech ending is not a dismissal, and
/// there is no timeout. `skip` is the tap. `leave` is navigating onward. A new
/// playback, such as coming back to the home, starts hidden.
public struct FreezeCelebrationPlayback: Equatable, Sendable {
    public private(set) var visible = false
    public private(set) var plan: FreezeStarPlan?
    /// The entrance has finished and VoiceOver is keeping the card for a tap or leaving.
    public private(set) var holdingForDismissal = false

    public init() {}

    public mutating func begin(reduceMotion: Bool, voiceOver: Bool = false) {
        plan = FreezeStarPlan.make(reduceMotion: reduceMotion, voiceOver: voiceOver, skipped: false)
        visible = true
        holdingForDismissal = false
    }

    /// The entrance timeline ended. VoiceOver keeps the card. Otherwise it leaves.
    public mutating func finish() {
        guard visible else { return }
        if plan?.removesOverlay == false {
            holdingForDismissal = true
            return
        }
        visible = false
        holdingForDismissal = false
    }

    /// The spoken sentence ending. This never removes the card.
    public mutating func noteSpeechFinished() {}

    public mutating func skip() {
        plan = FreezeStarPlan.make(reduceMotion: false, voiceOver: false, skipped: true)
        visible = false
        holdingForDismissal = false
    }

    /// The home went away. The card does not come back with it.
    public mutating func leave() {
        visible = false
        plan = nil
        holdingForDismissal = false
    }
}

/// What VoiceOver is given for the freeze star.
///
/// The label is the final streak count and `streak freeze earned`. The count
/// is the one passed in for that event, so a later earn does not keep saying 7.
/// `postsAnnouncement` stays false: the label is the one sentence, and nothing
/// posts a second announcement or speaks a phase. The sentence ending does not
/// remove the card, and the card does not block the rest of the home.
public enum FreezeStarSpeech {
    public static let postsAnnouncement = false
    public static let speaksPhases = false
    public static let dismissesOnSpeechCompletion = false
    public static let blocksInput = false
    /// The clause after the count. It is the visible line, lowercased, so the sentence reads as one.
    public static let earnedClause = "streak freeze earned"

    public static func label(count: Int, dayStreak: String = CelebrationCopy.dayStreak) -> String {
        "\(CelebrationCopy.streakSpoken(count, label: dayStreak)), \(earnedClause)"
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
