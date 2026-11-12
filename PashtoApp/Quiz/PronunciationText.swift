import PashtoCore
import SwiftUI
import UIKit

/// Shared pronunciation line for variant B.
///
/// Callers pass the stored field and the size and colour they already use.
/// Stressed syllables are heavier. Bold Text also underlines them. VoiceOver
/// reads the stored pronunciation, not the weight and not a broken spelling.
struct PronunciationText: View {
    var stored: String
    private var sizing: Sizing
    var color: Color
    var alignment: TextAlignment

    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(stored: String, points: CGFloat, color: Color, alignment: TextAlignment = .leading) {
        self.stored = stored
        self.sizing = .points(points)
        self.color = color
        self.alignment = alignment
    }

    init(stored: String, textStyle: Font.TextStyle, color: Color, alignment: TextAlignment = .leading) {
        self.stored = stored
        self.sizing = .textStyle(textStyle)
        self.color = color
        self.alignment = alignment
    }

    private var boldText: Bool { legibilityWeight == .bold }

    var body: some View {
        pronunciationLine(typeSize: dynamicTypeSize)
    }

    @State private var availableWidth: CGFloat = 0
    @State private var measuredWidest: CGFloat = 0

    /// Dynamic Type is an argument, not a discarded value in `body`.
    /// `body` is a ViewBuilder, and a discarded assignment there is not a view.
    private func pronunciationLine(typeSize: DynamicTypeSize) -> some View {
        let pointSize = resolvedPointSize(typeSize)
        let space = spaceWidth(pointSize)
        let tokens = PronunciationDisplay.tokens(in: stored)
        var widths = tokens.map {
            Double(PronunciationMeasure.size(token: $0, pointSize: pointSize, boldText: boldText).width)
        }
        if measuredWidest > 0 {
            widths.append(Double(measuredWidest))
        }
        let scale = CGFloat(
            PronunciationFit.lineScale(tokenWidths: widths, availableWidth: Double(availableWidth))
        )
        return PronunciationFlow(alignment: alignment, spacing: space * scale) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                PronunciationTokenView(
                    token: token,
                    pointSize: pointSize,
                    scale: scale,
                    color: color,
                    boldText: boldText,
                    sizing: sizing
                )
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: PronunciationWidthKey.self, value: geo.size.width)
            }
        }
        .onPreferenceChange(PronunciationWidthKey.self) { width in
            if abs(width - availableWidth) > 0.5 {
                availableWidth = width
            }
        }
        .onPreferenceChange(TokenWidthKey.self) { width in
            if width > measuredWidest + 0.5 {
                measuredWidest = width
            }
        }
        .environment(\.legibilityWeight, .regular)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: PronunciationDisplay.spoken(stored)))
    }

    private func resolvedPointSize(_: DynamicTypeSize) -> CGFloat {
        switch sizing {
        case .points(let size):
            return size
        case .textStyle(let style):
            let font = UIFont.preferredFont(forTextStyle: PronunciationText.uiTextStyle(style))
            return font.pointSize
        }
    }

    private func spaceWidth(_ pointSize: CGFloat) -> CGFloat {
        let weight = PronunciationFonts.uiWeight(PronunciationDisplay.unstressedWeight, boldText: boldText)
        let font = UIFont.systemFont(ofSize: pointSize, weight: weight)
        return (" " as NSString).size(withAttributes: [.font: font]).width
    }

    fileprivate static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        if style == .largeTitle { return .largeTitle }
        if style == .title { return .title1 }
        if style == .title2 { return .title2 }
        if style == .title3 { return .title3 }
        if style == .headline { return .headline }
        if style == .subheadline { return .subheadline }
        if style == .body { return .body }
        if style == .callout { return .callout }
        if style == .footnote { return .footnote }
        if style == .caption { return .caption1 }
        if style == .caption2 { return .caption2 }
        return .body
    }

    fileprivate enum Sizing {
        case points(CGFloat)
        case textStyle(Font.TextStyle)
    }
}

/// One whitespace-separated pronunciation word.
///
/// `scale` is the pronunciation's shared scale, so every word shrinks
/// together. Syllables stay in one stack: a hyphen cannot wrap, and the
/// flow may break only before this word.
private struct PronunciationTokenView: View {
    var token: PronunciationToken
    var pointSize: CGFloat
    var scale: CGFloat
    var color: Color
    var boldText: Bool
    var sizing: PronunciationText.Sizing

    @State private var measured: CGSize = .zero

    /// The unscaled word. A later measurement can only grow this, so a scaled
    /// frame cannot feed back in and shrink the word again.
    private var ideal: CGSize {
        let estimate = PronunciationMeasure.size(token: token, pointSize: pointSize, boldText: boldText)
        return CGSize(
            width: max(estimate.width, measured.width),
            height: max(estimate.height, measured.height)
        )
    }

