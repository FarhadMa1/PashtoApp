import Foundation

/// Text folding for comparison and search.
///
/// NFC checks compare `unicodeScalars`. Swift treats canonically equivalent
/// strings as equal, so `==` cannot tell NFC from NFD.
///
/// Vowel counts and stress checks belong with validation. They must use
/// `unicodeScalars` and `stressScalar`, not `String` equality.
public enum Normalization {
    /// Combining acute accent. The only mark removed from transliteration keys.
    public static let stressScalar: Unicode.Scalar = "\u{0301}"

    public static func unicodeScalars(_ text: String) -> [Unicode.Scalar] {
        Array(text.unicodeScalars)
    }

    public static func nfc(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
    }

    /// True when `text` is already in NFC, compared on Unicode scalars.
    public static func isNFC(_ text: String) -> Bool {
        unicodeScalars(text).elementsEqual(unicodeScalars(nfc(text)))
    }

    /// NFC, then locale-independent lowercase. Does not strip diacritics.
    ///
    /// Use this for English and `usage`. Pashto duplicate checks use `nfc` on `pashto`.
    public static func comparisonKey(_ text: String) -> String {
        nfc(text).lowercased(with: nil)
    }

    /// NFD, drop only U+0301, NFC, then locale-independent lowercase.
    ///
    /// Precomposed vowels such as `á` lose their accent. `ǧ`, `ṭ`, `x̌`, macrons, and carons stay.
    public static func transliterationKey(_ text: String) -> String {
        let decomposed = text.decomposedStringWithCanonicalMapping
        let stripped = String(decomposed.unicodeScalars.filter { $0 != stressScalar })
        return nfc(stripped).lowercased(with: nil)
    }
}
