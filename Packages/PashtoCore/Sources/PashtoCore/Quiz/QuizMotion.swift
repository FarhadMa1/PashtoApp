import Foundation

/// Approved quiz motion, without a UI framework.
///
/// Durations are the ones Jessica timed in the animation demo. Reduce Motion
/// swaps movement for a short fade, or for a jump when the bar only changes width.
/// The same result stays on screen: a check, a cross, the full bar, or the word.
public enum QuizMotion {
    /// Option pop, scale 1 → 1.04 → 1.
    public static let answerPop: TimeInterval = 0.25
    public static let answerPopPeakScale: Double = 1.04
    /// Green check fading in.
    public static let checkFade: TimeInterval = 0.2
    /// Horizontal shake.
    public static let answerShake: TimeInterval = 0.35
    public static let shakeAmplitude: Double = 6
    public static let shakeOscillations = 3
    /// Lesson bar sliding forward.
    public static let progressSpring: TimeInterval = 0.4
    public static let progressSpringDamping: Double = 0.86
    /// Short saffron glow when the bar is full. Not played for Reduce Motion.
    public static let progressGlow: TimeInterval = 0.4
    /// Big Pashto glyph. Scale starts here and ends at 1, so it never grows past the line.
    public static let glyphReveal: TimeInterval = 0.35
    public static let glyphStartScale: Double = 0.92
    /// Card flip.
    public static let cardFlip: TimeInterval = 0.4
    public static let cardFlipDamping: Double = 0.92
    /// Correct pair tiles moving toward each other.
    public static let pairGlide: TimeInterval = 0.2
    /// Spring that settles them into one green tile.
    public static let pairMerge: TimeInterval = 0.4
    public static let pairMergeDamping: Double = 0.78
    /// The green tile shrinking away.
    public static let pairFadeOut: TimeInterval = 0.25
    /// Pop spring. The two halves add up to `answerPop`.
    public static let popSpringDamping: Double = 0.72
    /// Fade used wherever Reduce Motion removes a move.
    public static let reduceMotionFade: TimeInterval = 0.2
    /// Next question entering from the right. The card that leaves fades.
    public static let questionSpring: TimeInterval = 0.28
    public static let questionSpringDamping: Double = 0.86

    public static let pairGoneScale: Double = 0.6

    /// True only for the moving glow. Reduce Motion keeps the full bar and skips the glow.
    public static func playsGlow(barIsFull: Bool, reduceMotion: Bool) -> Bool {
        barIsFull && !reduceMotion
    }
}

/// Which transform a graded choice plays.
public enum QuizMotionKind: Equatable, Sendable {
    /// Scale 1 → peak → 1.
    case pop
    /// Horizontal shake. Offsets are `AnswerShake.samples`.
    case shake
    /// Opacity only.
    case fade
    /// Rest. Nothing moves.
    case none
}

public enum AnswerMotion {
    /// The picked option. An unpicked correct option stays still and shows its check.
    public static func choice(_ mark: QuizResultMark?, reduceMotion: Bool) -> QuizMotionKind {
        switch mark {
        case .correct:
            return reduceMotion ? .fade : .pop
        case .incorrect:
            return reduceMotion ? .fade : .shake
        case nil:
            return .none
        }
    }

    /// Scales for a pop. Anything else stays at 1.
    public static func scales(for kind: QuizMotionKind) -> [Double] {
        switch kind {
        case .pop:
            return [1, QuizMotion.answerPopPeakScale, 1]
        case .shake, .fade, .none:
            return [1]
        }
    }
}

/// One point on the shake, as a fraction of `QuizMotion.answerShake`.
public struct ShakeSample: Equatable, Sendable {
    public var fraction: Double
    public var offset: Double

    public init(fraction: Double, offset: Double) {
        self.fraction = fraction
        self.offset = offset
    }
}

/// Three oscillations of ±6 points, then rest.
///
/// An oscillation is one trip to the left and one to the right. The track starts
/// and ends at 0. `segments` are the keyframe targets after that rest.
public enum AnswerShake {
    public static let samples: [ShakeSample] = [
        ShakeSample(fraction: 0, offset: 0),
        ShakeSample(fraction: 0.5 / 6, offset: -QuizMotion.shakeAmplitude),
        ShakeSample(fraction: 1.5 / 6, offset: QuizMotion.shakeAmplitude),
        ShakeSample(fraction: 2.5 / 6, offset: -QuizMotion.shakeAmplitude),
        ShakeSample(fraction: 3.5 / 6, offset: QuizMotion.shakeAmplitude),
        ShakeSample(fraction: 4.5 / 6, offset: -QuizMotion.shakeAmplitude),
        ShakeSample(fraction: 5.5 / 6, offset: QuizMotion.shakeAmplitude),
        ShakeSample(fraction: 1, offset: 0),
    ]

