import PashtoCore
import SwiftUI

/// Match columns, side by side. A correct pair glides together, becomes one green tile, then fades.
///
/// A wrong pair shakes with the red frame and the cross, and that mark stays.
/// Reduce Motion skips the glide and the shake and fades for 0.2 s instead.
/// Continue lives outside this view, so the motion never blocks it.
struct MatchingBoard: View {
    var task: MatchPairsTask
    var links: [ItemID: ItemID]
    var selectedLeft: ItemID?
    var revealed: Bool
    var showsPronunciation: Bool
    var itemsByID: [ItemID: ContentItem]
    var onLeft: (ItemID) -> Void
    var onRight: (ItemID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var pairPronunciationSize: CGFloat = 24
    @ScaledMetric(relativeTo: .title3) private var pairPashtoSize: CGFloat = 29
    @State private var spots: [String: CGRect] = [:]
    @State private var clock = PairMergeClock()

    private let space = "matching-board"

    var body: some View {
        columns
        .coordinateSpace(.named(space))
        .overlay {
            ZStack {
                ForEach(task.pairs, id: \.left.itemID) { pair in
                    mergedTile(pair)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
        .onPreferenceChange(TileSpotKey.self) { found in
            // Keep the resting frames. Offsets during the merge would otherwise
            // feed back into the next frame and the tiles would chase each other.
            guard !revealed else { return }
            var next: [String: CGRect] = [:]
            for place in found {
                next[place.key] = place.rect
            }
            if next != spots { spots = next }
        }
        .onChange(of: revealed) { _, isRevealed in
            if isRevealed {
                clock.play(events: mergeEvents(), reduceMotion: reduceMotion)
            } else {
                clock.stop()
            }
        }
        .onDisappear { clock.stop() }
    }

    @ViewBuilder
    private var columns: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                leftColumn
                rightColumn
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                leftColumn
                    .frame(maxWidth: .infinity, alignment: .top)
                rightColumn
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private var leftColumn: some View {
        VStack(spacing: 12) {
            ForEach(task.pairs, id: \.left.itemID) { pair in
                leftTile(pair)
            }
        }
    }

    private var rightColumn: some View {
        VStack(spacing: 12) {
            ForEach(task.rightColumn, id: \.itemID) { side in
                rightTile(side)
            }
        }
    }

    private func leftTile(_ pair: MatchPair) -> some View {
        let linked = linkedSide(links[pair.left.itemID])
        let spoken = pronunciation(for: pair.left.text, itemID: pair.left.itemID)
        let mark = pairMark(pair)
        let phase = step(for: pair.left.itemID, mark: mark)
        let overlay = hasMeetingPoint(pair)
        let visual = sourceMark(mark, step: phase, hasOverlay: overlay)
        let selected = selectedLeft == pair.left.itemID
        return Button {
            guard !revealed else { return }
            onLeft(pair.left.itemID)
        } label: {
            VStack(spacing: 6) {
                markIcon(visual)
                line(pair.left.text, itemID: pair.left.itemID, mark: visual)
                if let linked {
                    line(linked.text, itemID: linked.itemID, mark: visual)
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(plate(selected: selected, mark: visual))
        .foregroundStyle(Lapis.text)
        .disabled(revealed)
        .opacity(sourceOpacity(mark, step: phase, hasOverlay: overlay))
        .offset(glideOffset(pair, fromLeft: true))
        .modifier(ShakeMotion(token: mark == .incorrect ? clock.shakeToken : 0))
        .animation(Motion.pairStep(phase, reduceMotion: reduceMotion), value: phase)
        .background { spot(leftKey(pair.left.itemID)) }
        .accessibilityLabel(matchLabel(text: pair.left.text, pronunciation: spoken, linkedText: linked?.text, mark: mark))
        .accessibilityAddTraits(selectedLeft == pair.left.itemID ? .isSelected : [])
        .accessibilityHidden(phase == .gone)
        .allowsHitTesting(phase != .gone)
        .zIndex(phase == .glide ? 1 : 0)
    }

    private func rightTile(_ side: MatchSide) -> some View {
        let pair = task.pairs.first { links[$0.left.itemID] == side.itemID }
        let mark = pair.flatMap { pairMark($0) }
        let phase = pair.flatMap { step(for: $0.left.itemID, mark: mark) }
        let overlay = pair.map { hasMeetingPoint($0) } ?? false
        let visual = sourceMark(mark, step: phase, hasOverlay: overlay)
        return Button {
            onRight(side.itemID)
        } label: {
            VStack(spacing: 6) {
                markIcon(visual)
                line(side.text, itemID: side.itemID, mark: visual)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(plate(selected: false, mark: visual))
        .foregroundStyle(Lapis.text)
        .disabled(revealed || selectedLeft == nil)
        .opacity(sourceOpacity(mark, step: phase, hasOverlay: overlay))
        .offset(pair.map { glideOffset($0, fromLeft: false) } ?? .zero)
        .modifier(ShakeMotion(token: mark == .incorrect ? clock.shakeToken : 0))
        .animation(Motion.pairStep(phase, reduceMotion: reduceMotion), value: phase)
        .background { spot(rightKey(side.itemID)) }
        .accessibilityLabel(
            QuizPresentation.matchAccessibilityLabel(
                text: side.text,
                pronunciation: pronunciation(for: side.text, itemID: side.itemID),
                linkedText: nil
            )
        )
        .accessibilityHidden(phase == .gone)
        .allowsHitTesting(phase != .gone)
        .zIndex(phase == .glide ? 1 : 0)
    }

    @ViewBuilder
    private func mergedTile(_ pair: MatchPair) -> some View {
        if let meeting = meetingPoint(pair), pairMark(pair) == .correct {
            let phase = step(for: pair.left.itemID, mark: .correct)
            HStack(spacing: 10) {
                Image(systemName: QuizResultMark.correct.symbolName)
                    .font(.body.weight(.bold))
                    .foregroundStyle(Lapis.correct)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    line(pair.left.text, itemID: pair.left.itemID, mark: .correct)
                    if let linked = linkedSide(links[pair.left.itemID]) {
                        line(linked.text, itemID: linked.itemID, mark: .correct)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(width: meeting.size.width, height: meeting.size.height, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Lapis.correctFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(Lapis.correct, lineWidth: 2)
            }
            .scaleEffect(overlayScale(phase))
            .opacity(overlayOpacity(phase))
            .position(meeting.center)
            .animation(Motion.pairStep(phase, reduceMotion: reduceMotion), value: phase)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func line(_ text: String, itemID: ItemID, mark: QuizResultMark?) -> some View {
        let spoken = pronunciation(for: text, itemID: itemID)
        let arabic = QuizPresentation.containsArabicScript(text)
        return PashtoLine(
            text: text,
            pronunciation: spoken,
            arabic: arabic,
            pronunciationColor: mark == nil ? QuizChrome.primary : Lapis.fillPronunciation,
            scriptColor: mark == nil ? QuizChrome.pashto : Lapis.fillText,
            scriptFont: spoken == nil ? nil : .system(size: pairPashtoSize, weight: .regular),
            centers: true,
            pronunciationSize: spoken == nil ? nil : pairPronunciationSize,
            pronunciationLeads: spoken != nil
        )
        .font(.system(size: spoken == nil ? 17 : pairPronunciationSize, weight: spoken == nil ? .semibold : .bold))
        .foregroundStyle(mark == nil ? QuizChrome.ink : Lapis.fillText)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func plate(selected: Bool, mark: QuizResultMark?) -> QuizTactileButtonStyle {
        let edge = border(selected: selected, mark: mark)
        return QuizTactileButtonStyle(
            fill: fill(mark),
            edge: edge,
            lipColor: edge,
            expands: true,
            alignment: .center,
            lineWidth: selected && mark == nil ? 3 : 2
        )
    }

    @ViewBuilder
    private func markIcon(_ mark: QuizResultMark?) -> some View {
        if let mark {
            Image(systemName: mark.symbolName)
                .font(.body.weight(.bold))
                .foregroundStyle(mark == .correct ? Lapis.correct : Lapis.destructive)
                .accessibilityHidden(true)
        }
    }

    private func mergeEvents() -> [(id: ItemID, mark: QuizResultMark)] {
        task.pairs.compactMap { pair in
            guard let mark = pairMark(pair) else { return nil }
            return (pair.left.itemID, mark)
        }
    }

    private func step(for id: ItemID, mark: QuizResultMark?) -> PairMergeStep? {
        if let stored = clock.steps[id] { return stored }
        guard revealed, let mark else { return nil }
        return PairMergePlan.frames(mark: mark, reduceMotion: reduceMotion).first?.step
    }

    private func sourceOpacity(_ mark: QuizResultMark?, step: PairMergeStep?, hasOverlay: Bool) -> Double {
        guard mark == .correct else { return 1 }
        if step == .gone { return 0 }
        let covered = step == .merged || step == .fade
        if hasOverlay, covered { return 0 }
        return 1
    }

    private func sourceMark(_ mark: QuizResultMark?, step: PairMergeStep?, hasOverlay: Bool) -> QuizResultMark? {
        guard let mark else { return nil }
        let covered = step == .glide || step == .merged || step == .gone || step == .fade
        if mark == .correct, hasOverlay, covered { return nil }
        if mark == .correct, step == .gone { return nil }
        return mark
    }

    private func overlayOpacity(_ step: PairMergeStep?) -> Double {
        switch step {
        case .merged, .fade:
            return 1
        default:
            return 0
        }
    }

    private func overlayScale(_ step: PairMergeStep?) -> CGFloat {
        if reduceMotion { return 1 }
        switch step {
        case .gone:
            return CGFloat(QuizMotion.pairGoneScale)
        case .merged:
            return 1
        default:
            return CGFloat(QuizMotion.glyphStartScale)
        }
    }

    private func glideOffset(_ pair: MatchPair, fromLeft: Bool) -> CGSize {
        guard pairMark(pair) == .correct, !reduceMotion else { return .zero }
        switch step(for: pair.left.itemID, mark: .correct) {
        case .glide, .merged, .gone:
            break
        default:
            return .zero
        }
        guard let meeting = meetingRects(pair) else { return .zero }
        let from = fromLeft ? meeting.left : meeting.right
        let to = fromLeft ? meeting.right : meeting.left
        return CGSize(width: (to.midX - from.midX) * 0.5, height: (to.midY - from.midY) * 0.5)
    }

    private func hasMeetingPoint(_ pair: MatchPair) -> Bool {
        meetingPoint(pair) != nil
    }

    private func meetingPoint(_ pair: MatchPair) -> (center: CGPoint, size: CGSize)? {
        guard let rects = meetingRects(pair) else { return nil }
        return (
            center: CGPoint(
                x: (rects.left.midX + rects.right.midX) / 2,
                y: (rects.left.midY + rects.right.midY) / 2
            ),
            size: CGSize(
                width: max(rects.left.width, rects.right.width),
                height: max(rects.left.height, rects.right.height)
            )
        )
    }

    private func meetingRects(_ pair: MatchPair) -> (left: CGRect, right: CGRect)? {
        guard let rightID = links[pair.left.itemID] ?? (revealed ? pair.right.itemID : nil),
              let left = spots[leftKey(pair.left.itemID)],
              let right = spots[rightKey(rightID)],
              left.width > 1, right.width > 1 else { return nil }
        return (left, right)
    }

    private func spot(_ key: String) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: TileSpotKey.self,
                value: [TileSpot(key: key, rect: geo.frame(in: CoordinateSpace.named(space)))]
            )
        }
        .allowsHitTesting(false)
    }

    private func pairMark(_ pair: MatchPair) -> QuizResultMark? {
        QuizDraft.pairMark(
            linkedRight: links[pair.left.itemID],
            correctRight: pair.right.itemID,
            revealed: revealed
        )
    }

    private func linkedSide(_ id: ItemID?) -> MatchSide? {
        guard let id else { return nil }
        return task.pairs.first { $0.right.itemID == id }?.right
    }

    private func pronunciation(for text: String, itemID: ItemID) -> String? {
        QuizPresentation.spokenPronunciation(
            text: text,
            item: itemsByID[itemID],
            showsPronunciation: showsPronunciation
        )
    }

    private func matchLabel(text: String, pronunciation: String?, linkedText: String?, mark: QuizResultMark?) -> String {
        let base = QuizPresentation.matchAccessibilityLabel(
            text: text,
            pronunciation: pronunciation,
            linkedText: linkedText
        )
        guard let mark else { return base }
        return "\(base), \(QuizCopy.feedbackSpoken(correct: mark == .correct))"
    }

    private func border(selected: Bool, mark: QuizResultMark?) -> Color {
        switch mark {
        case .correct:
            Lapis.correct
        case .incorrect:
            Lapis.destructive
        case nil:
            selected ? Lapis.ring : QuizChrome.primary
        }
    }

    private func fill(_ mark: QuizResultMark?) -> Color {
        switch mark {
        case .correct:
            Lapis.correctFill
        case .incorrect:
            Lapis.incorrectFill
        case nil:
            QuizChrome.surface
        }
    }

    private func leftKey(_ id: ItemID) -> String { "L:\(id.rawValue)" }
    private func rightKey(_ id: ItemID) -> String { "R:\(id.rawValue)" }
}

private struct TileSpot: Equatable {
    var key: String
    var rect: CGRect
}

private struct TileSpotKey: PreferenceKey {
    static let defaultValue: [TileSpot] = []

    static func reduce(value: inout [TileSpot], nextValue: () -> [TileSpot]) {
        value.append(contentsOf: nextValue())
    }
}
