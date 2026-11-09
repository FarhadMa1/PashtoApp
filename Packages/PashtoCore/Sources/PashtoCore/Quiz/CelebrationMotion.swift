import Foundation

/// Timings for the lesson-finished celebration, the streak, the course path,
/// and the daily-goal ring.
///
/// The numbers are Jessica's. The pieces of a finished lesson play together,
/// so the wait is the longest piece and stays within `lessonFinishMaximum`.
/// Reduce Motion uses the short fade from `QuizMotion`, or no movement at all.
/// A counter shows its final value at once for Reduce Motion and for VoiceOver.
/// VoiceOver is given that final value and not the steps along the way.
public enum CelebrationMotion {
    /// Saffron octagram unfolding.
    public static let star: TimeInterval = 0.55
    public static let starDamping: Double = 0.62
    /// Girih fading in behind the star.
    public static let girih: TimeInterval = 0.8
    /// Numbers counting up.
    public static let countUp: TimeInterval = 0.6
    /// The celebration is skipped with one tap and does not run longer than this.
    public static let lessonFinishMaximum: TimeInterval = 1.4
    /// One pulse of the streak star.
    public static let streakPulse: TimeInterval = 0.45
    /// The path filling to the next lesson.
    public static let pathFill: TimeInterval = 0.5
    /// The gentle pulse on the next lesson. It loops.
    public static let pathPulse: TimeInterval = 1.6
    /// Daily-goal ring. `Circle.trim` uses this spring.
    public static let goalSpringResponse: TimeInterval = 0.6
    public static let goalSpringDamping: Double = 0.8
    /// The small check after the ring completes.
    public static let goalCheck: TimeInterval = 0.35

    /// The longest piece. They start together, so this is the whole celebration.
    public static var lessonFinishDuration: TimeInterval {
        max(star, girih, countUp)
    }
}

/// How the finished-lesson star comes in.
public enum LessonStarStyle: Equatable, Sendable {
    case unfold
    case fade

    public static func style(reduceMotion: Bool) -> LessonStarStyle {
        reduceMotion ? .fade : .unfold
    }
}

/// How the girih behind the star comes in.
///
/// Reduce Motion leaves it in place. It does not fade.
public enum GirihEntrance: Equatable, Sendable {
    case fadeIn
    case still

    public static func style(reduceMotion: Bool) -> GirihEntrance {
        reduceMotion ? .still : .fadeIn
    }
}

/// How the streak star marks a day that was kept.
public enum StreakPulseStyle: Equatable, Sendable {
    case pulse
    case fade

    public static func style(reduceMotion: Bool) -> StreakPulseStyle {
        reduceMotion ? .fade : .pulse
    }
}

/// One counting number.
///
/// `spoken` is the final value. Reduce Motion, VoiceOver, and a skip all
/// start there. Nothing else is read out.
public struct CounterPlan: Equatable, Sendable {
    public var start: Int
    public var end: Int
    public var animates: Bool
    public var spoken: Int

    public init(start: Int, end: Int, animates: Bool, spoken: Int) {
        self.start = start
        self.end = end
        self.animates = animates
        self.spoken = spoken
    }

    public static func plan(
        target: Int,
        reduceMotion: Bool,
        voiceOver: Bool,
        skipped: Bool
    ) -> CounterPlan {
        let end = max(0, target)
        let immediate = reduceMotion || voiceOver || skipped
        return CounterPlan(
            start: immediate ? end : 0,
            end: end,
            animates: !immediate && end > 0,
            spoken: end
        )
    }
}

/// Where one tap on the finished lesson leaves the celebration.
///
/// The star is at rest, the girih is visible, and both numbers are the final
/// first-try counts. Nothing keeps counting.
public struct LessonFinishSkip: Equatable, Sendable {
    public var starAtRest: Bool
    public var girihVisible: Bool
    public var correct: Int
    public var answered: Int

    public init(starAtRest: Bool, girihVisible: Bool, correct: Int, answered: Int) {
        self.starAtRest = starAtRest
        self.girihVisible = girihVisible
        self.correct = correct
        self.answered = answered
    }

    public static func afterOneTap(_ stats: LessonFinishStats) -> LessonFinishSkip {
        let correct = CounterPlan.plan(
            target: stats.correct,
            reduceMotion: false,
            voiceOver: false,
            skipped: true
        )
        let answered = CounterPlan.plan(
            target: stats.answered,
            reduceMotion: false,
            voiceOver: false,
            skipped: true
        )
        return LessonFinishSkip(
            starAtRest: true,
            girihVisible: true,
            correct: correct.spoken,
            answered: answered.spoken
        )
    }
}

