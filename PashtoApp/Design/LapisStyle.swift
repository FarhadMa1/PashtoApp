import PashtoCore
import SwiftUI
import UIKit

/// Lapis+ colors from the approved screens. Light and dark are both specified.
enum Lapis {
    static let background = dynamic(light: 0xFAF7F0, dark: 0x0F172A)
    static let text = dynamic(light: 0x111827, dark: 0xF1F5F9)
    static let secondaryText = dynamic(light: 0x6B7280, dark: 0x94A3B8)
    /// Unfilled goal track, path connector, and not-yet-reached node outline. `#7C8799` in both modes.
    static let muted = dynamic(light: QuizResultPalette.muted, dark: QuizResultPalette.muted)
    static let saffron = dynamic(light: 0xE8A33D, dark: 0xF2B85B)
    /// Ring, dot, selected match frame, and selected choice frame. Light `#B97D22` clears 3:1. `#E8A33D` does not.
    static let ring = dynamic(light: QuizResultPalette.ringLight, dark: QuizResultPalette.ringDark)
    static let saffronInk = color(0x1F1300)
    static let saffronShadow = color(0xB97D22)
    static let destructive = dynamic(
        light: QuizResultPalette.incorrectMarkLight,
        dark: QuizResultPalette.incorrectMarkDark
    )
    /// Border and check icon. Light `#16A34A` is not used for text.
    static let correct = dynamic(
        light: QuizResultPalette.correctMarkLight,
        dark: QuizResultPalette.correctMarkDark
    )
    /// Banner text. Darker than the light-mode check, because `#16A34A` on mint is about 3.1:1.
    static let correctText = dynamic(
        light: QuizResultPalette.correctTextLight,
        dark: QuizResultPalette.correctTextDark
    )
    static let correctFill = dynamic(
        light: QuizResultPalette.correctFillLight,
        dark: QuizResultPalette.correctFillDark
    )
    static let incorrectFill = dynamic(
        light: QuizResultPalette.incorrectFillLight,
        dark: QuizResultPalette.incorrectFillDark
    )
    /// Pashto and English on a correct or wrong fill.
    static let fillText = dynamic(
        light: QuizResultPalette.fillTextLight,
        dark: QuizResultPalette.fillTextDark
    )
    /// Pronunciation on a correct or wrong fill.
    static let fillPronunciation = dynamic(
        light: QuizResultPalette.fillPronunciationLight,
        dark: QuizResultPalette.fillPronunciationDark
    )
    /// Next-lesson fill. Light `#1E3A8A`. Dark `#4666D2`.
    static let badge = dynamic(light: QuizResultPalette.badgeLight, dark: QuizResultPalette.badgeDark)
    /// 1 pt lesson-bar outline. Light `#1E3A8A`, dark `#93B4F5`. Both clear 3:1 on the page.
    static let primary = dynamic(
        light: QuizResultPalette.lessonBarOutlineLight,
        dark: QuizResultPalette.lessonBarOutlineDark
    )
    /// Cream on the badge. `#FAF7F0` in both modes.
    static let badgeInk = color(QuizResultPalette.badgeInk)
    static let heroTop = color(0x2747A6)
    static let heroMiddle = color(0x1E3A8A)
    static let heroBottom = color(0x152B6B)
    static let girih = color(0xFAF7F0).opacity(0.13)
    static let heroShadow = color(0x1E3A8A).opacity(0.35)

    /// Completed practice ring and check. Light `#166534` clears 4.5:1 on each card fill.
    static let menuCheck = dynamic(light: 0x166534, dark: 0x4ADE80)
    /// Continue strip lip. Light `#07122F` on white. Dark uses the primary hue.
    static let continueLip = dynamic(light: 0x07122F, dark: 0x93B4F5)

    /// Fill, hue, and ring track for one home card. Hue is the border, lip, text, and ring.
    struct MenuCard {
        var fill: Color
        var hue: Color
        var track: Color

        /// Basics lapis card.
        static let lapis = MenuCard(
            fill: dynamic(light: 0xDCE5FB, dark: 0x1B2A4A),
            hue: dynamic(light: 0x1E3A8A, dark: 0x93B4F5),
            track: dynamic(light: 0xA8B8E0, dark: 0x334155)
        )
        /// Greetings saffron card.
        static let saffron = MenuCard(
            fill: dynamic(light: 0xFBE3BC, dark: 0x3A2A12),
            hue: dynamic(light: 0x8A5A12, dark: 0xF2B85B),
            track: dynamic(light: 0xE0C080, dark: 0x5C4A28)
        )

