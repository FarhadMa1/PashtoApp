import PashtoCore
import SwiftUI

/// Page track for learn cards. The quiz header uses the navy track and saffron fill.
enum LessonBarChrome {
    case page
    case quizHeader
}

/// Lesson bar. It springs forward as a question is answered.
///
/// The page chrome keeps the ring gold on the page colour, with a 1 pt lapis outline.
/// The quiz header uses `#F2B85B` on `#1E3A8A`, with a cream outline. That fill is not text.
/// At 100% the glow is saffron, and it is decorative. Reduce Motion jumps to the new width and skips the glow.
/// The system progress view speaks the value, so this adds no catalog string.

struct LessonProgressBar: View {
    var bar: LessonBar
    var chrome: LessonBarChrome = .page
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowToken = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: max(0, geo.size.width * CGFloat(bar.fraction)))
                    .modifier(SaffronGlow(token: glowToken))
            }
        }
        .frame(height: chrome == .quizHeader ? 10 : 12)
        .overlay {
            Capsule().strokeBorder(outline, lineWidth: 1)
        }
        .animation(Motion.progressAdvance(reduceMotion: reduceMotion), value: bar.fraction)
        .onChange(of: bar.showsGlow) { _, full in
            guard QuizMotion.playsGlow(barIsFull: full, reduceMotion: reduceMotion) else { return }
            glowToken += 1
        }
        .accessibilityRepresentation {
            ProgressView(value: bar.fraction)
        }
    }

    private var track: Color {
        chrome == .quizHeader ? QuizChrome.barTrack : Lapis.background
    }

    private var fill: Color {
        chrome == .quizHeader ? QuizChrome.barFill : Lapis.ring
    }

    private var outline: Color {
        chrome == .quizHeader ? QuizChrome.cream : Lapis.primary
    }
}

/// One saffron pulse, up and back down, over `QuizMotion.progressGlow`.
private struct SaffronGlow: ViewModifier {
    var token: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: token) { view, glow in
            view.shadow(
                color: Lapis.saffron.opacity(0.9 * glow),
                radius: 10 * CGFloat(glow)
            )
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(1.0, duration: QuizMotion.progressGlow / 2)
                LinearKeyframe(0.0, duration: QuizMotion.progressGlow / 2)
            }
        }
    }
}
