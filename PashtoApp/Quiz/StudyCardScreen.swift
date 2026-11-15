import AVFoundation
import PashtoCore
import SwiftUI
import UIKit

/// Learn and phrases cards in direction B.
///
/// Pronunciation is the large line. At the usual sizes Pashto sits under it,
/// then English. Learn shows the meaning. Phrases hide it until Show meaning.
/// The footer button stays outside the scrolling card.
///
/// At accessibility sizes the blue strip is a 30 pt bar plus a 4 pt progress
/// line. The title, Skip to practice, and the phrase scroll away. Once the
/// title has left, it sits on one line in the bar.
struct StudyCardScreen: View {
    var deck: StudyDeck
    var onNext: () -> StudyStep
    var onShowMeaning: () -> StudyStep
    /// Last learn card. Opens the next lesson. The button still reads Next.
    var onOpenNextLesson: () -> Void
    var onStartPractice: () -> Void
    var onSkip: () -> Void
    var onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var pronunciationFocused: Bool
    /// True once the large title has scrolled out of the accessibility bar.
    @State private var titleCollapsed = false
    /// Plays only from the speaker button. A card change stops the previous clip.
    @State private var clipPlayer = GreetingsClipPlayer()
    @AppStorage(ProfileSettingsStore.audioSpeedKey) private var audioSpeedRaw = AudioSpeed.normal.rawValue

    private var greetingsRate: Float { GreetingsPlaybackRate.rate(for: audioSpeedRaw) }

    var body: some View {
        VStack(spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                slimHeader
            } else {
                header
            }
            LapisScreen(
                scrollIdentifier: "study-card",
                scrollToID: noteScrollTarget,
                scrollCoordinateSpace: StudyCardScroll.space
            ) {
                scrollContent
            } footer: {
                Button(action: primaryTap) {
                    Text(verbatim: deck.offersStartPractice ? StudyCopy.startPractice : StudyCopy.next)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(StudyPrimaryButtonStyle())
                .accessibilitySortPriority(0)
            }
        }
        .background(pageBackground.ignoresSafeArea())
        .onPreferenceChange(StudyTitleMaxYKey.self) { maxY in
            guard dynamicTypeSize.isAccessibilitySize, maxY.isFinite, maxY < 10_000 else { return }
            // A zero frame is the title before it is measured. Negative means it
            // has left the top of the list.
            let collapsed = maxY < 0
            if collapsed != titleCollapsed {
                titleCollapsed = collapsed
            }
        }
        .onChange(of: deck.index) { _, _ in
            clipPlayer.stop()
            pronunciationFocused = true
        }
        .onChange(of: deck.lessonID) { _, _ in
            clipPlayer.stop()
        }
        .onDisappear {
            clipPlayer.stop()
        }
    }

    /// UI tests only. The note is taller than the list at the largest type,
    /// so the opened card starts at the first tip. `-uiTestNoteStaysAtTop`
    /// leaves the list at the top so a shot can show the phrase first.
    /// A normal card stays put.
    private var noteScrollTarget: String? {
        guard UITestLaunch.openItemID != nil, !UITestLaunch.noteStaysAtTop, deck.meaningVisible else { return nil }
        guard let note = deck.card?.pronunciationNote, !PronunciationNotes.tips(in: note).isEmpty else {
            return nil
        }
        return "pronunciation-tip-0"
    }

    private var pageBackground: Color {
        dynamicTypeSize.isAccessibilitySize ? Lapis.background : StudyPalette.page
    }

