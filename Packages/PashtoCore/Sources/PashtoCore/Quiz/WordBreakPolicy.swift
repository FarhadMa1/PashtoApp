import Foundation

/// Keeps an English or Pashto line from breaking inside a word.
///
/// A word joiner is inserted between the characters of each word, including
/// across a hyphen. Spaces stay ordinary break points. The stored string is
/// not changed. Callers pass the result to the text view and keep the
/// original string for VoiceOver.
public enum WordBreakPolicy {
    public static let wordJoiner: Character = "\u{2060}"

    public static func display(_ text: String) -> String {
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
