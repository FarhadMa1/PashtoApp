import PashtoCore
import SwiftUI

/// Big Pashto letter or word. It fades in, and it can turn over.
///
/// The front is the prompt the quiz already shows, including pronunciation
/// only when that prompt already has it. The back adds the English gloss
/// only after the question has been answered. A phrase stays at the title size.
/// Nothing here posts an accessibility announcement.
struct GlyphCard: View {
    var model: GlyphCardModel
    /// False for a card that is leaving. It is already on screen and only fades.
    var playsReveal: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flipped = false
    @State private var shown: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var pronunciationSize: CGFloat = 38
    @ScaledMetric(relativeTo: .title2) private var pashtoSize: CGFloat = 32

    init(model: GlyphCardModel, playsReveal: Bool = true) {
        self.model = model
        self.playsReveal = playsReveal
        _shown = State(initialValue: !playsReveal)
    }

    var body: some View {
        let flipStyle = CardFlip.style(reduceMotion: reduceMotion)
        Group {
            if model.canFlip {
                Button {
                    withAnimation(Motion.flip(reduceMotion: reduceMotion)) {
                        flipped.toggle()
                    }
                } label: {
                    card(flipStyle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(spoken)
            } else {
                card(flipStyle)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken)
            }
        }
        .onAppear {
            guard playsReveal else { return }
            withAnimation(Motion.reveal(reduceMotion: reduceMotion)) {
                shown = true
            }
        }
    }

    private func card(_ flipStyle: CardFlip) -> some View {
        ZStack(alignment: .top) {
            face(model.front, angle: flipped ? 180 : 0, shown: !flipped, spins: flipStyle == .rotation)
            face(model.back, angle: flipped ? 0 : -180, shown: flipped, spins: flipStyle == .rotation)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : CGFloat(GlyphReveal.style(reduceMotion: reduceMotion).startScale))
    }

    private func face(_ side: GlyphCardSide, angle: Double, shown: Bool, spins: Bool) -> some View {
        VStack(spacing: 9) {
            PashtoLine(
                text: side.glyph,
                pronunciation: side.pronunciation,
                arabic: QuizPresentation.containsArabicScript(side.glyph),
                pronunciationColor: QuizChrome.primary,
                scriptColor: QuizChrome.pashto,
                scriptFont: .system(size: pashtoSize, weight: .regular),
                fitsWidth: prominent,
                centers: true,
                pronunciationSize: side.pronunciation == nil ? nil : pronunciationSize,
                pronunciationLeads: side.pronunciation != nil
            )
            .font(.system(size: pronunciationSize, weight: .bold))
            .foregroundStyle(QuizChrome.primary)
            .frame(maxWidth: .infinity)
            if let meaning = side.meaning {
                Text(meaning)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(QuizChrome.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .modifier(SpinFace(angle: angle, shown: shown, spins: spins))
    }

    private var prominent: Bool {
        GlyphPromptScaleChoice.scale(for: model.front.glyph) == .prominent
    }

    private var spoken: String {
        let side = flipped ? model.back : model.front
        return [side.pronunciation, side.glyph, side.meaning]
            .compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : value
            }
            .joined(separator: ", ")
    }
}

/// Hides a face once it has turned past the edge, so the glyph is not mirrored.
///
/// `animatableData` is a plain nonisolated value. SwiftUI samples it off the main actor.
private struct SpinFace: ViewModifier, Animatable {
    var angle: Double
    var shown: Bool
    var spins: Bool

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(spins ? angle : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.6
            )
            .opacity(visible ? 1 : 0)
            .accessibilityHidden(!visible)
    }

    private var visible: Bool {
        guard spins else { return shown }
        var turns = angle.truncatingRemainder(dividingBy: 360)
        if turns < 0 { turns += 360 }
        return turns < 90 || turns > 270
    }
}
