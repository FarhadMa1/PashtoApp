import AVFoundation
import PashtoCore
import SwiftUI
import UIKit

/// Learn and phrases cards in direction B.
///
/// Pronunciation is the large line. Pashto is smaller and stays right to left.
/// English sits under them. Learn shows the meaning. Phrases hide it until
/// Show meaning. The footer button stays outside the scrolling card.
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
    /// Plays only from the speaker button. A card change stops the previous clip.
    @State private var clipPlayer = GreetingsClipPlayer()

    var body: some View {
        VStack(spacing: 0) {
            header
            LapisScreen {
                card
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
            } footer: {
                Button(action: primaryTap) {
                    Text(verbatim: deck.offersStartPractice ? StudyCopy.startPractice : StudyCopy.next)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(StudyPrimaryButtonStyle())
                .accessibilitySortPriority(0)
            }
        }
        .background(StudyPalette.page.ignoresSafeArea())
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityTitle
            } else {
                standardTitle
            }
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

    /// Back on its own row, then the lesson title at full width.
    ///
    /// The title wraps between words. Nothing is drawn over the back button.
    /// VoiceOver reads the visible title.
    private var accessibilityTitle: some View {
        VStack(alignment: .leading, spacing: 12) {
            studyBackButton(oneLine: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: deck.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(StudyPalette.headerInk)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilitySortPriority(65)
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
        VStack(spacing: 18) {
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
            clipPlayer.play(url)
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

    @ScaledMetric(relativeTo: .largeTitle) private var pronunciationSize: CGFloat = 39
    @ScaledMetric(relativeTo: .title2) private var pashtoSize: CGFloat = 32
    @ScaledMetric(relativeTo: .title3) private var meaningSize: CGFloat = 22

    var body: some View {
        VStack(spacing: 10) {
            PronunciationText(stored: card.pronunciation, points: pronunciationSize, color: StudyPalette.pronunciation, alignment: .center)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityFocused(pronunciationFocused)
                .accessibilitySortPriority(50)
            Text(verbatim: card.pashto)
                .font(.system(size: pashtoSize, weight: .regular))
                .foregroundStyle(StudyPalette.pashto)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .environment(\.layoutDirection, .rightToLeft)
                .accessibilitySortPriority(40)
            if showsMeaning {
                Text(verbatim: card.meaning)
                    .font(.system(size: meaningSize, weight: .regular))
                    .foregroundStyle(StudyPalette.meaning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilitySortPriority(30)
                if let explanation = card.explanation {
                    Text(verbatim: explanation)
                        .font(.body)
                        .foregroundStyle(StudyPalette.meaning)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilitySortPriority(25)
                }
                if let note = card.pronunciationNote {
                    Text(verbatim: note)
                        .font(.subheadline)
                        .foregroundStyle(Lapis.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilitySortPriority(22)
                }
            }
        }
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

    func play(_ url: URL) {
        haltPlayer()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            let next = try AVAudioPlayer(contentsOf: url)
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

/// Scrollable words for one learn lesson.
///
/// English sits above the stored pronunciation. Pashto stays on the right,
/// with room for the dots and the tail. A speaker is drawn only when a clip
/// exists, and it plays only after a tap. Practice opens the quiz. Flashcards
/// open the card view. Looking at the list does not finish the lesson.
struct LearnListScreen: View {
    var list: LearnList
    var onPractice: () -> Void
    var onFlashcards: () -> Void
    var onBack: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var clipPlayer = GreetingsClipPlayer()
    @ScaledMetric(relativeTo: .body) private var englishSize: CGFloat = 18
    @ScaledMetric(relativeTo: .title3) private var pronunciationSize: CGFloat = 21
    @ScaledMetric(relativeTo: .body) private var pashtoSize: CGFloat = 19
    @ScaledMetric(relativeTo: .body) private var pashtoLineSpacing: CGFloat = 8
    @ScaledMetric(relativeTo: .body) private var pashtoPadding: CGFloat = 4
    @ScaledMetric(relativeTo: .body) private var tileSide: CGFloat = 48

    private var hue: Color { Lapis.MenuCard.resolve(list.unitID).hue }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                wordCard
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
            }
            footer
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
        .background(QuizChrome.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Lapis.muted.opacity(0.45), lineWidth: 0.5)
        }
    }

    private func wordRow(_ row: LearnListRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let picture = row.picture {
                Image(picture.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: tileSide, height: tileSide)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.english)
                    .font(.system(size: englishSize, weight: .medium))
                    .foregroundStyle(Lapis.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.layoutDirection, .leftToRight)
                PronunciationText(stored: row.pronunciation, points: pronunciationSize, color: hue, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: row.pashto)
                    .font(.system(size: pashtoSize))
                    .foregroundStyle(Lapis.secondaryText)
                    .multilineTextAlignment(.trailing)
                    .lineSpacing(pashtoLineSpacing)
                    .padding(.vertical, pashtoPadding)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.layoutDirection, .rightToLeft)
                if row.showsPlayButton, let url = clipURL(for: row.itemID) {
                    playButton(url)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityIdentifier(row.itemID.rawValue)
    }

    /// Outline speaker. Nothing plays until this button is tapped.
    private func playButton(_ url: URL) -> some View {
        Button {
            clipPlayer.play(url)
        } label: {
            Image(systemName: "speaker.wave.2")
                .font(.body.weight(.semibold))
                .foregroundStyle(hue)
                .frame(minWidth: 44, minHeight: 44)
                .background(hue.opacity(0.16), in: Circle())
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