    var body: some View {
        syllables
            .fixedSize()
            .background {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: TokenSizeKey.self, value: geo.size)
                        .preference(key: TokenWidthKey.self, value: geo.size.width)
                }
            }
            .onPreferenceChange(TokenSizeKey.self) { size in
                guard size.width > measured.width + 0.5 else { return }
                measured = size
            }
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: ideal.width * scale, height: ideal.height * scale, alignment: .topLeading)
            .accessibilityHidden(true)
    }

    private var syllables: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(token.runs.enumerated()), id: \.offset) { _, run in
                syllable(run)
            }
        }
    }

    private func syllable(_ run: PronunciationRun) -> some View {
        let weight = run.weight(boldText: boldText)
        return Text(verbatim: run.text)
            .font(font(weight: PronunciationFonts.fontWeight(weight)))
            .foregroundStyle(color)
            .lineLimit(1)
            .overlay(alignment: .bottom) {
                if run.underlined(boldText: boldText) {
                    underline(weight: weight)
                }
            }
            .accessibilityHidden(true)
    }

    private func font(weight: Font.Weight) -> Font {
        switch sizing {
        case .points:
            return .system(size: pointSize, weight: weight)
        case .textStyle(let style):
            return .system(style, weight: weight)
        }
    }

    private func underline(weight: Int) -> some View {
        let font = UIFont.systemFont(ofSize: pointSize, weight: PronunciationFonts.uiWeight(weight, boldText: true))
        let descent = abs(font.descender)
        let thickness = CGFloat(PronunciationDisplay.boldTextUnderlineThickness)
        let offset = CGFloat(PronunciationDisplay.boldTextUnderlineOffset)
        return Rectangle()
            .fill(color)
            .frame(height: thickness)
            .offset(y: offset + thickness - descent)
            .accessibilityHidden(true)
    }
}

private enum PronunciationMeasure {
    static func size(token: PronunciationToken, pointSize: CGFloat, boldText: Bool) -> CGSize {
        var width: CGFloat = 0
        var height: CGFloat = 1
        for run in token.runs {
            let font = UIFont.systemFont(
                ofSize: pointSize,
                weight: PronunciationFonts.uiWeight(run.weight(boldText: boldText), boldText: boldText)
            )
            width += (run.text as NSString).size(withAttributes: [.font: font]).width
            height = max(height, font.lineHeight)
        }
        return CGSize(width: max(ceil(width), 1), height: ceil(height))
    }
}

private enum PronunciationFonts {
    static func uiWeight(_ weight: Int, boldText: Bool) -> UIFont.Weight {
        switch weight {
        case PronunciationDisplay.boldTextStressedWeight: .heavy
        case PronunciationDisplay.stressedWeight: .bold
        case PronunciationDisplay.boldTextUnstressedWeight: .semibold
        default: boldText ? .semibold : .regular
        }
    }

    static func fontWeight(_ weight: Int) -> Font.Weight {
        switch weight {
        case PronunciationDisplay.boldTextStressedWeight: .heavy
        case PronunciationDisplay.stressedWeight: .bold
        case PronunciationDisplay.boldTextUnstressedWeight: .semibold
        default: .regular
        }
    }
}

private struct PronunciationWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TokenWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TokenSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Wraps pronunciation tokens at spaces. A token keeps its hyphens on one line.
private struct PronunciationFlow: Layout {
    var alignment: TextAlignment
    var spacing: CGFloat

    private struct Line {
        var indexes: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    nonisolated func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let lines = wrap(proposal: proposal, subviews: subviews)
        let height = lines.reduce(CGFloat(0)) { $0 + $1.height }
        if let width = proposal.width, width.isFinite {
            return CGSize(width: width, height: height)
        }
        let width = lines.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    nonisolated func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let lines = wrap(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        var y = bounds.minY
        for line in lines {
            let extra = bounds.width - line.width
            let originX: CGFloat
            switch alignment {
            case .center:
                originX = bounds.minX + max(0, extra) / 2
            case .trailing:
                originX = bounds.minX + max(0, extra)
            default:
                originX = bounds.minX
            }
            var x = originX
            for (offset, index) in line.indexes.enumerated() {
                if offset > 0 { x += spacing }
                let size = line.sizes[offset]
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                x += size.width
            }
            y += line.height
        }
    }

    private nonisolated func wrap(proposal: ProposedViewSize, subviews: Subviews) -> [Line] {
        let limit = proposal.width ?? .infinity
        var lines: [Line] = []
        var current = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let gap: CGFloat = current.indexes.isEmpty ? 0 : spacing
            let next = current.width + gap + size.width
            if !current.indexes.isEmpty, next > limit {
                lines.append(current)
                current = Line(indexes: [index], sizes: [size], width: size.width, height: size.height)
            } else {
                current.indexes.append(index)
                current.sizes.append(size)
                current.width = current.indexes.count == 1 ? size.width : next
                current.height = max(current.height, size.height)
            }
        }
        if !current.indexes.isEmpty || lines.isEmpty {
            lines.append(current)
        }
        return lines
    }
}
