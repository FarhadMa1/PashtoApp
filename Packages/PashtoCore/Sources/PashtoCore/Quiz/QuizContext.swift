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

    public init(
        bundle: ContentBundle,
        seenLessonIDs: [LessonID],
        retiredItemIDs: [ItemID] = []
    ) {
        self.bundle = bundle
        self.seenLessonIDs = seenLessonIDs
        self.retiredItemIDs = retiredItemIDs
    }
}
