import Foundation

/// Keeps a Latin line from breaking inside a word.
///
/// English and pronunciation get a word joiner between the characters of
/// each word, including across a hyphen. Spaces stay ordinary break points.
/// Pashto, and any other Arabic-script text, is returned unchanged: a joiner
/// between those letters splits the shapes and can reverse their order.
/// The stored string is not changed. Callers pass the result to the text
/// view and keep the original string for VoiceOver.
public enum WordBreakPolicy {
    public static let wordJoiner: Character = "\u{2060}"

    public static func display(_ text: String) -> String {
        if QuizPresentation.containsArabicScript(text) {
            return text
        }
        var result = ""
        var previousWasSpace = true
        for character in text {
            if character.isWhitespace {
                result.append(character)
                previousWasSpace = true
            } else {
                if !previousWasSpace {
                    result.append(wordJoiner)
                }
                result.append(character)
                previousWasSpace = false
            }
        }
        return result
    }

    public static func strippingJoiners(_ text: String) -> String {
        String(text.filter { $0 != wordJoiner })
    }
}
