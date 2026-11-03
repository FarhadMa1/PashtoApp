import Foundation

/// The home's lesson list, refreshed when the progress snapshot changes.
///
/// `snapshot` refreshes in `didSet`. The list uses the seen lessons and the
/// transliteration setting on that snapshot. VoiceOver and the course are
/// set on their own, because they are not part of the snapshot. The cache
/// skips a rebuild when none of those inputs changed, so a streak-only update
/// does not rebuild the course.
public struct ReleasedLessonList: Sendable {
    public private(set) var lessons: [ReleasedLesson] = []
    public private(set) var voiceOver = false
    /// Setting this refreshes the list. The same inputs do not rebuild it.
    public var snapshot: ProgressSnapshot? {
        didSet { refresh() }
    }

    private var cache = ReleasedLessonCache()
    private var course: ContentBundle?
    private var releasedUnitIDs: [UnitID] = []

    public init() {}

    /// Times the course was actually rebuilt. A matching snapshot does not add one.
    public var rebuildCount: Int { cache.rebuildCount }

    public mutating func setCourse(_ course: ContentBundle?, releasedUnitIDs: [UnitID]) {
        self.course = course
        self.releasedUnitIDs = releasedUnitIDs
        refresh()
    }

    public mutating func setVoiceOver(_ enabled: Bool) {
        guard enabled != voiceOver else { return }
        voiceOver = enabled
        refresh()
    }

    private mutating func refresh() {
        cache.refresh(
            course: course,
            releasedUnitIDs: releasedUnitIDs,
            seenLessonIDs: snapshot?.lessonProgress.map(\.lessonID) ?? [],
            showsPronunciation: snapshot?.settings.showTransliteration ?? true,
            voiceOver: voiceOver
        )
        lessons = cache.lessons
    }
}