    @ViewBuilder
    private var scrollContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                scrollingTitle
                card
                if deck.meaningVisible, let note = deck.card?.pronunciationNote {
                    PronunciationNoteText(note: note)
                        .accessibilitySortPriority(15)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        } else {
            card
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)
        }
    }

    /// Blue strip at the usual text sizes. Back, title, progress, and Skip stay put.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            standardTitle
            LessonProgressBar(bar: LessonBar(answered: deck.index, total: max(deck.count, 1)))
                .accessibilitySortPriority(60)
            HStack {
                Spacer()
                Button(action: onSkip) {
                    Text(verbatim: StudyCopy.skipToPractice)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(StudyPalette.headerInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.trailing)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilitySortPriority(10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudyPalette.header)
    }

    /// Compact bar and a 4 pt progress line. The back control keeps its glyph
    /// size and uses a 44 pt hit area. The title and Skip are not in this bar
    /// until the large title has scrolled away. The bar does not grow with text size.
    private var slimHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                slimBackButton
                if titleCollapsed {
                    Text(verbatim: deck.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Lapis.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            slimProgress
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Lapis.background.ignoresSafeArea(edges: .top))
    }

    private var slimBackButton: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.backward")
                    .accessibilityHidden(true)
                if !titleCollapsed {
                    Text("Pashto")
                        .lineLimit(1)
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(StudyPalette.pronunciation)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Pashto"))
        .accessibilityAddTraits(.isButton)
        .accessibilitySortPriority(70)
    }

    private var slimProgress: some View {
        let fraction = LessonBar(answered: deck.index, total: max(deck.count, 1)).fraction
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(StudyPalette.barTrack)
                Rectangle()
                    .fill(StudyPalette.pronunciation)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 4)
        .accessibilityRepresentation {
            ProgressView(value: fraction)
        }
        .accessibilitySortPriority(60)
    }

    /// Large title and Skip to practice. They scroll with the phrase and the tips.
    /// Both wrap onto as many lines as the text needs.
    private var scrollingTitle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: deck.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(Lapis.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .accessibilitySortPriority(65)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: StudyTitleMaxYKey.self,
                            value: geo.frame(in: .named(StudyCardScroll.space)).maxY
                        )
                    }
                }
            Button(action: onSkip) {
                HStack(spacing: 4) {
                    Text(verbatim: StudyCopy.skipToPractice)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(StudyPalette.pronunciation)
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44, alignment: .leading)
            .accessibilitySortPriority(55)
        }
    }

    /// Back and the lesson title on one row. Regular sizes keep this row.
    private var standardTitle: some View {
        HStack(alignment: .center, spacing: 12) {
            studyBackButton(oneLine: false)
            Spacer(minLength: 8)
            Text(verbatim: deck.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(StudyPalette.headerInk)
                .accessibilityHidden(true)
        }
    }

    private func studyBackButton(oneLine: Bool) -> some View {
        Button(action: onBack) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.backward")
                    .accessibilityHidden(true)
                if oneLine {
                    Text("Pashto")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("Pashto")
                }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(StudyPalette.headerInk)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Pashto"))
        .accessibilityAddTraits(.isButton)
        .accessibilitySortPriority(70)
    }

    private var card: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center, spacing: 18) {
            if let card = deck.card {
                if let picture = FamilyPictures.picture(
                    for: card.itemID,
                    english: card.meaning,
                    lessonKind: deck.kind,
                    unitID: deck.unitID
                ) {
                    Image(picture.assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: picture.accessibilityLabel))
                        .accessibilitySortPriority(55)
                }
                StudyCardLines(
                    card: card,
                    showsMeaning: deck.meaningVisible,
                    pronunciationFocused: $pronunciationFocused
                )
                .id(deck.index)
                .transition(.opacity)
                .animation(cardAnimation, value: deck.index)
                if let url = greetingsClipURL(for: card) {
                    playButton(url)
                }
            }
            if deck.kind == .phrases, deck.meaningVisible == false {
                Button(action: revealMeaning) {
                    Text(verbatim: StudyCopy.showMeaning)
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(StudyPalette.pronunciation)
                .accessibilitySortPriority(20)
            }
            pageDots
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(StudyPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<deck.count, id: \.self) { index in
                Circle()
                    .fill(index == deck.index ? StudyPalette.pronunciation : StudyPalette.dot)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    private var cardAnimation: Animation {
        .easeOut(duration: reduceMotion ? QuizMotion.reduceMotionFade : 0.28)
    }

    private func primaryTap() {
        if deck.offersStartPractice {
            onStartPractice()
        } else if deck.isLast {
            onOpenNextLesson()
        } else {
            _ = onNext()
        }
    }

    /// Greetings learn and phrases cards only. A missing file draws nothing.
    /// The quiz never reaches this screen.
    private func greetingsClipURL(for card: StudyCard) -> URL? {
        guard deck.kind == .learn || deck.kind == .phrases else { return nil }
        guard deck.unitID.rawValue == GreetingsAudio.unitID else { return nil }
        guard let directory = Bundle.main.resourceURL else { return nil }
        return GreetingsAudio.url(for: card.itemID, in: directory)
    }

    /// Outline speaker in the card primary color, for light and dark.
    /// The label is spoken. The icon has no other text.
    private func playButton(_ url: URL) -> some View {
        Button {
            clipPlayer.play(url, rate: greetingsRate)
        } label: {
            Image(systemName: "speaker.wave.2")
                .font(.body.weight(.semibold))
                .foregroundStyle(StudyPalette.pronunciation)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background {
                    Capsule(style: .continuous)
                        .stroke(StudyPalette.pronunciation, lineWidth: 2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Play"))
        .accessibilityAddTraits(.isButton)
        .accessibilitySortPriority(21)
    }

    private func revealMeaning() {
        let step = onShowMeaning()
        guard step == .revealedMeaning, let meaning = deck.card?.meaning else { return }
        AccessibilityNotification.Announcement(meaning).post()
    }
}

/// Pronunciation, Pashto, and English for one learn or phrases card.
///
/// The same stack is used by a lesson and by the reference card. Learn shows
/// the meaning. A phrases card can hide it.
struct StudyCardLines: View {
    var card: StudyCard
    var showsMeaning: Bool
    var pronunciationFocused: AccessibilityFocusState<Bool>.Binding

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var pronunciationSize: CGFloat = 39
    /// 13 pt at the default size, scaling with the body style. Smaller than the pronunciation.
    @ScaledMetric(relativeTo: .body) private var pashtoSize: CGFloat = 13
    @ScaledMetric(relativeTo: .body) private var smallPashtoSize: CGFloat = 13
    @ScaledMetric(relativeTo: .title3) private var meaningSize: CGFloat = 22

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            largeTypeLines
        } else {
            regularLines
        }
    }

    /// Pronunciation, English, and Pashto sit together. Tips come after Pashto.
    /// Pashto stays the smallest line.
    private var regularLines: some View {
        VStack(spacing: 10) {
            pronunciation(alignment: .center, frame: .center)
            if showsMeaning {
                meaningLine(alignment: .center, priority: 40)
            }
            pashtoLine(size: pashtoSize, alignment: .center, direction: .rightToLeft, priority: 30)
            if showsMeaning {
                if let explanation = card.explanation {
                    explanationLine(explanation, alignment: .center)
                }
                if let note = card.pronunciationNote {
                    PronunciationNoteText(note: note)
                        .accessibilitySortPriority(22)
                }
            }
        }
    }

    /// Pronunciation first, then English, then small Pashto. The note is drawn
    /// under the card so a plain note can use the full width.
    private var largeTypeLines: some View {
        VStack(alignment: .leading, spacing: 10) {
            pronunciation(alignment: .leading, frame: .leading)
            if showsMeaning {
                meaningLine(alignment: .leading, priority: 40)
                if let explanation = card.explanation {
                    explanationLine(explanation, alignment: .leading)
                }
            }
            pashtoLine(size: smallPashtoSize, alignment: .leading, direction: .leftToRight, priority: 30)
        }
    }

    private func pronunciation(alignment: TextAlignment, frame: Alignment) -> some View {
        PronunciationText(stored: card.pronunciation, points: pronunciationSize, color: StudyPalette.pronunciation, alignment: alignment)
        .multilineTextAlignment(alignment)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: frame)
        .accessibilityFocused(pronunciationFocused)
        .accessibilitySortPriority(50)
    }

    private func pashtoLine(
        size: CGFloat,
        alignment: TextAlignment,
        direction: LayoutDirection,
        priority: Double
    ) -> some View {
        Text(verbatim: card.pashto)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(StudyPalette.pashto)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
            .environment(\.layoutDirection, direction)
            .accessibilitySortPriority(priority)
    }

    private func meaningLine(alignment: TextAlignment, priority: Double) -> some View {
        Text(verbatim: card.meaning)
            .font(.system(size: meaningSize, weight: .regular))
            .foregroundStyle(StudyPalette.meaning)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilitySortPriority(priority)
    }

    private func explanationLine(_ explanation: String, alignment: TextAlignment) -> some View {
        Text(verbatim: explanation)
            .font(.body)
            .foregroundStyle(StudyPalette.meaning)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilitySortPriority(25)
    }
}

/// Pronunciation tips as left-aligned rows. The stored note is unchanged.
///
/// A letter tip puts the letter and its colon in a narrow column, slightly
/// larger than the words. Wrapped words start under the first word. A tip
/// with no letter is ordinary text across the full width, with no empty
/// column. Each piece is an LTR isolate so a Pashto letter does not flip the
/// row. VoiceOver stops once on the whole note and reads the stored text.
/// A UI-test launch keeps each tip as its own element so a shot can see it.
struct PronunciationNoteText: View {
    var note: String

    /// Wide enough for one letter and its colon. It scales with the letter.
    @ScaledMetric(relativeTo: .body) private var letterColumn: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var columnGap: CGFloat = 6
    @ScaledMetric(relativeTo: .subheadline) private var rowSpacing: CGFloat = 8

    private var exposesTips: Bool { UITestLaunch.openItemID != nil }

    var body: some View {
        let stack = VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(Array(PronunciationNotes.tips(in: note).enumerated()), id: \.offset) { index, tip in
                tipRow(index: index, tip: tip)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.layoutDirection, .leftToRight)

        if exposesTips {
            stack
        } else {
            stack
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: PronunciationNotes.spoken(note)))
        }
    }

    @ViewBuilder
    private func tipRow(index: Int, tip: PronunciationTip) -> some View {
        let row = rowContent(tip)
            .id("pronunciation-tip-\(index)")
        if exposesTips {
            row
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("pronunciation-tip-\(index)")
                .accessibilityLabel(Text(verbatim: PronunciationNotes.spoken(tip.stored)))
        } else {
            row
        }
    }

    @ViewBuilder
    private func rowContent(_ tip: PronunciationTip) -> some View {
        if let letter = tip.letter {
            HStack(alignment: .firstTextBaseline, spacing: columnGap) {
                Text(verbatim: PronunciationNotes.displayLine(letter))
                    .font(.body)
                    .foregroundStyle(Lapis.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: letterColumn, alignment: .leading)
                tipWords(tip.text)
            }
            .environment(\.layoutDirection, .leftToRight)
        } else {
            tipWords(tip.text)
        }
    }

    private func tipWords(_ text: String) -> some View {
        Text(verbatim: PronunciationNotes.displayLine(text))
            .font(.subheadline)
            .foregroundStyle(Lapis.secondaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// Scroll space shared by the card list and the large-title measurement.
private enum StudyCardScroll {
    static let space = "study-card-scroll"
}

/// Bottom of the large title in the scroll view. A non-positive value means
/// the title has scrolled away and the bar can show it on one line.
private struct StudyTitleMaxYKey: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Direction B colors for the card screen. Light and dark are both specified.
enum StudyPalette {
    static let page = dynamic(light: 0xEBEFF9, dark: 0x0F172A)
    static let header = dynamic(light: 0x1E3A8A, dark: 0x1E293B)
    static let headerInk = dynamic(light: 0xF8FAFC, dark: 0xF8FAFC)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1E293B)
    static let pronunciation = dynamic(light: 0x1E3A8A, dark: 0x93B4F5)
    static let pashto = dynamic(light: 0x475569, dark: 0xCBD5E1)
    static let meaning = dynamic(light: 0x1E293B, dark: 0xF1F5F9)
    static let dot = dynamic(light: 0xCBD5E1, dark: 0x475569)
    /// 4 pt track under the accessibility bar.
    static let barTrack = dynamic(light: 0xE6EAE6, dark: 0x334155)
    static let button = dynamic(light: 0x1E3A8A, dark: 0x4666D2)
    static let buttonInk = dynamic(light: 0xFAF7F0, dark: 0xFAF7F0)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? ui(dark) : ui(light)
        })
    }

    private static func ui(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private enum StudyCopy {
    static var newWords: String { String(localized: "study.newWords") }
    static var phrases: String { String(localized: "module.section.phrases") }
    static var next: String { String(localized: "study.next") }
    static var startPractice: String { String(localized: "study.startPractice") }
    static var skipToPractice: String { String(localized: "study.skipToPractice") }
    static var showMeaning: String { String(localized: "today.showMeaning") }
}

/// Plays one bundled clip at a time. Nothing starts until `play` is called.
///
/// The session stays up while a clip is playing. It is released when that clip
/// ends, when the file cannot be read, or when `stop` runs, so other audio can
/// resume. A callback from an older player does not release the session a newer
/// clip is using.
@MainActor
final class GreetingsClipPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?

    func play(_ url: URL, rate: Float) {
        haltPlayer()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            let next = try AVAudioPlayer(contentsOf: url)
            next.enableRate = true
            next.rate = rate
            next.delegate = self
            player = next
            next.prepareToPlay()
            next.play()
        } catch {
            player = nil
            deactivate()
        }
    }

    func stop() {
        haltPlayer()
        deactivate()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor in
            self.releaseIfCurrent(finished)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor in
            self.releaseIfCurrent(finished)
        }
    }

    /// Drops the current player without releasing the session.
    private func haltPlayer() {
        let current = player
        player = nil
        current?.delegate = nil
        current?.stop()
    }

    private func releaseIfCurrent(_ finished: ObjectIdentifier) {
        guard let player, ObjectIdentifier(player) == finished else { return }
        self.player = nil
        deactivate()
    }

    private func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// The stored audio-speed choice, as a player rate.