        static func resolve(_ unitID: UnitID) -> MenuCard {
            switch unitID.rawValue {
            case "u-greetings":
                saffron
            case "u-introductions":
                MenuCard(
                    fill: dynamic(light: 0xCDEDE7, dark: 0x12352F),
                    hue: dynamic(light: 0x0F5E55, dark: 0x5EEAD4),
                    track: dynamic(light: 0x7DB5AB, dark: 0x2A4A44)
                )
            case "u-family":
                MenuCard(
                    fill: dynamic(light: 0xF6D6DC, dark: 0x3A1A24),
                    hue: dynamic(light: 0x8E2F45, dark: 0xFDA4AF),
                    track: dynamic(light: 0xD4A0A8, dark: 0x5C3340)
                )
            case "u-time":
                // Light track is a quarter of the way from the fill toward the ink.
                MenuCard(
                    fill: dynamic(light: 0xDDEBCF, dark: 0x1F3315),
                    hue: dynamic(light: 0x3F5F1E, dark: 0xBEF264),
                    track: dynamic(light: 0xB3C6A2, dark: 0x3A5229)
                )
            case "u-travel":
                MenuCard(
                    fill: dynamic(light: 0xE6DDF7, dark: 0x2A1E42),
                    hue: dynamic(light: 0x5B2E91, dark: 0xC4B5FD),
                    track: dynamic(light: 0xC1B1DF, dark: 0x4A3A6B)
                )
            case "u-numbers":
                MenuCard(
                    fill: dynamic(light: 0xD4ECF7, dark: 0x0F2A3A),
                    hue: dynamic(light: 0x0B5674, dark: 0x7DD3FC),
                    track: dynamic(light: 0xA2C6D6, dark: 0x2A546A)
                )
            case "u-food":
                MenuCard(
                    fill: dynamic(light: 0xFADDC9, dark: 0x3A1F12),
                    hue: dynamic(light: 0x9A3A10, dark: 0xFDBA74),
                    track: dynamic(light: 0xE2B49B, dark: 0x6B462A)
                )
            case "u-town":
                MenuCard(
                    fill: dynamic(light: 0xDEE4EE, dark: 0x1A2433),
                    hue: dynamic(light: 0x2E4560, dark: 0xBCCDE3),
                    track: dynamic(light: 0xB2BCCA, dark: 0x424E5F)
                )
            case "u-conversation":
                MenuCard(
                    fill: dynamic(light: 0xF5DAF0, dark: 0x36173A),
                    hue: dynamic(light: 0x86198F, dark: 0xF0ABFC),
                    track: dynamic(light: 0xD9AAD8, dark: 0x643C6A)
                )
            default:
                lapis
            }
        }
    }

    static var heroGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: heroTop, location: 0),
                .init(color: heroMiddle, location: 0.45),
                .init(color: heroBottom, location: 1),
            ],
            startPoint: UnitPoint(x: 0.2, y: 0),
            endPoint: UnitPoint(x: 0.8, y: 1)
        )
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(uiColor: ui(hex))
    }

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

/// Cream page, scrolling text, and a footer that stays on screen at large type.
struct LapisScreen<Content: View, Footer: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content()
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer()
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Lapis.background.ignoresSafeArea())
    }
}

/// Saffron primary button. The shadow is the hard offset from the design.
struct SaffronButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.heavy))
            .foregroundStyle(Lapis.saffronInk)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Lapis.saffronShadow)
                    .offset(y: 4)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Lapis.saffron)
                    .offset(y: configuration.isPressed ? 2 : 0)
            }
            .padding(.bottom, 4)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

