import PashtoCore
import SwiftUI

/// Lesson bar. It springs forward as a question is answered.
///
/// The fill is the ring gold and the track is the page colour, so the fill clears 3:1.
/// A 1 pt lapis outline sits on the track. Light `#1E3A8A` and dark `#93B4F5` both clear 3:1 on the page.
/// At 100% the glow is saffron, and it is decorative. Reduce Motion jumps to the new width and skips the glow.
/// The system progress view speaks the value, so this adds no catalog string.
struct LessonProgressBar: View {
    var bar: LessonBar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowToken = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Lapis.background)
                Capsule()
                    .fill(Lapis.ring)
                    .frame(width: max(0, geo.size.width * CGFloat(bar.fraction)))
                    .modifier(SaffronGlow(token: glowToken))
            }
        }
        .frame(height: 12)
        .overlay {
            Capsule().strokeBorder(Lapis.primary, lineWidth: 1)
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
