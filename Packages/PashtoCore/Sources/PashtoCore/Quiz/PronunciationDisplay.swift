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

/// How a pronunciation fits the width it is given.
///
/// One scale covers the whole pronunciation. The widest word sets it, and
/// every word uses that same scale, so a long word shrinks as one line
/// instead of syllable by syllable. A pronunciation whose words already fit
/// stays at 1 and may still wrap at spaces. Hyphens stay inside a word.
/// A non-positive available width means the line has not been measured yet,
/// so the pronunciation stays at full size for that pass.
public enum PronunciationFit {
    public static func scale(idealWidth: Double, availableWidth: Double) -> Double {
        guard idealWidth > 0 else { return 1 }
        guard availableWidth.isFinite, availableWidth > 0 else { return 1 }
        return min(1, availableWidth / idealWidth)
    }

    /// Shared scale for one pronunciation. `tokenWidths` are the unscaled
    /// widths of the whitespace-separated words, not the syllables.
    public static func lineScale(tokenWidths: [Double], availableWidth: Double) -> Double {
        scale(idealWidth: tokenWidths.max() ?? 0, availableWidth: availableWidth)
    }
}

/// The pronunciation note copied onto a learn or phrases card.
///
/// A blank note stays off the card. Every other note is shown, including
/// Numbers, Food, Town, Conversation, Travel, and Time. The stored text is
/// not rewritten. `lines(in:)` and `displayText` are only for drawing: one
/// tip on each line, and each line forced left to right so a Pashto letter
/// at the start does not flip the line.
public enum PronunciationNotes {
    /// U+2066 LEFT-TO-RIGHT ISOLATE. A leading Pashto letter is RTL, and this
    /// keeps the line's base direction left to right.
    public static let leftToRightIsolate = "\u{2066}"
    /// U+2069 POP DIRECTIONAL ISOLATE.
    public static let popDirectionalIsolate = "\u{2069}"

    public static func presented(_ note: String?) -> String? {
        guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// One tip per line. A tip begins at a Pashto letter, or a run of them,
    /// that is immediately followed by ": ". Text inside a tip stays together,
    /// so "a voiced kh, close to French r" is not a خ tip. A note with one
    /// tip is the stored string, with no added break.
    public static func lines(in note: String) -> [String] {
        let starts = tipStarts(in: note)
        if starts.count < 2, starts.first == nil || starts.first == note.startIndex {
            return [note]
        }
        var indices = starts
        if indices.first != note.startIndex {
            indices.insert(note.startIndex, at: 0)
        }
        var pieces: [String] = []
        for (offset, start) in indices.enumerated() {
            let end = offset + 1 < indices.count ? indices[offset + 1] : note.endIndex
            let piece = String(note[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                pieces.append(piece)
            }
        }
        return pieces.isEmpty ? [note] : pieces
    }

    /// What the card draws. Each line is an LTR isolate, and tips are separated
    /// by a newline. The stored note is not this string.
    public static func displayText(_ note: String) -> String {
        lines(in: note).map(displayLine).joined(separator: "\n")
    }

    /// One drawn line, wrapped so its base direction is left to right.
    public static func displayLine(_ line: String) -> String {
        leftToRightIsolate + line + popDirectionalIsolate
    }

    /// What VoiceOver reads. Direction isolates and the newlines added for
    /// display are removed, so a drawn note is spoken as the stored text.
    public static func spoken(_ text: String) -> String {
        var output = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
                 0x2066, 0x2067, 0x2068, 0x2069:
                continue
            case 0x0A, 0x0D:
                output.unicodeScalars.append(" ")
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        return output
    }

    /// Indexes where a tip starts. The scan jumps past each ": " so a letter
    /// inside the marker is not tested again.
    private static func tipStarts(in note: String) -> [String.Index] {
        var starts: [String.Index] = []
        var index = note.startIndex
        while index < note.endIndex {
            if let markerEnd = tipMarkerEnd(in: note, at: index) {
                starts.append(index)
                index = markerEnd
            } else {
                index = note.index(after: index)
            }
        }
        return starts
    }

    /// End of a tip marker at `index`, or nil when this is not the start of a tip.
    /// The marker is a Pashto letter or letter group immediately followed by ": ".
    private static func tipMarkerEnd(in note: String, at index: String.Index) -> String.Index? {
        if index != note.startIndex {
            let previous = note[note.index(before: index)]
            guard previous.isWhitespace else { return nil }
        }
        var cursor = index
        var letters = 0
        while cursor < note.endIndex, isPashtoLetter(note[cursor]) {
            letters += 1
            cursor = note.index(after: cursor)
        }
        guard letters > 0, note[cursor...].hasPrefix(": ") else { return nil }
        return note.index(cursor, offsetBy: 2)
    }

    private static func isPashtoLetter(_ character: Character) -> Bool {
        var sawLetter = false
        for scalar in character.unicodeScalars {
            guard isArabicScript(scalar) else { return false }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
                sawLetter = true
            case .nonspacingMark, .enclosingMark, .spacingMark:
                continue
            default:
                return false
            }
        }
        return sawLetter
    }

    private static func isArabicScript(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
            return true
        default:
            return false
        }
    }
}