/// Design B colours for the quiz. Saffron is the streak mark only, never quiz text.
enum QuizChrome {
    static let page = Lapis.background
    static let ink = Lapis.text
    static let surface = dynamic(light: QuizDesignPalette.surfaceLight, dark: QuizDesignPalette.surfaceDark)
    static let pashto = dynamic(light: QuizDesignPalette.pashtoLight, dark: QuizDesignPalette.pashtoDark)
    static let primary = dynamic(light: QuizDesignPalette.pronunciationLight, dark: QuizDesignPalette.pronunciationDark)
    static let tint = dynamic(light: QuizDesignPalette.tintLight, dark: QuizDesignPalette.tintDark)
    static let badge = Lapis.badge
    static let cream = Lapis.badgeInk
    static let muted = Lapis.muted
    static let barTrack = color(QuizDesignPalette.barTrack)
    static let barFill = color(QuizDesignPalette.barFill)
    static let buttonLip = color(QuizDesignPalette.buttonLipLight)
    /// Decorative streak mark. It is not a text colour.
    static let saffron = color(QuizDesignPalette.saffronAccent)

    private static func color(_ hex: UInt32) -> Color {
        Color(uiColor: ui(hex))
    }

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

/// Full-width answer face. The lower edge is the tactile lip from Design B.
struct QuizTactilePlate: View {
    var fill: Color
    var edge: Color
    var lipColor: Color
    var pressed = false
    var lineWidth: CGFloat = 2
    var corner: CGFloat = 17

    private var lip: CGFloat { lineWidth >= 3 ? 4 : 3 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(lipColor)
                .offset(y: lip)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(edge, lineWidth: lineWidth)
                }
                .offset(y: pressed ? 2 : 0)
        }
        .accessibilityHidden(true)
    }
}

/// Answer, word, and pair buttons. The label stays at least 44 pt tall.
struct QuizTactileButtonStyle: ButtonStyle {
    var fill: Color
    var edge: Color
    var lipColor: Color
    var expands = true
    var alignment: Alignment = .leading
    var lineWidth: CGFloat = 2

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(
                maxWidth: expands ? .infinity : nil,
                minHeight: 44,
                alignment: alignment
            )
            .background {
                QuizTactilePlate(
                    fill: fill,
                    edge: edge,
                    lipColor: lipColor,
                    pressed: configuration.isPressed,
                    lineWidth: lineWidth
                )
            }
            .padding(.bottom, 3)
    }
}

/// Home category card. The lip and the border are the card's own hue.
struct MenuHueButtonStyle: ButtonStyle {
    var fill: Color
    var hue: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                QuizTactilePlate(
                    fill: fill,
                    edge: hue,
                    lipColor: hue,
                    pressed: configuration.isPressed,
                    lineWidth: 2,
                    corner: 18
                )
            }
            .padding(.bottom, 5)
    }
}

/// Continue strip and a category lesson. White face, lapis edge, dark lip.
struct SurfaceCardButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 58

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: max(minHeight, 44), alignment: .leading)
            .contentShape(Rectangle())
            .background {
                QuizTactilePlate(
                    fill: QuizChrome.surface,
                    edge: Lapis.primary,
                    lipColor: Lapis.continueLip,
                    pressed: configuration.isPressed,
                    lineWidth: 2,
                    corner: 16
                )
            }
            .padding(.bottom, 5)
    }
}

/// Quiz Continue. Cream on the badge. Saffron is not the button.
struct QuizContinueButtonStyle: ButtonStyle {
    var enabled: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let fill = enabled ? QuizChrome.badge : QuizChrome.surface
        let ink = enabled ? QuizChrome.cream : QuizChrome.pashto
        let edge: Color
        let lip: Color
        if enabled, colorScheme == .dark {
            edge = QuizChrome.primary
            lip = QuizChrome.primary
        } else if enabled {
            edge = QuizChrome.badge
            lip = QuizChrome.buttonLip
        } else {
            edge = QuizChrome.muted
            lip = QuizChrome.muted
        }
        return configuration.label
            .font(.body.weight(.heavy))
            .foregroundStyle(ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                QuizTactilePlate(
                    fill: fill,
                    edge: edge,
                    lipColor: lip,
                    pressed: configuration.isPressed && enabled
                )
            }
            .padding(.bottom, 4)
            .opacity(configuration.isPressed && enabled ? 0.92 : 1)
    }
}