enum GreetingsPlaybackRate {
    static func rate(for raw: String) -> Float {
        Float(AudioSpeed.resolved(raw).playbackRate)
    }
}

/// English or Pashto that wraps at spaces and shrinks a long word onto one line.
///
/// `joinLatinWords` is for English and pronunciation. It keeps a hyphen inside
/// the word. Pashto call sites leave it off, so Arabic letters stay joined
/// and in order. The spoken label is the original string. Vertical padding
/// leaves room for Pashto dots and tails.
struct FittingWords: View {
    var text: String
    var size: CGFloat
    var weight: Font.Weight
    var color: Color
    var alignment: TextAlignment
    var direction: LayoutDirection
    var lineSpacing: CGFloat = 0
    var verticalPadding: CGFloat = 0
    /// Word joiners for Latin text. Pashto passes `false`.
    var joinLatinWords: Bool = false
    /// The learn row keeps its point size. Other callers still fit a long word.
    var shrinksToFit: Bool = true

    @State private var availableWidth: CGFloat = 0

    private var words: [String] {
        text.split(separator: " ", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
    }

    private var scale: CGFloat {
        guard shrinksToFit else { return 1 }
        let widest = words.map { FittingWordMeasure.width($0, size: size, weight: weight) }.max() ?? 0
        guard widest > 0, availableWidth > 0 else { return 1 }
        return min(1, availableWidth / widest)
    }

    var body: some View {
        let shown = scale
        FittingWordFlow(
            alignment: alignment,
            spacing: FittingWordMeasure.space(size: size * shown, weight: weight),
            lineSpacing: lineSpacing,
            rightToLeft: direction == .rightToLeft
        ) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                Text(verbatim: displayed(word))
                    .font(.system(size: size * shown, weight: weight))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.vertical, verticalPadding)
                    .accessibilityHidden(true)
                    .environment(\.layoutDirection, direction)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: FittingWidthKey.self, value: geo.size.width)
            }
        }
        .onPreferenceChange(FittingWidthKey.self) { width in
            if abs(width - availableWidth) > 0.5 {
                availableWidth = width
            }
        }
        // Trailing stays on the right. RTL on the stack would flip it to the left.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }

    /// Latin words stay unbreakable. Pashto is the same characters it arrived with.
    private func displayed(_ word: String) -> String {
        guard joinLatinWords else { return word }
        return WordBreakPolicy.display(word)
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }
}

