/// The course a learner can practice.
///
/// Source files keep every sound example and every letter. Units 1–3 do not
/// introduce those letters, so letter tasks, letter cards, and letter
/// distractors are not built from them. `u-sounds` stays in the files and is
/// omitted from the release list. Unreleased units 4–8 are left as they are.
public enum PlayableCourse {
    /// Greetings, introductions, and family. Their `letters` arrays stay in
    /// the source and are not part of the playable course.
    public static let scriptHiddenUnitIDs: Set<String> = [
        "u-greetings",
        "u-introductions",
        "u-family",
    ]

    /// Kinds the playable quiz does not ask.
    ///
    /// Letter tasks need the hidden letters. Choosing a pronunciation would
    /// show the answer once that pronunciation is always on screen.
    public static let retiredQuizKinds: Set<TaskKind> = [
        .findLetter,
        .letterContrast,
        .firstLetter,
        .transliterationChoice,
    ]

    /// A copy whose units 1–3 introduce no letters.
    ///
    /// Letter items that nothing else references are left out, so they cannot
    /// be prompts, distractors, or new cards. Sound-example items stay when a
    /// lesson still references them. Calling this again changes nothing.
    public static func hidingScript(_ bundle: ContentBundle) -> ContentBundle {
        let units = bundle.units.map(hidingLetters(in:))
        var referenced = Set<ItemID>()
        for unit in units {
            for lesson in unit.lessons {
                for reference in lesson.items {
                    referenced.insert(reference.item)
                }
                for letter in lesson.letters {
                    referenced.insert(letter)
                }
                for dialog in lesson.dialogs {
                    for turn in dialog.turns {
                        referenced.insert(turn.item)
                    }
                }
            }
        }
        let items = bundle.items.filter { referenced.contains($0.id) }
        let groups = bundle.nonDistractorGroups.compactMap { group -> [ItemID]? in
            let kept = group.filter { referenced.contains($0) }
            return kept.count >= 2 ? kept : nil
        }
        return ContentBundle(
            contentVersion: bundle.contentVersion,
            variant: bundle.variant,
            romanization: bundle.romanization,
            items: items,
            units: units,
            nonDistractorGroups: groups
        )
    }

    /// False for units 1–3. Their letters are not new cards.
    public static func countsLettersAsCards(_ unitID: UnitID) -> Bool {
        !scriptHiddenUnitIDs.contains(unitID.rawValue)
    }

    private static func hidingLetters(in unit: CourseUnit) -> CourseUnit {
        guard scriptHiddenUnitIDs.contains(unit.id.rawValue) else { return unit }
        let lessons = unit.lessons.map { lesson in
            Lesson(
                id: lesson.id,
                title: lesson.title,
                items: lesson.items,
                letters: [],
                dialogs: lesson.dialogs
            )
        }
        return CourseUnit(id: unit.id, track: unit.track, title: unit.title, lessons: lessons)
    }
}
