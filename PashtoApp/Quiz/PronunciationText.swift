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
        _ = dynamicTypeSize
        let pointSize = resolvedPointSize
        let space = spaceWidth(pointSize)
        PronunciationFlow(alignment: alignment, spacing: space) {
            ForEach(Array(PronunciationDisplay.tokens(in: stored).enumerated()), id: \.offset) { _, token in
                tokenView(token, pointSize: pointSize)
            }
        }
        .environment(\.legibilityWeight, .regular)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: PronunciationDisplay.spoken(stored)))
    }

    private var resolvedPointSize: CGFloat {
        switch sizing {
        case .points(let size):
            return size
        case .textStyle(let style):
            let font = UIFont.preferredFont(forTextStyle: Self.uiTextStyle(style))
            return font.pointSize
        }
    }

    private func spaceWidth(_ pointSize: CGFloat) -> CGFloat {
        let weight = uiWeight(PronunciationDisplay.unstressedWeight, boldText: boldText)
        let font = UIFont.systemFont(ofSize: pointSize, weight: weight)
        return (" " as NSString).size(withAttributes: [.font: font]).width
    }

    private func tokenView(_ token: PronunciationToken, pointSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(token.runs.enumerated()), id: \.offset) { _, run in
                syllable(run, pointSize: pointSize)
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityHidden(true)
    }

    private func syllable(_ run: PronunciationRun, pointSize: CGFloat) -> some View {
        let weight = run.weight(boldText: boldText)
        let fontWeight = Self.fontWeight(weight)
        return Text(verbatim: run.text)
            .font(font(pointSize: pointSize, weight: fontWeight))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .overlay(alignment: .bottom) {
                if run.underlined(boldText: boldText) {
                    underline(pointSize: pointSize, weight: weight)
                }
            }
            .accessibilityHidden(true)
    }

    private func font(pointSize: CGFloat, weight: Font.Weight) -> Font {
        switch sizing {
        case .points:
            return .system(size: pointSize, weight: weight)
        case .textStyle(let style):
            return .system(style, weight: weight)
        }
    }

    private func underline(pointSize: CGFloat, weight: Int) -> some View {
        let font = UIFont.systemFont(ofSize: pointSize, weight: uiWeight(weight, boldText: true))
        let descent = abs(font.descender)
        let thickness = CGFloat(PronunciationDisplay.boldTextUnderlineThickness)
        let offset = CGFloat(PronunciationDisplay.boldTextUnderlineOffset)
        return Rectangle()
            .fill(color)
            .frame(height: thickness)
            .offset(y: offset + thickness - descent)
            .accessibilityHidden(true)
    }

    private func uiWeight(_ weight: Int, boldText: Bool) -> UIFont.Weight {
        switch weight {
        case PronunciationDisplay.boldTextStressedWeight: .heavy
        case PronunciationDisplay.stressedWeight: .bold
        case PronunciationDisplay.boldTextUnstressedWeight: .semibold
        default: boldText ? .semibold : .regular
        }
    }

    private static func fontWeight(_ weight: Int) -> Font.Weight {
        switch weight {
        case PronunciationDisplay.boldTextStressedWeight: .heavy
        case PronunciationDisplay.stressedWeight: .bold
        case PronunciationDisplay.boldTextUnstressedWeight: .semibold
        default: .regular
        }
    }

    private static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
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

    private enum Sizing {
        case points(CGFloat)
        case textStyle(Font.TextStyle)
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
