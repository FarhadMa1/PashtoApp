/// A lesson the home can open, copied from a unit in the release list.
public struct ReleasedLesson: Hashable, Sendable, Identifiable {
    public let id: LessonID
    public let title: String
    public let unitID: UnitID

    public init(id: LessonID, title: String, unitID: UnitID) {
        self.id = id
        self.title = title
        self.unitID = unitID
    }
}

/// The lesson quiz `RootView` starts from the home, and ends when the learner finishes or leaves.
///
/// `start` always passes the release list into `LessonSessionBuilder`. Nil is
/// not an option here: nil would quiz the whole bundle, including units that
/// are not in `release-units.json`. An empty list releases nothing, so a
/// missing list cannot open a lesson. `end` drops the session. The home is
/// what is left.
public struct RootLessonSession: Equatable, Sendable {
    public private(set) var session: LessonSession?
    /// Items from the released units. The quiz looks prompts up in this list.
    public private(set) var items: [ContentItem]

    public init() {
        session = nil
        items = []
    }

    /// True while a started lesson still has questions to show.
    public var isActive: Bool {
        guard let session else { return false }
        return !session.tasks.isEmpty
    }

    /// Lessons in released units, in course order.
    ///
    /// A unit that is not listed is skipped. An empty list returns nothing,
    /// which is the home's existing empty state.
    public static func lessons(in bundle: ContentBundle, releasedUnitIDs: [UnitID]) -> [ReleasedLesson] {
        let course = ReleasedCourse.limiting(bundle, to: releasedUnitIDs)
        let listed = Set(releasedUnitIDs)
        var lessons: [ReleasedLesson] = []
        for unit in course.units where listed.contains(unit.id) {
            for lesson in unit.lessons {
                lessons.append(ReleasedLesson(id: lesson.id, title: lesson.title, unitID: unit.id))
            }
        }
        return lessons
    }

    /// Builds the session for one tap. An unreleased lesson, or an empty release list, does not start one.
    @discardableResult
    public mutating func start(
        lessonID: LessonID,
        in bundle: ContentBundle,
        seenLessonIDs: [LessonID] = [],
        releasedUnitIDs: [UnitID],
        showsPronunciation: Bool = true,
        voiceOver: Bool = false,
        using rng: inout some RandomNumberGenerator
    ) -> LessonSession {
        let course = ReleasedCourse.limiting(bundle, to: releasedUnitIDs)
        let session = LessonSessionBuilder.build(
            for: lessonID,
            in: bundle,
            seenLessonIDs: seenLessonIDs,
            releasedUnitIDs: releasedUnitIDs,
            showsPronunciation: showsPronunciation,
            voiceOver: voiceOver,
            using: &rng
        )
        guard !session.tasks.isEmpty else {
            self.session = nil
            items = []
            return session
        }
        self.session = session
        items = course.items
        return session
    }

    /// Finishing or leaving. The session is gone and the home shows again.
    public mutating func end() {
        session = nil
        items = []
    }
}
