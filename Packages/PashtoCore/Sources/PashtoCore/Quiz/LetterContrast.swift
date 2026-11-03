import Foundation

/// The mark a learner should see after a same-sound question.
public enum LetterMark: String, Hashable, Codable, Sendable {
    /// The small ring on ډ, ټ, and ړ.
    case ring
    /// The dot that separates ذ from ز.
    case dot
}

/// One letter that shares its sound with a different shape.
public struct LetterContrastEntry: Hashable, Sendable {
    public let glyph: String
    /// Exact English helper. Stress is not marked; this is not a pronunciation.
    public let hint: String
    /// Key in the app string catalog. The English value is `hint`.
    public let localizationKey: String
    /// Nil for the plain shape, which has nothing extra to mark.
    public let mark: LetterMark?
    public let partnerGlyph: String
}

/// Shape hints for the eight letters that sound alike.
///
/// `contrastHint` on the item wins when the content generator has written it.
/// These strings are used until then, and they are the strings the catalog
/// translates.
public enum LetterContrasts {
    public static let entries: [LetterContrastEntry] = [
        entry("د", "da, plain, no ring", "quiz.letterHint.da.plain", nil, "ډ"),
        entry("ډ", "da with a ring (tongue curled back)", "quiz.letterHint.da.ring", .ring, "د"),
        entry("ت", "ta, two dots, no ring", "quiz.letterHint.ta.plain", nil, "ټ"),
        entry("ټ", "ta with a ring (tongue curled back)", "quiz.letterHint.ta.ring", .ring, "ت"),
        entry("ر", "ra, plain, no ring", "quiz.letterHint.ra.plain", nil, "ړ"),
        entry("ړ", "ra with a ring (tongue curled back)", "quiz.letterHint.ra.ring", .ring, "ر"),
        entry("ذ", "za, dot on the da shape", "quiz.letterHint.za.dalDot", .dot, "ز"),
        entry("ز", "za, dot on the ra shape", "quiz.letterHint.za.raDot", .dot, "ذ"),
    ]

    public static func entry(matching glyph: String) -> LetterContrastEntry? {
        let key = Normalization.nfc(glyph)
        return entries.first { Normalization.nfc($0.glyph) == key }
    }

    /// The hint a same-sound task shows for this letter.
    public static func hint(for item: ContentItem) -> String? {
        if let written = item.contrastHint, !Text.isBlank(written) {
            return written
        }
        return entry(matching: item.pashto)?.hint
    }

    public static func localizationKey(for hint: String) -> String? {
        entries.first { $0.hint == hint }?.localizationKey
    }

    private static func entry(
        _ glyph: String,
        _ hint: String,
        _ key: String,
        _ mark: LetterMark?,
        _ partner: String
    ) -> LetterContrastEntry {
        LetterContrastEntry(
            glyph: glyph,
            hint: hint,
            localizationKey: key,
            mark: mark,
            partnerGlyph: partner
        )
    }
}
