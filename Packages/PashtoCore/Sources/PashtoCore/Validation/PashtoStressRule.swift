import Foundation

/// Pashto stress in scholarly transliteration.
///
/// A hyphenated word is one word. Syllables are vowel nuclei (`a`, `ā`, `ə`, `e`, `i`, `o`, `u`).
/// `y` and `w` next to a vowel are consonants, so `ay`, `əy`, and `aw` are one nucleus.
/// Punctuation is ignored. Hyphens stay.
///
/// A word with more than one nucleus needs exactly one stress mark (U+0301).
/// One nucleus does not need a mark. Two marks are an error.
///
/// The perfective check is only a review. It fires when a word is not in
/// `unstressedWords` and the next word starts with `kṛ` (`k` + U+1E5B, or `k` + `r` + U+0323).
public struct PashtoStressRule: StressRule, Sendable {
    public init() {}

    public func issues(in translit: String, unstressedWords: [String], id: String?) -> [ValidationIssue] {
        let words = Self.words(in: translit)
        let exceptions = Set(unstressedWords.map(Normalization.transliterationKey))
        var issues: [ValidationIssue] = []
        for word in words {
            let count = Self.counts(in: word)
            if count.nuclei > 1, count.accents == 0 {
                issues.append(Self.error(
                    id,
                    "\"\(word)\" has \(count.nuclei) syllables and no stress mark."
                ))
            }
            if count.accents > 1 {
                issues.append(Self.error(
                    id,
                    "\"\(word)\" has \(count.accents) stress marks. A word can have one."
                ))
            }
        }
        if words.count >= 2 {
            for index in 0..<(words.count - 1) {
                let first = words[index]
                let second = words[index + 1]
                guard Self.startsWithPerfective(second) else { continue }
                guard !exceptions.contains(Normalization.transliterationKey(first)) else { continue }
                issues.append(ValidationIssue(
                    id: id,
                    field: "translit",
                    message: "\"\(first) \(second)\" may be a perfective verb. The word after \"\(first)\" starts with kṛ, and \"\(first)\" is not in unstressedWords.",
                    severity: .review
                ))
            }
        }
        return issues
    }

    public func syllableCount(in word: String) -> Int {
        Self.counts(in: word).nuclei
    }

    /// Each `unstressedWords` entry is one syllable and uses only characters that appear in the table transliterations.
    public func unstressedListIssues(
        _ words: [String],
        tableTransliterations: [String]
    ) -> [ValidationIssue] {
        let allowed = Set(tableTransliterations.flatMap { Normalization.unicodeScalars(Normalization.nfc($0)) })
        var issues: [ValidationIssue] = []
        for word in words {
            if Text.isBlank(word) {
                issues.append(Self.listError("unstressedWords contains an empty entry."))
                continue
            }
            let nuclei = Self.counts(in: word).nuclei
            if nuclei != 1 {
                issues.append(Self.listError("\"\(word)\" in unstressedWords has \(nuclei) syllables. Each entry must be one syllable."))
            }
            var unknown: [Unicode.Scalar] = []
            var seenUnknown: Set<Unicode.Scalar> = []
            for scalar in Normalization.unicodeScalars(Normalization.nfc(word)) where !allowed.contains(scalar) {
                if seenUnknown.insert(scalar).inserted {
                    unknown.append(scalar)
                }
            }
            if !unknown.isEmpty {
                let listed = unknown.map(PashtoScript.code).joined(separator: ", ")
                issues.append(Self.listError("\"\(word)\" in unstressedWords uses \(listed), not in romanization.table."))
            }
        }
        return issues
    }

    static func words(in translit: String) -> [String] {
        strippingPunctuation(translit)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func counts(in word: String) -> (nuclei: Int, accents: Int) {
        var nuclei = 0
        var accents = 0
        for scalar in word.decomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar == Normalization.stressScalar {
                accents += 1
            } else if vowelScalars.contains(scalar) {
                nuclei += 1
            }
        }
        return (nuclei, accents)
    }

    private static func startsWithPerfective(_ word: String) -> Bool {
        let scalars = Array(word.lowercased(with: nil).decomposedStringWithCanonicalMapping.unicodeScalars)
        guard scalars.count >= 3 else { return false }
        return scalars[0] == "k" && scalars[1] == "r" && scalars[2] == "\u{0323}"
    }

    private static func strippingPunctuation(_ text: String) -> String {
        var kept: [Unicode.Scalar] = []
        for scalar in text.unicodeScalars {
            let category = scalar.properties.generalCategory
            if category != .dashPunctuation, isPunctuation(category) {
                continue
            }
            kept.append(scalar)
        }
        return String(String.UnicodeScalarView(kept))
    }

    private static func isPunctuation(_ category: Unicode.GeneralCategory) -> Bool {
        switch category {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return true
        default:
            return false
        }
    }

    private static func error(_ id: String?, _ message: String) -> ValidationIssue {
        ValidationIssue(id: id, field: "translit", message: message, severity: .error)
    }

    private static func listError(_ message: String) -> ValidationIssue {
        ValidationIssue(id: nil, field: "unstressedWords", message: message, severity: .error)
    }

    /// Vowel letters. `ā` counts as `a` because macron is a separate scalar after NFD.
    static let vowelScalars: Set<Unicode.Scalar> = ["a", "e", "i", "o", "u", "\u{0259}"]
}
