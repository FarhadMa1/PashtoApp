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
    /// Learn list. Opens the unit's first practice lesson.
    public static let practiceLesson = "Practice lesson →"
    /// Learn list. Opens the card view for the same lesson.
    public static let flashcards = "Flashcards"
    /// Bookmark is empty. Spoken only.
    public static let save = "Save"
    /// Bookmark is filled. Spoken only.
    public static let saved = "Saved"
    /// Speaker on a row that has a clip. Spoken only.
    public static let play = "Play"

    /// `3 of 7 words`. The noun stays `words` for every count.
    public static func wordsCount(completed: Int, total: Int) -> String {
        "\(completed) of \(total) words"
    }

    public static func section(_ kind: LessonKind) -> String {
        switch kind {
        case .learn: learn
        case .phrases: phrases
        case .practice: practice
        }
    }
}

