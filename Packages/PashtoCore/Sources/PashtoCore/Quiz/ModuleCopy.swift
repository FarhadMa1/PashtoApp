/// Approved English for the lesson path and the card screens.
///
/// These words are the ones Farhad approved. The app catalog uses the same spelling.
public enum ModuleCopy {
    public static let learn = "Learn"
    public static let phrases = "Phrases"
    public static let practice = "Practice"
    public static let newWords = "New words"
    public static let next = "Next"
    public static let startPractice = "Start practice"
    public static let skipToPractice = "Skip to practice"

    public static func section(_ kind: LessonKind) -> String {
        switch kind {
        case .learn: learn
        case .phrases: phrases
        case .practice: practice
        }
    }
}

/// Phrase category names that are not approved yet.
///
/// One key per released unit. Every value is nil, and the card screen does not
/// show a category heading. Fill the value in this table when the name is approved.
public enum PendingCopy {
    public static let phraseCategoryGreetings = "pending.phrases.category.u-greetings"
    public static let phraseCategoryIntroductions = "pending.phrases.category.u-introductions"
    public static let phraseCategoryFamily = "pending.phrases.category.u-family"

    public static let phraseCategories: [String: String?] = [
        phraseCategoryGreetings: nil,
        phraseCategoryIntroductions: nil,
        phraseCategoryFamily: nil,
    ]

    public static func phraseCategoryKey(for unitID: UnitID) -> String? {
        switch unitID.rawValue {
        case "u-greetings": phraseCategoryGreetings
        case "u-introductions": phraseCategoryIntroductions
        case "u-family": phraseCategoryFamily
        default: nil
        }
    }

    /// Nil until that unit's category name is approved. Callers show no heading.
    public static func phraseCategoryHeading(for unitID: UnitID) -> String? {
        guard let key = phraseCategoryKey(for: unitID) else { return nil }
        return phraseCategories[key] ?? nil
    }
}
