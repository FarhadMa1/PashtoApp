/// How serious a validation finding is.
///
/// `review` is for a person to confirm. It does not fail the bundle by itself.
public enum ValidationSeverity: String, Hashable, Sendable {
    case error
    case warning
    case review
}

/// One problem found while checking a bundle.
///
/// `id` is the item, lesson, unit, or dialog the message is about.
/// It is nil for a bundle-level field such as `variant`.
public struct ValidationIssue: Hashable, Sendable {
    public let id: String?
    public let field: String
    public let message: String
    public let severity: ValidationSeverity

    public init(id: String?, field: String, message: String, severity: ValidationSeverity) {
        self.id = id
        self.field = field
        self.message = message
        self.severity = severity
    }
}

/// Which bundle checks to run.
///
/// Release-unit membership and lesson size are not part of either mode.
/// The content tool owns those gates. Both modes run the same bundle checks
/// until that tool exists, so the call shape can stay `validate(_:mode:)`.
public enum ValidationMode: String, Hashable, Sendable {
    case authoring
    case release
}

/// Stress check used by `ContentValidator`. Replace it by passing another rule to `validate`.
///
/// Syllable counts and the `unstressedWords` list use this same rule, so a replacement
/// owns those checks instead of `PashtoStressRule`.
public protocol StressRule: Sendable {
    func issues(in translit: String, unstressedWords: [String], id: String?) -> [ValidationIssue]
    /// Vowel nuclei in one transliteration word. Hyphens stay inside the word.
    func syllableCount(in word: String) -> Int
    func unstressedListIssues(_ words: [String], tableTransliterations: [String]) -> [ValidationIssue]
}