private enum FittingWordMeasure {
    static func width(_ word: String, size: CGFloat, weight: Font.Weight) -> CGFloat {
        let font = UIFont.systemFont(ofSize: size, weight: uiWeight(weight))
        return ceil((word as NSString).size(withAttributes: [.font: font]).width)
    }

    static func space(size: CGFloat, weight: Font.Weight) -> CGFloat {
        width(" ", size: size, weight: weight)
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        default: .regular
        }
    }
}

private struct FittingWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Wraps words at spaces. A word is already one line.
private struct FittingWordFlow: Layout {
    var alignment: TextAlignment
    var spacing: CGFloat
    var lineSpacing: CGFloat
    var rightToLeft: Bool

    private struct Line {
        var indexes: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    nonisolated func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let lines = wrap(proposal: proposal, subviews: subviews)
        let gaps = CGFloat(max(lines.count - 1, 0)) * lineSpacing
        let height = lines.reduce(CGFloat(0)) { $0 + $1.height } + gaps
        if let width = proposal.width, width.isFinite {
            return CGSize(width: width, height: height)
        }
        return CGSize(width: lines.map(\.width).max() ?? 0, height: height)
    }

    nonisolated func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let lines = wrap(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        var y = bounds.minY
        for (lineIndex, line) in lines.enumerated() {
            let extra = max(0, bounds.width - line.width)
            let blockMinX: CGFloat
            switch alignment {
            case .center:
                blockMinX = bounds.minX + extra / 2
            case .trailing:
                blockMinX = bounds.minX + extra
            default:
                blockMinX = bounds.minX
            }
            if rightToLeft {
                var x = blockMinX + line.width
                for (offset, index) in line.indexes.enumerated() {
                    let size = line.sizes[offset]
                    if offset > 0 { x -= spacing }
                    x -= size.width
                    subviews[index].place(
                        at: CGPoint(x: x, y: y),
                        anchor: .topLeading,
                        proposal: ProposedViewSize(width: size.width, height: size.height)
                    )
                }
            } else {
                var x = blockMinX
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
            }
            y += line.height
            if lineIndex < lines.count - 1 { y += lineSpacing }
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

/// English on the left, pronunciation and Pashto on the right, about 42/58.
/// Text is not scaled to fit.
private struct LearnTextColumns: Layout {
    var leadingFraction: CGFloat

    nonisolated func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 0
        let parts = widths(for: width)
        let left = subviews[0].sizeThatFits(ProposedViewSize(width: parts.leading, height: nil))
        let right = subviews[1].sizeThatFits(ProposedViewSize(width: parts.trailing, height: nil))
        return CGSize(width: width, height: max(left.height, right.height))
    }

    nonisolated func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let parts = widths(for: bounds.width)
        let leftSize = subviews[0].sizeThatFits(ProposedViewSize(width: parts.leading, height: nil))
        let rightSize = subviews[1].sizeThatFits(ProposedViewSize(width: parts.trailing, height: nil))
        let height = max(leftSize.height, rightSize.height)
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: parts.leading, height: height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: ProposedViewSize(width: parts.trailing, height: height)
        )
    }