    public struct Segment: Equatable, Sendable {
        public var offset: Double
        public var duration: TimeInterval

        public init(offset: Double, duration: TimeInterval) {
            self.offset = offset
            self.duration = duration
        }
    }

    /// Seven keyframe targets. Their durations add up to the shake.
    public static var segments: [Segment] {
        var result: [Segment] = []
        for index in samples.indices.dropFirst() {
            let previous = samples[index - 1]
            let sample = samples[index]
            let duration = (sample.fraction - previous.fraction) * QuizMotion.answerShake
            result.append(Segment(offset: sample.offset, duration: duration))
        }
        return result
    }

    public static var positivePeaks: Int {
        samples.filter { $0.offset == QuizMotion.shakeAmplitude }.count
    }

    public static var negativePeaks: Int {
        samples.filter { $0.offset == -QuizMotion.shakeAmplitude }.count
    }
}

/// How the lesson bar moves.
public enum ProgressAdvance: Equatable, Sendable {
    case spring
    case jump

    public static func style(reduceMotion: Bool) -> ProgressAdvance {
        reduceMotion ? .jump : .spring
    }
}

/// Filled length of the lesson bar.
///
/// A revealed answer counts before Continue. A wrong answer that will be asked
/// again lengthens the bar, so a miss on the last card does not flash 100%.
public struct LessonBar: Equatable, Sendable {
    public var answered: Int
    public var total: Int

    public init(answered: Int, total: Int) {
        self.answered = answered
        self.total = total
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(answered) / Double(total)
    }

    public var showsGlow: Bool {
        total > 0 && answered >= total
    }

    public static func measure(
        submitted: Int,
        remaining: Int,
        revealed: GradeResult?,
        currentIsRepeat: Bool
    ) -> LessonBar {
        let submitted = max(0, submitted)
        let remaining = max(0, remaining)
        let countsCurrent = revealed != nil && remaining > 0
        let queuesRepeat = revealed == .incorrect && !currentIsRepeat && remaining > 0
        let total = submitted + remaining + (queuesRepeat ? 1 : 0)
        let answered = min(submitted + (countsCurrent ? 1 : 0), total)
        return LessonBar(answered: answered, total: total)
    }
}

/// How the big Pashto glyph comes in.
public enum GlyphReveal: Equatable, Sendable {
    /// Opacity and scale, from `QuizMotion.glyphStartScale` to 1.
    case fadeAndScale
    /// Opacity only.
    case fade

    public static func style(reduceMotion: Bool) -> GlyphReveal {
        reduceMotion ? .fade : .fadeAndScale
    }

    public var startScale: Double {
        switch self {
        case .fadeAndScale: QuizMotion.glyphStartScale
        case .fade: 1
        }
    }
}

/// How the glyph card turns over.
public enum CardFlip: Equatable, Sendable {
    case rotation
    case fade

    public static func style(reduceMotion: Bool) -> CardFlip {
        reduceMotion ? .fade : .rotation
    }
}

/// Identity of the question on screen.
///
/// It changes only when the session moves to another question. Revealing an
/// answer is not part of it, so the card does not slide when the learner
/// answers. A repeat is a new identity because `answerCount` has grown.
public struct QuestionIdentity: Hashable, Sendable {
    public var answerCount: Int
    public var isRepeat: Bool

    public init(answerCount: Int, isRepeat: Bool) {
        self.answerCount = answerCount
        self.isRepeat = isRepeat
    }
}

/// How the next question replaces the one on screen.
///
/// The new card slides in from the right. The card leaving fades. Reduce
/// Motion crossfades both. The transition does not disable Continue or the
/// next answer.
public enum QuestionChange: Equatable, Sendable {
    case slideFromRight
    case crossfade

    /// Continue and the next answer stay available while the cards move.
    public static let blocksInput = false

    public static func style(reduceMotion: Bool) -> QuestionChange {
        reduceMotion ? .crossfade : .slideFromRight
    }

    /// Spring response for the slide, or the short fade for Reduce Motion.
    public static func duration(reduceMotion: Bool) -> TimeInterval {
        switch style(reduceMotion: reduceMotion) {
        case .slideFromRight:
            QuizMotion.questionSpring
        case .crossfade:
            QuizMotion.reduceMotionFade
        }
    }
}

