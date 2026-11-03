import PashtoCore
import SwiftUI

/// SwiftUI timings for the approved quiz motions.
///
/// Numbers live in `QuizMotion`. This type only turns them into animations
/// and reads Reduce Motion.
enum Motion {
    static var progress: Animation {
        .spring(response: QuizMotion.progressSpring, dampingFraction: QuizMotion.progressSpringDamping)
    }

    static var pairMerge: Animation {
        .spring(response: QuizMotion.pairMerge, dampingFraction: QuizMotion.pairMergeDamping)
    }

    static var cardFlip: Animation {
        .spring(response: QuizMotion.cardFlip, dampingFraction: QuizMotion.cardFlipDamping)
    }

    static var fade: Animation {
        .easeOut(duration: QuizMotion.reduceMotionFade)
    }

    static var checkFade: Animation {
        .easeOut(duration: QuizMotion.checkFade)
    }

    static var glyphReveal: Animation {
        .easeOut(duration: QuizMotion.glyphReveal)
    }

    static var pairGlide: Animation {
        .easeInOut(duration: QuizMotion.pairGlide)
    }

    static var pairFadeOut: Animation {
        .easeIn(duration: QuizMotion.pairFadeOut)
    }

    static func progressAdvance(reduceMotion: Bool) -> Animation? {
        switch ProgressAdvance.style(reduceMotion: reduceMotion) {
        case .spring:
            progress
        case .jump:
            nil
        }
    }

    static func reveal(reduceMotion: Bool) -> Animation {
        switch GlyphReveal.style(reduceMotion: reduceMotion) {
        case .fadeAndScale:
            glyphReveal
        case .fade:
            fade
        }
    }

    static func flip(reduceMotion: Bool) -> Animation {
        switch CardFlip.style(reduceMotion: reduceMotion) {
        case .rotation:
            cardFlip
        case .fade:
            fade
        }
    }

    static func pairStep(_ step: PairMergeStep?, reduceMotion: Bool) -> Animation? {
        switch step {
        case .glide:
            pairGlide
        case .merged:
            reduceMotion ? fade : pairMerge
        case .gone:
            reduceMotion ? fade : pairFadeOut
        case .fade:
            fade
        case .shake, .hold, nil:
            nil
        }
    }
}

/// Pop or shake on the option the learner picked. Reduce Motion does neither.
struct ChoiceMotion: ViewModifier {
    var mark: QuizResultMark?
    /// False for the correct option the learner did not pick. That one still shows its check.
    var moves: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popToken = 0
    @State private var shakeToken = 0

    private var kind: QuizMotionKind {
        guard moves else { return .none }
        return AnswerMotion.choice(mark, reduceMotion: reduceMotion)
    }

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 1.0, trigger: popToken) { view, scale in
                view.scaleEffect(CGFloat(scale))
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(
                        QuizMotion.answerPopPeakScale,
                        duration: QuizMotion.answerPop / 2,
                        spring: Spring(
                            response: QuizMotion.answerPop / 2,
                            dampingRatio: QuizMotion.popSpringDamping
                        )
                    )
                    SpringKeyframe(
                        1.0,
                        duration: QuizMotion.answerPop / 2,
                        spring: Spring(
                            response: QuizMotion.answerPop / 2,
                            dampingRatio: QuizMotion.popSpringDamping
                        )
                    )
                }
            }
            .modifier(ShakeMotion(token: kind == .shake ? shakeToken : 0))
            .onChange(of: kind) { _, newKind in
                if newKind == .pop { popToken += 1 }
                if newKind == .shake { shakeToken += 1 }
            }
    }
}

/// Horizontal shake driven by `AnswerShake.segments`.
struct ShakeMotion: ViewModifier {
    var token: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 0.0, trigger: token) { view, offset in
                view.offset(x: reduceMotion ? 0 : CGFloat(offset))
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(ShakeKeys.offset(0), duration: ShakeKeys.duration(0))
                    LinearKeyframe(ShakeKeys.offset(1), duration: ShakeKeys.duration(1))
                    LinearKeyframe(ShakeKeys.offset(2), duration: ShakeKeys.duration(2))
                    LinearKeyframe(ShakeKeys.offset(3), duration: ShakeKeys.duration(3))
                    LinearKeyframe(ShakeKeys.offset(4), duration: ShakeKeys.duration(4))
                    LinearKeyframe(ShakeKeys.offset(5), duration: ShakeKeys.duration(5))
                    LinearKeyframe(ShakeKeys.offset(6), duration: ShakeKeys.duration(6))
                }
            }
    }
}

/// Keeps the shake keyframes on the shared samples. A missing sample rests at 0.
private enum ShakeKeys {
    static func offset(_ index: Int) -> Double {
        let segments = AnswerShake.segments
        guard segments.indices.contains(index) else { return 0 }
        return segments[index].offset
    }

    static func duration(_ index: Int) -> Double {
        let segments = AnswerShake.segments
        guard segments.indices.contains(index) else { return 0.05 }
        return max(segments[index].duration, 0.01)
    }
}