    private nonisolated func widths(for width: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        let gap: CGFloat = 9
        let usable = max(0, width - gap)
        let leading = (usable * leadingFraction).rounded(.down)
        return (leading, max(0, usable - leading))
    }
}

/// Scrollable words for one learn lesson.
///
/// English is on the left. Pronunciation is the main text on the right, with
/// grey Pashto right-aligned under it. A lesson with no clip has no Play column.
/// A picture uses that same leading slot. XL stacks English, pronunciation,
/// then right-aligned Pashto, and caps the picture.
/// A speaker plays only after a tap. Practice opens the quiz.
/// Flashcards open the card view. Looking at the list does not finish the lesson.
/// At the largest text sizes the word count and Practice lesson scroll with the list.
struct LearnListScreen: View {
    var list: LearnList
    var onPractice: () -> Void
    var onFlashcards: () -> Void
    var onBack: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var clipPlayer = GreetingsClipPlayer()
    @AppStorage(ProfileSettingsStore.audioSpeedKey) private var audioSpeedRaw = AudioSpeed.normal.rawValue
    /// Dynamic Type still scales these. The default is a step under the old row.
    /// Pashto is 13 pt at the default size and is not shrunk to fit.
    @ScaledMetric(relativeTo: .body) private var englishSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var pronunciationSize: CGFloat = 19
    @ScaledMetric(relativeTo: .body) private var pashtoSize: CGFloat = 13