/// Two rounded squares, one turned 45 degrees. The approved badge.
struct Octagram: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        let inset = side * 0.18
        let square = CGRect(
            x: origin.x + inset,
            y: origin.y + inset,
            width: side - inset * 2,
            height: side - inset * 2
        )
        let radius = side * 0.08
        var path = Path(roundedRect: square, cornerRadius: radius)
        let turn = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .rotated(by: .pi / 4)
            .translatedBy(x: -rect.midX, y: -rect.midY)
        path.addPath(Path(roundedRect: square, cornerRadius: radius), transform: turn)
        return path
    }

    func inset(by amount: CGFloat) -> Octagram {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

struct OctagramBadge<Mark: View>: View {
    var fill: Color
    var side: CGFloat = 132
    @ViewBuilder var mark: () -> Mark

    var body: some View {
        ZStack {
            Octagram().fill(fill)
            mark()
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// The girih tile drawn over the lapis hero. It is decoration.
struct GirihPattern: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 56
            var path = Path()
            let columns = Int(ceil(size.width / tile)) + 1
            let rows = Int(ceil(size.height / tile)) + 1
            for row in 0..<rows {
                for column in 0..<columns {
                    let x = CGFloat(column) * tile
                    let y = CGFloat(row) * tile
                    let square = CGRect(x: x + 14, y: y + 14, width: 28, height: 28)
                    path.addRect(square)
                    let center = CGPoint(x: x + 28, y: y + 28)
                    let turn = CGAffineTransform(translationX: center.x, y: center.y)
                        .rotated(by: .pi / 4)
                        .translatedBy(x: -center.x, y: -center.y)
                    path.addPath(Path(square), transform: turn)
                    path.addEllipse(in: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12))
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + 14, y: y + 14))
                    path.move(to: CGPoint(x: x + tile, y: y))
                    path.addLine(to: CGPoint(x: x + 42, y: y + 14))
                    path.move(to: CGPoint(x: x, y: y + tile))
                    path.addLine(to: CGPoint(x: x + 14, y: y + 42))
                    path.move(to: CGPoint(x: x + tile, y: y + tile))
                    path.addLine(to: CGPoint(x: x + 42, y: y + 42))
                }
            }
            context.stroke(path, with: .color(Lapis.girih), lineWidth: 1.4)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct WelcomeHero: View {
    var body: some View {
        OctagramBadge(fill: Lapis.saffron) {
            SunriseMark()
                .stroke(
                    Lapis.saffronInk,
                    style: StrokeStyle(lineWidth: 2 * 60 / 24, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 60, height: 60)
        }
        .padding(.vertical, 34)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)
        .background {
            Lapis.heroGradient
            GirihPattern()
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Lapis.heroShadow, radius: 15, y: 14)
        .accessibilityHidden(true)
    }
}

/// Sunrise over a horizon. The arc is the upper half of the circle.
struct SunriseMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(4, 17, in: rect))
        path.addLine(to: point(20, 17, in: rect))
        path.move(to: point(7, 17, in: rect))
        path.addArc(
            center: point(12, 17, in: rect),
            radius: 5 / 24 * min(rect.width, rect.height),
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: true
        )
        path.move(to: point(12, 6, in: rect))
        path.addLine(to: point(12, 8, in: rect))
        path.move(to: point(5.6, 9.6, in: rect))
        path.addLine(to: point(7, 11, in: rect))
        path.move(to: point(18.4, 9.6, in: rect))
        path.addLine(to: point(17, 11, in: rect))
        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + x / 24 * rect.width,
            y: rect.minY + y / 24 * rect.height
        )
    }
}

struct UpArrowMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(12, 19, in: rect))
        path.addLine(to: point(12, 5, in: rect))
        path.move(to: point(5, 12, in: rect))
        path.addLine(to: point(12, 5, in: rect))
        path.addLine(to: point(19, 12, in: rect))
        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + x / 24 * rect.width,
            y: rect.minY + y / 24 * rect.height
        )
    }
}

struct ExclamationMark: View {
    var side: CGFloat = 52

    var body: some View {
        ZStack {
            ExclamationStem()
                .stroke(
                    Lapis.saffronInk,
                    style: StrokeStyle(lineWidth: 2.2 * side / 24, lineCap: .round)
                )
            Circle()
                .fill(Lapis.saffronInk)
                .frame(width: max(3, 1.8 * side / 24), height: max(3, 1.8 * side / 24))
                .offset(y: 5 * side / 24)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

private struct ExclamationStem: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaleX = rect.width / 24
        let scaleY = rect.height / 24
        path.move(to: CGPoint(x: rect.minX + 12 * scaleX, y: rect.minY + 7 * scaleY))
        path.addLine(to: CGPoint(x: rect.minX + 12 * scaleX, y: rect.minY + 13 * scaleY))
        return path
    }
}
