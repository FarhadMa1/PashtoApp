/// A lesson the home can open, copied from a unit in the release list.
public struct ReleasedLesson: Hashable, Sendable, Identifiable {
    public let id: LessonID
    public let title: String
    public let unitID: UnitID
    public let kind: LessonKind

    public init(id: LessonID, title: String, unitID: UnitID, kind: LessonKind = .practice) {
        self.id = id
        self.title = title
        self.unitID = unitID
        self.kind = kind
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
    /// which is the home's existing empty state. A practice lesson is skipped
    /// when `LessonSessionBuilder` would give it no questions under these
    /// settings, so the home does not offer a quiz that does nothing.
    /// `l-sounds-1` is that case: every item is a `soundExample`, and a sound
    /// example is not introduced. Learn and phrases lessons stay on the list.
    /// Their row title is the unit title.
    public static func lessons(
        in bundle: ContentBundle,
        releasedUnitIDs: [UnitID],
        seenLessonIDs: [LessonID] = [],
        showsPronunciation: Bool = true,
        voiceOver: Bool = false
    ) -> [ReleasedLesson] {
        let course = ReleasedCourse.limiting(bundle, to: releasedUnitIDs)
        let listed = Set(releasedUnitIDs)
        var lessons: [ReleasedLesson] = []
        for unit in course.units where listed.contains(unit.id) {
            for lesson in unit.lessons {
                if lesson.countsForProgress {
                    guard hasQuestions(
                        lesson.id,
                        in: bundle,
                        seenLessonIDs: seenLessonIDs,
                        releasedUnitIDs: releasedUnitIDs,
                        showsPronunciation: showsPronunciation,
                        voiceOver: voiceOver
                    ) else { continue }
                    lessons.append(ReleasedLesson(id: lesson.id, title: lesson.title, unitID: unit.id, kind: lesson.kind))
                } else {
                    let title = unit.title
                    lessons.append(ReleasedLesson(id: lesson.id, title: title, unitID: unit.id, kind: lesson.kind))
                }
            }
        }
        return lessons
    }

    /// Same builder `start` uses. A fresh generator each time, because only
    /// the question count matters here, not the order.
    private static func hasQuestions(
        _ lessonID: LessonID,
        in bundle: ContentBundle,
        seenLessonIDs: [LessonID],
        releasedUnitIDs: [UnitID],
        showsPronunciation: Bool,
        voiceOver: Bool
    ) -> Bool {
        var rng = LessonProbeGenerator()
        let session = LessonSessionBuilder.build(
            for: lessonID,
            in: bundle,
            seenLessonIDs: seenLessonIDs,
            releasedUnitIDs: releasedUnitIDs,
            showsPronunciation: showsPronunciation,
            voiceOver: voiceOver,
            using: &rng
        )
        return !session.tasks.isEmpty
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

    /// Continues a lesson that was already saved.
    ///
    /// The questions and the answers are the ones in `session`. They are not
    /// built again. A session with nothing left to answer does not open.
    public mutating func resume(
        _ session: LessonSession,
        in bundle: ContentBundle,
        releasedUnitIDs: [UnitID]
    ) {
        guard !session.tasks.isEmpty else {
            self.session = nil
            items = []
            return
        }
        let course = ReleasedCourse.limiting(bundle, to: releasedUnitIDs)
        self.session = session
        items = course.items
    }

    /// Replaces the open session after an answer, when it is the same lesson.
    ///
    /// A different lesson is left as it was. Clearing the session is `end`.
    public mutating func replaceSession(_ session: LessonSession) {
        guard let current = self.session, current.lessonID == session.lessonID else { return }
        self.session = session
    }

    /// Finishing or leaving. The session is gone and the home shows again.
    public mutating func end() {
        session = nil
        items = []
    }
}

/// The home's lesson list, kept so it is not rebuilt on every read.
///
/// VoiceOver is part of the key. Turning it on or off changes which tasks a
/// lesson is given, and a lesson with no tasks is left off the home.
public struct ReleasedLessonCache: Sendable {
    public private(set) var lessons: [ReleasedLesson] = []
    private(set) var rebuildCount = 0
    private var key: Key?

    public init() {}

    /// Rebuilds when the course, the release list, progress, pronunciation, or VoiceOver changed.
    public mutating func refresh(
        course: ContentBundle?,
        releasedUnitIDs: [UnitID],
        seenLessonIDs: [LessonID] = [],
        showsPronunciation: Bool = true,
        voiceOver: Bool = false
    ) {
        let next = Key(
            course: course,
            releasedUnitIDs: releasedUnitIDs,
            seenLessonIDs: seenLessonIDs,
            showsPronunciation: showsPronunciation,
            voiceOver: voiceOver
        )
        guard next != key else { return }
        key = next
        rebuildCount += 1
        guard let course else {
            lessons = []
            return
        }
        lessons = RootLessonSession.lessons(
            in: course,
            releasedUnitIDs: releasedUnitIDs,
            seenLessonIDs: seenLessonIDs,
            showsPronunciation: showsPronunciation,
            voiceOver: voiceOver
        )
    }

    private struct Key: Equatable, Sendable {
        var course: ContentBundle?
        var releasedUnitIDs: [UnitID]
        var seenLessonIDs: [LessonID]
        var showsPronunciation: Bool
        var voiceOver: Bool
    }
}

/// Enough for the home to ask whether a lesson has any question.
private struct LessonProbeGenerator: RandomNumberGenerator {
    private var state: UInt64 = 0xA5A5A5A5A5A5A5A5

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
        return mixed ^ (mixed >> 31)
    }
}
