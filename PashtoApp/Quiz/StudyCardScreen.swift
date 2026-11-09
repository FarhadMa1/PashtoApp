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
    @AccessibilityFocusState private var pronunciationFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var pronunciationSize: CGFloat = 39
    @ScaledMetric(relativeTo: .title2) private var pashtoSize: CGFloat = 32
    @ScaledMetric(relativeTo: .title3) private var meaningSize: CGFloat = 22

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
            pronunciationFocused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.backward")
                            .accessibilityHidden(true)
                        Text("Pashto")
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
                Spacer(minLength: 8)
                Text(verbatim: deck.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(StudyPalette.headerInk)
                    .accessibilityHidden(true)
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

    private var card: some View {
        VStack(spacing: 18) {
            if let card = deck.card {
                VStack(spacing: 10) {
                    Text(verbatim: card.pronunciation)
                        .font(.system(size: pronunciationSize, weight: .bold))
                        .foregroundStyle(StudyPalette.pronunciation)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityFocused($pronunciationFocused)
                        .accessibilitySortPriority(50)
                    Text(verbatim: card.pashto)
                        .font(.system(size: pashtoSize, weight: .regular))
                        .foregroundStyle(StudyPalette.pashto)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .environment(\.layoutDirection, .rightToLeft)
                        .accessibilitySortPriority(40)
                    if deck.meaningVisible {
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
                .id(deck.index)
                .transition(.opacity)
                .animation(cardAnimation, value: deck.index)
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

    private func revealMeaning() {
        let step = onShowMeaning()
        guard step == .revealedMeaning, let meaning = deck.card?.meaning else { return }
        AccessibilityNotification.Announcement(meaning).post()
    }
}

/// Direction B colors for the card screen. Light and dark are both specified.
private enum StudyPalette {
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

private struct StudyPrimaryButtonStyle: ButtonStyle {
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
