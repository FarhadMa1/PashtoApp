/// Lessons the learner can be quizzed on, and the bundle those lessons come from.
///
/// Put both finished lessons and lessons skipped by the placement test in
/// `seenLessonIDs`. An item is seen only when one of those lessons introduces
/// it, through an `introduce` reference or through `letters`. A `soundExample`
/// does not make an item seen.
///
/// `retiredItemIDs` is supplied by the caller. Retired ids live in the content
/// tool's registry, not on `ContentItem`, and a decoded bundle does not contain
/// them. Passing the ids here keeps those items out of a quiz anyway.
public struct QuizContext: Sendable {
    public let bundle: ContentBundle
    public let seenLessonIDs: [LessonID]
    public let retiredItemIDs: [ItemID]
    /// Units from `release-units.json`, in that file's order.
    ///
    /// From the first unit after Greetings, an item takes wrong answers of the
    /// same Pashto word count. Greetings, and anything before it, keeps one
    /// shared pool. Empty means only the ids in `AnswerPool.shaped` are split
    /// that way. This value does not read the
    /// file. The caller passes the list.
    public let releasedUnitIDs: [UnitID]

    public init(
        bundle: ContentBundle,
        seenLessonIDs: [LessonID],
        retiredItemIDs: [ItemID] = [],
        releasedUnitIDs: [UnitID] = []
    ) {
        self.bundle = bundle
        self.seenLessonIDs = seenLessonIDs
        self.retiredItemIDs = retiredItemIDs
        self.releasedUnitIDs = releasedUnitIDs
    }
}
