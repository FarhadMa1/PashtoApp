import Foundation

/// The units a release is allowed to quiz.
///
/// The caller passes the ids from `release-units.json`. This type does not
/// read that file. A unit that is not listed is dropped, and so are items
/// that only that unit referenced, so they cannot become prompts or distractors.
public enum ReleasedCourse {
    public static func limiting(_ bundle: ContentBundle, to releasedUnitIDs: [UnitID]) -> ContentBundle {
        let listed = Set(releasedUnitIDs)
        let units = bundle.units.filter { listed.contains($0.id) }
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
}