/// One side of the new-word card.
///
/// `pronunciation` is the spoken field already chosen for this prompt.
/// This value never carries scholarly transliteration.
public struct GlyphCardSide: Equatable, Sendable {
    public var glyph: String
    public var pronunciation: String?
    public var meaning: String?

    public init(glyph: String, pronunciation: String?, meaning: String?) {
        self.glyph = glyph
        self.pronunciation = pronunciation
        self.meaning = meaning
    }
}

/// How large a Pashto prompt is drawn.
public enum GlyphPromptScale: Equatable, Sendable {
    /// One letter or one word.
    case prominent
    /// A phrase or a sentence. Any prompt that contains a space.
    case title
}

public enum GlyphPromptScaleChoice {
    /// A single letter or a single word is prominent. A space keeps the title size.
    public static func scale(for text: String) -> GlyphPromptScale {
        text.contains(" ") ? .title : .prominent
    }
}

/// Front and back of a new letter or word.
///
/// The front is the prompt as the quiz already shows it. The back adds the
/// English gloss only after the question has been answered, for every task kind.
public struct GlyphCardModel: Equatable, Sendable {
    public var front: GlyphCardSide
    public var back: GlyphCardSide

    public init(front: GlyphCardSide, back: GlyphCardSide) {
        self.front = front
        self.back = back
    }

    public var canFlip: Bool { front != back }

    public static func make(
        glyph: String,
        pronunciation: String?,
        meaning: String?,
        kind: TaskKind,
        answered: Bool
    ) -> GlyphCardModel {
        let spoken = blankToNil(pronunciation)
        let gloss = meaningOnBack(meaning, kind: kind, answered: answered)
        return GlyphCardModel(
            front: GlyphCardSide(glyph: glyph, pronunciation: spoken, meaning: nil),
            back: GlyphCardSide(glyph: glyph, pronunciation: spoken, meaning: gloss)
        )
    }

    /// The gloss, or nil until the question has been answered.
    static func meaningOnBack(_ meaning: String?, kind: TaskKind, answered: Bool) -> String? {
        guard answered else { return nil }
        switch kind {
        case .meaningPashtoToEnglish, .meaningEnglishToPashto, .transliterationChoice,
             .findLetter, .letterContrast, .firstLetter, .matchPairs, .orderWords, .dialogResponse:
            return blankToNil(meaning)
        }
    }
}

/// One beat of a pair after the answer is shown.
public enum PairMergeStep: Equatable, Sendable {
    /// Tiles move toward each other. Skipped for Reduce Motion.
    case glide
    /// One green tile with a check.
    case merged
    /// That tile has shrunk and faded.
    case gone
    /// Wrong tiles shake.
    case shake
    /// Reduce Motion fade, with no glide and no shake.
    case fade
    /// Wrong tiles stay red, with the cross, after the shake or the fade.
    case hold
}

public struct PairMergeFrame: Equatable, Sendable {
    public var time: TimeInterval
    public var step: PairMergeStep

    public init(time: TimeInterval, step: PairMergeStep) {
        self.time = time
        self.step = step
    }
}

public enum PairMergePlan {
    /// Frames from the moment the answer is shown. Time 0 is the first frame.
    public static func frames(mark: QuizResultMark, reduceMotion: Bool) -> [PairMergeFrame] {
        switch (mark, reduceMotion) {
        case (.correct, false):
            return [
                PairMergeFrame(time: 0, step: .glide),
                PairMergeFrame(time: QuizMotion.pairGlide, step: .merged),
                PairMergeFrame(time: QuizMotion.pairGlide + QuizMotion.pairMerge, step: .gone),
            ]
        case (.correct, true):
            return [
                PairMergeFrame(time: 0, step: .fade),
                PairMergeFrame(time: QuizMotion.reduceMotionFade, step: .gone),
            ]
        case (.incorrect, false):
            return [
                PairMergeFrame(time: 0, step: .shake),
                PairMergeFrame(time: QuizMotion.answerShake, step: .hold),
            ]
        case (.incorrect, true):
            return [
                PairMergeFrame(time: 0, step: .fade),
                PairMergeFrame(time: QuizMotion.reduceMotionFade, step: .hold),
            ]
        }
    }
}

/// The haptic for a graded answer, for every task kind.
///
/// A choice plays it when the option is tapped. Match and word order play it
/// when Continue grades the answer. Both call this so the two paths stay one.
public enum AnswerHaptic: Equatable, Sendable {
    case success
    case error

    public static func kind(for result: GradeResult) -> AnswerHaptic {
        switch result {
        case .correct:
            .success
        case .incorrect:
            .error
        }
    }
}
