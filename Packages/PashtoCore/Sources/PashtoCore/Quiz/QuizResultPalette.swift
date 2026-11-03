import Foundation

/// Result colours for a graded quiz card.
///
/// Light and dark values are the designer's. The animation demo has no dark
/// fills. `#16A34A` is a border and a check icon in light mode. It is not
/// banner text: on the mint fill it is only about 3.1:1.
public enum QuizResultPalette {
    public static let correctFillLight: UInt32 = 0xECFDF3
    public static let correctFillDark: UInt32 = 0x0B2A1A
    public static let incorrectFillLight: UInt32 = 0xFEF3F2
    public static let incorrectFillDark: UInt32 = 0x3A1212

    /// Border and check icon.
    public static let correctMarkLight: UInt32 = 0x16A34A
    public static let correctMarkDark: UInt32 = 0x4ADE80

    /// Banner text. Dark mode uses the same green as the mark.
    public static let correctTextLight: UInt32 = 0x15803D
    public static let correctTextDark: UInt32 = 0x4ADE80

    /// Border, cross, and banner text.
    public static let incorrectMarkLight: UInt32 = 0xB42318
    public static let incorrectMarkDark: UInt32 = 0xFDA29B

    /// Pashto and English sitting on a result fill.
    public static let fillTextLight: UInt32 = 0x1F2937
    public static let fillTextDark: UInt32 = 0xF1F5F9
    public static let fillPronunciationLight: UInt32 = 0x475569
    public static let fillPronunciationDark: UInt32 = 0xCBD5E1

    /// Page behind a result card. A border is also measured against this.
    public static let pageLight: UInt32 = 0xFAF7F0
    public static let pageDark: UInt32 = 0x0F172A

    /// Ring, dot, and the frame around a selected choice or match card.
    ///
    /// Light `#B97D22` is the colour that clears 3:1. `#E8A33D` is about 2.2:1
    /// on white and about 2:1 on the page, so it is not used for that frame.
    /// Dark `#F2B85B` is for the dark fills and the dark page.
    /// On white that dark gold is about 1.8:1, and the ring is not drawn on white.
    public static let ringLight: UInt32 = 0xB97D22
    public static let ringDark: UInt32 = 0xF2B85B
    public static let white: UInt32 = 0xFFFFFF

    public struct ContrastPair: Sendable, Equatable {
        public let name: String
        public let foreground: UInt32
        public let background: UInt32
        /// 4.5 for text. 3 for a border or an icon.
        public let minimumRatio: Double

        public init(name: String, foreground: UInt32, background: UInt32, minimumRatio: Double) {
            self.name = name
            self.foreground = foreground
            self.background = background
            self.minimumRatio = minimumRatio
        }
    }

    public static let textPairs: [ContrastPair] = [
        ContrastPair(name: "correct banner text, light", foreground: correctTextLight, background: correctFillLight, minimumRatio: 4.5),
        ContrastPair(name: "correct banner text, dark", foreground: correctTextDark, background: correctFillDark, minimumRatio: 4.5),
        ContrastPair(name: "wrong banner text, light", foreground: incorrectMarkLight, background: incorrectFillLight, minimumRatio: 4.5),
        ContrastPair(name: "wrong banner text, dark", foreground: incorrectMarkDark, background: incorrectFillDark, minimumRatio: 4.5),
        ContrastPair(name: "text on correct fill, light", foreground: fillTextLight, background: correctFillLight, minimumRatio: 4.5),
        ContrastPair(name: "text on wrong fill, light", foreground: fillTextLight, background: incorrectFillLight, minimumRatio: 4.5),
        ContrastPair(name: "text on correct fill, dark", foreground: fillTextDark, background: correctFillDark, minimumRatio: 4.5),
        ContrastPair(name: "text on wrong fill, dark", foreground: fillTextDark, background: incorrectFillDark, minimumRatio: 4.5),
        ContrastPair(name: "pronunciation on correct fill, light", foreground: fillPronunciationLight, background: correctFillLight, minimumRatio: 4.5),
        ContrastPair(name: "pronunciation on wrong fill, light", foreground: fillPronunciationLight, background: incorrectFillLight, minimumRatio: 4.5),
        ContrastPair(name: "pronunciation on correct fill, dark", foreground: fillPronunciationDark, background: correctFillDark, minimumRatio: 4.5),
        ContrastPair(name: "pronunciation on wrong fill, dark", foreground: fillPronunciationDark, background: incorrectFillDark, minimumRatio: 4.5),
    ]

    public static let markPairs: [ContrastPair] = [
        ContrastPair(name: "correct border and icon, light", foreground: correctMarkLight, background: correctFillLight, minimumRatio: 3),
        ContrastPair(name: "correct border and icon, dark", foreground: correctMarkDark, background: correctFillDark, minimumRatio: 3),
        ContrastPair(name: "wrong border and icon, light", foreground: incorrectMarkLight, background: incorrectFillLight, minimumRatio: 3),
        ContrastPair(name: "wrong border and icon, dark", foreground: incorrectMarkDark, background: incorrectFillDark, minimumRatio: 3),
        ContrastPair(name: "correct border on the page, light", foreground: correctMarkLight, background: pageLight, minimumRatio: 3),
        ContrastPair(name: "correct border on the page, dark", foreground: correctMarkDark, background: pageDark, minimumRatio: 3),
        ContrastPair(name: "wrong border on the page, light", foreground: incorrectMarkLight, background: pageLight, minimumRatio: 3),
        ContrastPair(name: "wrong border on the page, dark", foreground: incorrectMarkDark, background: pageDark, minimumRatio: 3),
        ContrastPair(name: "ring and dot on white, light", foreground: ringLight, background: white, minimumRatio: 3),
        ContrastPair(name: "ring and dot on correct fill, light", foreground: ringLight, background: correctFillLight, minimumRatio: 3),
        ContrastPair(name: "ring and dot on wrong fill, light", foreground: ringLight, background: incorrectFillLight, minimumRatio: 3),
        ContrastPair(name: "ring and dot on the page, light", foreground: ringLight, background: pageLight, minimumRatio: 3),
        ContrastPair(name: "selected choice frame on the page, light", foreground: ringLight, background: pageLight, minimumRatio: 3),
        ContrastPair(name: "ring and dot on correct fill, dark", foreground: ringDark, background: correctFillDark, minimumRatio: 3),
        ContrastPair(name: "ring and dot on wrong fill, dark", foreground: ringDark, background: incorrectFillDark, minimumRatio: 3),
        ContrastPair(name: "ring and dot on the page, dark", foreground: ringDark, background: pageDark, minimumRatio: 3),
        ContrastPair(name: "selected choice frame on the page, dark", foreground: ringDark, background: pageDark, minimumRatio: 3),
    ]

    /// WCAG relative contrast of two sRGB colours.
    public static func contrastRatio(foreground: UInt32, background: UInt32) -> Double {
        let lighter = max(relativeLuminance(foreground), relativeLuminance(background))
        let darker = min(relativeLuminance(foreground), relativeLuminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let s = Double(value) / 255
            if s <= 0.04045 { return s / 12.92 }
            return pow((s + 0.055) / 1.055, 2.4)
        }
        let red = channel((hex >> 16) & 0xFF)
        let green = channel((hex >> 8) & 0xFF)
        let blue = channel(hex & 0xFF)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
