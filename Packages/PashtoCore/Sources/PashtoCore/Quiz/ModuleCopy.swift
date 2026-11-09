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

