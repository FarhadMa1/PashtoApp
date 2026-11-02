/// One lesson the learner finished, or skipped in the placement test.
///
/// Which lessons are unlocked is not stored. The path treats every id here
/// as finished, whether the source is `completed` or `placement`. A lesson
/// added earlier in the course does not remove one that is already here.
public struct LessonProgress: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Hashable, Sendable {
        /// The learner finished the lesson.
        case completed
        /// The placement test skipped the lesson.
        case placement
    }

    public let lessonID: LessonID
    public let source: Source
    /// The civil day the lesson was first finished or skipped.
    public let firstCompletedDay: LocalDay
    /// Best percent correct on the first try, from 0 through 100.
    ///
    /// A later session does not lower this. The store replaces the whole row,
    /// so the caller keeps the higher score.
    public let bestScorePercent: Int

    public init(
        lessonID: LessonID,
        source: Source,
        firstCompletedDay: LocalDay,
        bestScorePercent: Int
    ) {
        self.lessonID = lessonID
        self.source = source
        self.firstCompletedDay = firstCompletedDay
        self.bestScorePercent = bestScorePercent
    }
}