/// First-try numbers on the finished-lesson celebration.
///
/// A question asked again after a miss is not counted. The same rule is what
/// the stored score uses. These are the numbers already on the session.
public struct LessonFinishStats: Equatable, Sendable {
    public var answered: Int
    public var correct: Int

    public init(answered: Int, correct: Int) {
        self.answered = answered
        self.correct = correct
    }

    public static func measure(_ session: LessonSession) -> LessonFinishStats {
        let first = session.answers.filter { !$0.task.isRepeat }
        let correct = first.filter { $0.result == .correct }.count
        return LessonFinishStats(answered: first.count, correct: correct)
    }
}

/// The streak number rolling from the previous count to the new one.
public struct StreakRoll: Equatable, Sendable {
    public var from: Int
    public var to: Int
    public var animates: Bool
    public var spoken: Int

    public init(from: Int, to: Int, animates: Bool, spoken: Int) {
        self.from = from
        self.to = to
        self.animates = animates
        self.spoken = spoken
    }

    public static func plan(
        from: Int,
        to: Int,
        reduceMotion: Bool,
        voiceOver: Bool
    ) -> StreakRoll {
        let end = max(0, to)
        let start = max(0, from)
        let immediate = reduceMotion || voiceOver
        return StreakRoll(
            from: immediate ? end : start,
            to: end,
            animates: !immediate && start != end,
            spoken: end
        )
    }
}

/// Which lesson on the path is next, and how that node and the fill behave.
public enum CoursePathMotion {
    public enum NodeStyle: Equatable, Sendable {
        /// A 1.6 s pulse.
        case pulse
        /// A still ring. Reduce Motion uses this instead of the pulse.
        case ring

        public static func style(reduceMotion: Bool) -> NodeStyle {
            reduceMotion ? .ring : .pulse
        }
    }

    public enum FillStyle: Equatable, Sendable {
        case ease
        case jump

        public static func style(reduceMotion: Bool) -> FillStyle {
            reduceMotion ? .jump : .ease
        }
    }

    /// The first lesson in `order` that is not finished.
    ///
    /// `skipping` is for lessons that stay open and never count, so the marker
    /// does not sit on a learn or phrases card.
    public static func next(
        in order: [LessonID],
        finished: Set<LessonID>,
        skipping: Set<LessonID> = []
    ) -> LessonID? {
        order.first { !finished.contains($0) && !skipping.contains($0) }
    }
}

/// The daily-goal ring, from the previous count to the new one.
///
/// `goal` is the new-item limit already stored for the learner. The fraction
/// is that count over the limit. The check appears when the count reaches it.
/// Reduce Motion and VoiceOver show the end at once. `spoken` is the final
/// fraction, which is the only value VoiceOver reads.
public struct GoalRingPlan: Equatable, Sendable {
    public var fromFraction: Double
    public var toFraction: Double
    public var fromCount: Int
    public var toCount: Int
    public var animates: Bool
    public var showsCheck: Bool
    public var spoken: String

    public init(
        fromFraction: Double,
        toFraction: Double,
        fromCount: Int,
        toCount: Int,
        animates: Bool,
        showsCheck: Bool,
        spoken: String
    ) {
        self.fromFraction = fromFraction
        self.toFraction = toFraction
        self.fromCount = fromCount
        self.toCount = toCount
        self.animates = animates
        self.showsCheck = showsCheck
        self.spoken = spoken
    }

    public static func plan(
        from doneBefore: Int,
        to done: Int,
        goal: Int,
        reduceMotion: Bool,
        voiceOver: Bool
    ) -> GoalRingPlan {
        let limit = max(goal, 0)
        let start = max(0, doneBefore)
        let end = max(0, done)
        let immediate = reduceMotion || voiceOver
        return GoalRingPlan(
            fromFraction: immediate ? fraction(end, limit: limit) : fraction(start, limit: limit),
            toFraction: fraction(end, limit: limit),
            fromCount: immediate ? end : start,
            toCount: end,
            animates: !immediate && start != end,
            showsCheck: limit > 0 && end >= limit,
            spoken: "\(end)/\(limit)"
        )
    }

    private static func fraction(_ value: Int, limit: Int) -> Double {
        guard limit > 0 else { return 0 }
        return min(1, Double(value) / Double(limit))
    }
}