    private var greetingsRate: Float { GreetingsPlaybackRate.rate(for: audioSpeedRaw) }
    @ScaledMetric(relativeTo: .body) private var pashtoLineSpacing: CGFloat = 8
    @ScaledMetric(relativeTo: .body) private var pashtoPadding: CGFloat = 4
    /// Thumbnail base. XL uses the scaled value, capped.
    private static let imagePointSize: CGFloat = 40
    private static let imageXLCap: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var tileSide: CGFloat = 40

    private var hue: Color { Lapis.MenuCard.resolve(list.unitID).hue }

    /// XL and the accessibility sizes stack. The default size stays two columns.
    private var stacksRow: Bool { dynamicTypeSize >= .xxxLarge }

    /// The Play column is a lesson choice. One clip keeps it, including on rows with none.
    private var showsPlayColumn: Bool { list.rows.contains { $0.showsPlayButton } }

    /// Pictures use the same leading slot as Play. A lesson does not have both.
    private var showsImageColumn: Bool { list.rows.contains { $0.picture != nil } }

    /// 40 pt until the row stacks. XL scales it and stops at 64 pt.
    private var imageSide: CGFloat {
        stacksRow ? min(tileSide, Self.imageXLCap) : Self.imagePointSize
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                wordCard
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                if dynamicTypeSize.isAccessibilitySize {
                    footer
                }
            }
            if !dynamicTypeSize.isAccessibilitySize {
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Lapis.background.ignoresSafeArea())
        .onChange(of: list.lessonID) { _, _ in
            clipPlayer.stop()
        }
        .onDisappear {
            clipPlayer.stop()
        }
        .accessibilityIdentifier("learn-list")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    backButton
                    titleBlock
                }
            } else {
                ZStack {
                    titleBlock
                    HStack {
                        backButton
                        Spacer(minLength: 0)
                    }
                }
            }
            progressBar
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.backward")
                    .accessibilityHidden(true)
                Text("Pashto")
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Lapis.text)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Pashto"))
        .accessibilityAddTraits(.isButton)
    }

    private var titleBlock: some View {
        Text(verbatim: list.title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(Lapis.text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }

    /// Practice words over the words in this lesson. An empty bar is zero completed.
    private var progressBar: some View {
        let fraction = list.wordCount > 0 ? CGFloat(list.completedCount) / CGFloat(list.wordCount) : 0
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Lapis.muted.opacity(0.35))
                Capsule()
                    .fill(hue)
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 4, maxHeight: 4)
        .accessibilityHidden(true)
    }

    private var wordCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(list.rows.enumerated()), id: \.element.itemID) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(Lapis.muted.opacity(0.35))
                        .frame(maxWidth: .infinity, minHeight: 0.5, maxHeight: 0.5)
                        .accessibilityHidden(true)
                }
                wordRow(row)
            }
        }
    }

    private func wordRow(_ row: LearnListRow) -> some View {
        HStack(alignment: stacksRow ? .top : .center, spacing: 8) {
            if showsPlayColumn {
                playSlot(row)
            } else if showsImageColumn {
                imageSlot(row)
            }
            if stacksRow {
                stackedWords(row)
            } else {
                LearnTextColumns(leadingFraction: 0.42) {
                    englishColumn(row, alignment: .leading)
                    pronunciationColumn(row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityIdentifier(row.itemID.rawValue)
    }

    private func stackedWords(_ row: LearnListRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            englishColumn(row, alignment: .leading)
            pronunciationLine(row, alignment: .leading)
            pashtoLine(row, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 40 pt picture in the 44 pt leading slot, so English lines up with Play rows.
    /// XL keeps the picture beside the stack and does not grow it past 64 pt.
    @ViewBuilder
    private func imageSlot(_ row: LearnListRow) -> some View {
        let side = imageSide
        let slot = stacksRow ? side : 44
        if let picture = row.picture {
            Image(picture.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .frame(width: slot, height: slot)
                .accessibilityHidden(true)
        } else {
            Color.clear
                .frame(width: slot, height: slot)
                .accessibilityHidden(true)
        }
    }

    private func englishColumn(_ row: LearnListRow, alignment: TextAlignment) -> some View {
        FittingWords(
            text: row.english,
            size: englishSize,
            weight: .medium,
            color: Lapis.text,
            alignment: alignment,
            direction: .leftToRight,
            joinLatinWords: true,
            shrinksToFit: false
        )
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }

    /// Trailing stack. RTL stays on the Pashto text, so trailing remains the right edge.
    private func pronunciationColumn(_ row: LearnListRow) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            pronunciationLine(row, alignment: .trailing)
            pashtoLine(row, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func pronunciationLine(_ row: LearnListRow, alignment: TextAlignment) -> some View {
        PronunciationText(stored: row.pronunciation, points: pronunciationSize, color: hue, alignment: alignment, unstressedWeight: 500, shrinksToFit: false)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }

    private func pashtoLine(_ row: LearnListRow, alignment: TextAlignment) -> some View {
        FittingWords(
            text: row.pashto,
            size: pashtoSize,
            weight: .regular,
            color: Lapis.wordListPashto,
            alignment: alignment,
            direction: .rightToLeft,
            lineSpacing: pashtoLineSpacing,
            verticalPadding: pashtoPadding,
            joinLatinWords: false,
            shrinksToFit: false
        )
    }

    /// 30 pt speaker inside a 44 pt hit area. A row without a clip keeps the empty spot.
    @ViewBuilder
    private func playSlot(_ row: LearnListRow) -> some View {
        if row.showsPlayButton, let url = clipURL(for: row.itemID) {
            playButton(url)
        } else {
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }

    /// Outline speaker. Nothing plays until this button is tapped.
    private func playButton(_ url: URL) -> some View {
        Button {
            clipPlayer.play(url, rate: greetingsRate)
        } label: {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(hue)
                .frame(width: 30, height: 30)
                .background(hue.opacity(0.16), in: Circle())
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ModuleCopy.play))
        .accessibilityAddTraits(.isButton)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    countText
                    Spacer(minLength: 12)
                    practiceButton
                }
                VStack(alignment: .leading, spacing: 4) {
                    countText
                    practiceButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            flashcardsButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var countText: some View {
        Text(verbatim: list.countLabel)
            .font(.subheadline)
            .foregroundStyle(Lapis.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var practiceButton: some View {
        Button(action: onPractice) {
            Text(verbatim: ModuleCopy.practiceLesson)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(hue)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(Text(verbatim: ModuleCopy.practiceLessonSpoken))
    }

    private var flashcardsButton: some View {
        Button(action: onFlashcards) {
            Text(verbatim: ModuleCopy.flashcards)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(hue)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(hue, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func clipURL(for itemID: ItemID) -> URL? {
        guard let directory = Bundle.main.resourceURL else { return nil }
        return GreetingsAudio.url(for: itemID, in: directory)
    }
}

struct StudyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.heavy))
            .foregroundStyle(StudyPalette.buttonInk)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(StudyPalette.button)
            }
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}
