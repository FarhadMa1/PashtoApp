import Foundation

/// Shape checks for the pronunciation shown in the app.
///
/// Letters, hyphen, space, and punctuation are allowed. A hyphenated word has
/// one all-uppercase syllable. Zero is allowed only when that word is two
/// `tokenPronunciations` joined with `-` (`chi` and `shay` make `chi-shay`).
/// A word without a hyphen is lowercase or entirely uppercase. Entirely
/// uppercase is a stressed one-syllable word (`KHAYR`). Mixed case is an error.
/// An all-uppercase word whose next word starts with `kr` is a review (`ZDA kram`).
///
/// When `requireHyphenWhenMultiSyllable` is set, a transliteration word with more
/// than one syllable (from the active `StressRule`) must be spelled with a hyphen.
/// Letter items leave that flag off: names such as `alif` are labels.
enum PronunciationRules {
    static func issues(
        translit: String,
        pronunciation: String,
        id: String?,
        syllableCount: (String) -> Int,
        requireHyphenWhenMultiSyllable: Bool,
        tokenPronunciations: [String]? = nil
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var reported: Set<Unicode.Scalar> = []
        for scalar in pronunciation.unicodeScalars where !isAllowed(scalar) {
            if reported.insert(scalar).inserted {
                issues.append(error(id, "pronunciation contains \(PashtoScript.code(scalar)), which is outside letters, hyphen, space, and punctuation."))
            }
        }

        let translitWords = words(in: translit)
        let pronunciationWords = words(in: pronunciation)
        if translitWords.count != pronunciationWords.count {
            issues.append(error(
                id,
                "pronunciation has \(pronunciationWords.count) words and translit has \(translitWords.count)."
            ))
        }

        if requireHyphenWhenMultiSyllable {
            let paired = min(translitWords.count, pronunciationWords.count)
            for index in 0..<paired {
                let spoken = pronunciationWords[index]
                let nuclei = syllableCount(translitWords[index])
                if nuclei > 1, !spoken.contains("-") {
                    issues.append(error(
                        id,
                        "\"\(spoken)\" needs a hyphen and one uppercase syllable. The transliteration has \(nuclei) syllables."
                    ))
                }
            }
        }

        for index in pronunciationWords.indices {
            let word = pronunciationWords[index]
            if word.contains("-") {
                issues.append(contentsOf: hyphenatedIssues(word, id: id, tokenPronunciations: tokenPronunciations))
            } else {
                issues.append(contentsOf: plainIssues(
                    word,
                    next: index + 1 < pronunciationWords.count ? pronunciationWords[index + 1] : nil,
                    id: id
                ))
            }
        }
        return issues
    }

    private static func hyphenatedIssues(
        _ word: String,
        id: String?,
        tokenPronunciations: [String]?
    ) -> [ValidationIssue] {
        let syllables = word.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        var uppercase = 0
        var issues: [ValidationIssue] = []
        for syllable in syllables {
            switch caseOf(syllable) {
            case .empty:
                issues.append(error(id, "\"\(word)\" has an empty syllable."))
            case .lower:
                break
            case .upper:
                uppercase += 1
            case .mixed:
                issues.append(error(id, "Syllable \"\(syllable)\" in \"\(word)\" mixes uppercase and lowercase."))
            }
        }
        if uppercase == 0, !joinsTokenPronunciations(spokenSegment(word), tokenPronunciations) {
            issues.append(error(id, "\"\(word)\" has no uppercase syllable."))
        } else if uppercase > 1 {
            issues.append(error(id, "\"\(word)\" has more than one uppercase syllable."))
        }
        return issues
    }

    /// `chi-shay` is `chi` and `shay` joined by the hyphen. Any other unstressed hyphen is an error.
    private static func joinsTokenPronunciations(_ word: String, _ tokens: [String]?) -> Bool {
        guard let tokens, tokens.count >= 2 else { return false }
        for index in 0..<(tokens.count - 1) {
            if tokens[index] + "-" + tokens[index + 1] == word {
                return true
            }
        }
        return false
    }

    /// The spoken piece. A trailing question mark is not part of the token join.
    private static func spokenSegment(_ word: String) -> String {
        var segment = word
        let trailing: Set<Character> = ["?", "!", ".", ",", ":", ";", "؟", "،"]
        while let last = segment.last, trailing.contains(last) {
            segment.removeLast()
        }
        return segment
    }

    private static func plainIssues(_ word: String, next: String?, id: String?) -> [ValidationIssue] {
        switch caseOf(word) {
        case .empty, .lower:
            return []
        case .upper:
            if let next, letterPrefix(next).hasPrefix("kr") {
                return [ValidationIssue(
                    id: id,
                    field: "pronunciation",
                    message: "Uppercase \"\(word)\" before a word starting with \"kr\" needs review.",
                    severity: .review
                )]
            }
            return []
        case .mixed:
            return [error(id, "\"\(word)\" has no hyphen and must be lowercase.")]
        }
    }

    private enum SyllableCase {
        case empty
        case lower
        case upper
        case mixed
    }

    private static func caseOf(_ syllable: String) -> SyllableCase {
        var sawLower = false
        var sawUpper = false
        for scalar in syllable.unicodeScalars {
            if scalar >= "a", scalar <= "z" {
                sawLower = true
            } else if scalar >= "A", scalar <= "Z" {
                sawUpper = true
            }
        }
        if sawUpper, sawLower { return .mixed }
        if sawUpper { return .upper }
        if sawLower { return .lower }
        return .empty
    }

    private static func letterPrefix(_ word: String) -> String {
        let letters = word.unicodeScalars.filter { ($0 >= "a" && $0 <= "z") || ($0 >= "A" && $0 <= "Z") }
        return String(String.UnicodeScalarView(letters)).lowercased(with: nil)
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        if scalar >= "a", scalar <= "z" { return true }
        if scalar >= "A", scalar <= "Z" { return true }
        if scalar == "-" || scalar == " " { return true }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return true
        default:
            return false
        }
    }

    private static func error(_ id: String?, _ message: String) -> ValidationIssue {
        ValidationIssue(id: id, field: "pronunciation", message: message, severity: .error)
    }
}
