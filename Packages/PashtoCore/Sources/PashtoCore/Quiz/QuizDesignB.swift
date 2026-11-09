import Foundation

/// Question titles approved with Design B.
///
/// These three lines are the only new quiz words. Dialog and letter questions
/// keep the prompt they already have, so they do not gain a title.
/// The strings are not catalog keys. `Localizable.xcstrings` stays as it was.
public enum QuizPromptTitle {
    public static let chooseTheMeaning = "Choose the meaning"
    public static let putTheWordsInOrder = "Put the words in order"
    public static let matchThePairs = "Match the pairs"

    public static func title(for kind: TaskKind) -> String? {
        switch kind {
        case .meaningPashtoToEnglish, .meaningEnglishToPashto:
            chooseTheMeaning
        case .orderWords:
            putTheWordsInOrder
        case .matchPairs:
            matchThePairs
        case .transliterationChoice, .findLetter, .letterContrast, .firstLetter, .dialogResponse:
            nil
        }
    }
}

/// Design B colours for the quiz screen.
///
/// Pronunciation and Pashto use the checked pairs. Saffron `#E8A33D` and the
/// bar gold `#F2B85B` are accents. `#16A34A` stays a light-mode mark, not text.
/// Result fills stay in `QuizResultPalette`.
public enum QuizDesignPalette {
    public static let pronunciationLight: UInt32 = 0x1E3A8A
    public static let pronunciationDark: UInt32 = 0x93B4F5
    public static let pashtoLight: UInt32 = 0x475569
    public static let pashtoDark: UInt32 = 0xCBD5E1
    public static let inkLight: UInt32 = 0x111827
    public static let inkDark: UInt32 = 0xF1F5F9
    public static let pageLight: UInt32 = 0xFAF7F0
    public static let pageDark: UInt32 = 0x0F172A
    public static let surfaceLight: UInt32 = 0xFFFFFF
    public static let surfaceDark: UInt32 = 0x1E293B
    public static let tintLight: UInt32 = 0xEBEFF9
    public static let tintDark: UInt32 = 0x1E293B
    public static let badgeLight: UInt32 = 0x1E3A8A
    public static let badgeDark: UInt32 = 0x4666D2
    public static let cream: UInt32 = 0xFAF7F0
    /// Progress fill. Not a text colour.
    public static let barFill: UInt32 = 0xF2B85B
    public static let barTrack: UInt32 = 0x1E3A8A
    /// Light Continue lip. The face is the badge.
    public static let buttonLipLight: UInt32 = 0x152B6B
    /// Streak mark only. On cream this is about 2:1, so it is not text.
    public static let saffronAccent: UInt32 = 0xE8A33D

    public static let textPairs: [QuizResultPalette.ContrastPair] = [
        QuizResultPalette.ContrastPair(name: "pronunciation on the page, light", foreground: pronunciationLight, background: pageLight, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "pronunciation on a card, light", foreground: pronunciationLight, background: surfaceLight, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "pronunciation on the tray, light", foreground: pronunciationLight, background: tintLight, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "Pashto on the page, light", foreground: pashtoLight, background: pageLight, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "Pashto on a card, light", foreground: pashtoLight, background: surfaceLight, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "Pashto on the tray, light", foreground: pashtoLight, background: tintLight, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "ink on the page, light", foreground: inkLight, background: pageLight, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "ink on a card, light", foreground: inkLight, background: surfaceLight, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "pronunciation on the page, dark", foreground: pronunciationDark, background: pageDark, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "pronunciation on a card, dark", foreground: pronunciationDark, background: surfaceDark, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "pronunciation on the tray, dark", foreground: pronunciationDark, background: tintDark, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "Pashto on the page, dark", foreground: pashtoDark, background: pageDark, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "Pashto on a card, dark", foreground: pashtoDark, background: surfaceDark, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "Pashto on the tray, dark", foreground: pashtoDark, background: tintDark, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "ink on the page, dark", foreground: inkDark, background: pageDark, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "ink on a card, dark", foreground: inkDark, background: surfaceDark, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "cream on the header, light", foreground: cream, background: badgeLight, minimumRatio: 4.5),
        QuizResultPalette.ContrastPair(name: "cream on the header, dark", foreground: cream, background: badgeDark, minimumRatio: 4.5),
    ]

    public static let markPairs: [QuizResultPalette.ContrastPair] = [
        QuizResultPalette.ContrastPair(name: "progress fill on the track", foreground: barFill, background: barTrack, minimumRatio: 3),
        QuizResultPalette.ContrastPair(name: "answer edge on a card, light", foreground: pronunciationLight, background: surfaceLight, minimumRatio: 3),
        QuizResultPalette.ContrastPair(name: "answer edge on a card, dark", foreground: pronunciationDark, background: surfaceDark, minimumRatio: 3),
        QuizResultPalette.ContrastPair(name: "muted edge on a card, light", foreground: QuizResultPalette.muted, background: surfaceLight, minimumRatio: 3),
        QuizResultPalette.ContrastPair(name: "muted edge on a card, dark", foreground: QuizResultPalette.muted, background: surfaceDark, minimumRatio: 3),
        QuizResultPalette.ContrastPair(name: "selected edge on a card, light", foreground: QuizResultPalette.ringLight, background: surfaceLight, minimumRatio: 3),
        QuizResultPalette.ContrastPair(name: "selected edge on a card, dark", foreground: QuizResultPalette.ringDark, background: surfaceDark, minimumRatio: 3),
    ]
}
