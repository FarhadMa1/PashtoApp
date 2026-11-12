import Foundation

/// One piece of a pronunciation as variant B draws it.
///
/// `text` is lowercase. A syllable separator is U+2011 so the line can break
/// at spaces only. `stressed` is true when that syllable is fully uppercase
/// in the stored field and contains an ASCII A–Z letter.
public struct PronunciationRun: Equatable, Sendable {
    public var text: String
    public var stressed: Bool

    public init(text: String, stressed: Bool) {
        self.text = text
        self.stressed = stressed
    }

    /// 700 on a stressed syllable, 400 on everything else.
    /// Bold Text uses 800 and 600 so the stress stays heavier than the rest.
    public func weight(boldText: Bool) -> Int {
        if boldText {
            return stressed
                ? PronunciationDisplay.boldTextStressedWeight
                : PronunciationDisplay.boldTextUnstressedWeight
        }
        return stressed ? PronunciationDisplay.stressedWeight : PronunciationDisplay.unstressedWeight
    }

    /// Bold Text underlines the stressed syllable only.
    public func underlined(boldText: Bool) -> Bool {
        boldText && stressed
    }
}

/// One whitespace-separated word. Hyphens stay inside the token.
public struct PronunciationToken: Equatable, Sendable {
    public var runs: [PronunciationRun]

    public init(runs: [PronunciationRun]) {
        self.runs = runs
    }
}

/// Display variant B for a stored `pronunciation`.
///
/// The stored field is unchanged, capitals included. A syllable is stressed
/// when it contains an ASCII A–Z letter and is equal to its uppercase form.
/// Letters are drawn lowercase. Spaces and hyphens stay. Punctuation stays
/// with its syllable and is lowercased only when it is a letter.
public enum PronunciationDisplay {
    public static let nonBreakingHyphen: Character = "\u{2011}"
    public static let unstressedWeight = 400
    public static let stressedWeight = 700
    public static let boldTextUnstressedWeight = 600
    public static let boldTextStressedWeight = 800
    /// Bold Text underline. Points, not pixels.
    public static let boldTextUnderlineThickness: Double = 2
    /// Distance from the baseline to the top of that underline.
    public static let boldTextUnderlineOffset: Double = 4

    /// What VoiceOver reads. The stored pronunciation, including capitals and ASCII hyphens.
    public static func spoken(_ stored: String) -> String {
        stored
    }

    public static func isStressedSyllable(_ syllable: String) -> Bool {
        let hasASCIIUppercase = syllable.unicodeScalars.contains { (65...90).contains($0.value) }
        return hasASCIIUppercase && syllable == syllable.uppercased()
    }

    public static func runs(in stored: String) -> [PronunciationRun] {
        var result: [PronunciationRun] = []
        for part in partsKeepingWhitespace(stored) {
            if part.allSatisfy(\.isWhitespace) {
                result.append(PronunciationRun(text: part, stressed: false))
                continue
            }
            let syllables = part.split(separator: "-", omittingEmptySubsequences: false)
            for (index, syllable) in syllables.enumerated() {
                if index > 0 {
                    result.append(PronunciationRun(text: String(nonBreakingHyphen), stressed: false))
                }
                let raw = String(syllable)
                result.append(PronunciationRun(
                    text: raw.lowercased(),
                    stressed: isStressedSyllable(raw)
                ))
            }
        }
        return result
    }

    /// Lowercase display string. Syllable hyphens are U+2011.
    public static func displayText(stored: String) -> String {
        runs(in: stored).map(\.text).joined()
    }

    /// Words split on whitespace. A hyphenated word is one token.
    public static func tokens(in stored: String) -> [PronunciationToken] {
        var tokens: [PronunciationToken] = []
        var current: [PronunciationRun] = []
        for run in runs(in: stored) {
            if run.text.allSatisfy(\.isWhitespace) {
                if !current.isEmpty {
                    tokens.append(PronunciationToken(runs: current))
                    current = []
                }
                continue
            }
            current.append(run)
        }
        if !current.isEmpty {
            tokens.append(PronunciationToken(runs: current))
        }
        return tokens
    }

    private static func partsKeepingWhitespace(_ stored: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var spaces: Bool?
        for character in stored {
            let space = character.isWhitespace
            if spaces == nil || spaces == space {
                current.append(character)
                spaces = space
            } else {
                parts.append(current)
                current = String(character)
                spaces = space
            }
        }
        if !current.isEmpty {
            parts.append(current)
        }
        return parts
    }
}

/// Which pronunciation notes reach the screen and VoiceOver.
///
/// Numbers, Food, Town, and Conversation hide every note. A note that mentions
/// capitals is hidden as well, because stress is no longer shown as capitals.
/// The stored note is not rewritten.
public enum PronunciationNotes {
    public static let unitsThatHideEveryNote: Set<String> = [
        "u-numbers", "u-food", "u-town", "u-conversation",
    ]

    public static func mentionsCapitals(_ note: String) -> Bool {
        note.range(of: "capitals", options: [.caseInsensitive]) != nil
    }

    /// The note to show, or nil when this unit or this wording stays off the screen.
    public static func presented(_ note: String?, in unitID: UnitID) -> String? {
        guard !unitsThatHideEveryNote.contains(unitID.rawValue) else { return nil }
        guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard !mentionsCapitals(trimmed) else { return nil }
        return trimmed
    }
}
