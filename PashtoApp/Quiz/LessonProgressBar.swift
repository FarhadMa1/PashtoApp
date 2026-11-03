import PashtoCore
import SwiftUI

/// Saffron lesson bar. It springs forward as a question is answered.
///
/// At 100% it glows once. Reduce Motion jumps to the new width and skips the glow.
/// The system progress view speaks the value, so this adds no catalog string.
struct LessonProgressBar: View {
    var bar: LessonBar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowToken = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Lapis.secondaryText.opacity(0.25))
                Capsule()
                    .fill(Lapis.saffron)
                    .frame(width: max(0, geo.size.width * CGFloat(bar.fraction)))
                    .modifier(SaffronGlow(token: glowToken))
            }
        }
        .frame(height: 12)
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
