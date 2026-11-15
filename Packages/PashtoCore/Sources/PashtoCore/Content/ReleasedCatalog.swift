import Foundation

/// What a release may show. Categories 34–60 and unverified items stay in the
/// file and are removed here, before the menu or a quiz reads the course.
public enum ReleasedCatalog {
    public static let firstHiddenCategory = 34

    public static func showing(_ bundle: ContentBundle) -> ContentBundle {
        let categories = bundle.categories.filter { $0.number < firstHiddenCategory }
        let visibleNumbers = Set(categories.map(\.number))
        let hiddenItems = Set(bundle.items.compactMap { item -> ItemID? in
            if item.verified == false { return item.id }
            if item.verification.status != .verified { return item.id }
            return nil
        })
        let items = bundle.items.filter { !hiddenItems.contains($0.id) }
        let kept = Set(items.map(\.id))
        let memberships = bundle.memberships.filter { membership in
            visibleNumbers.contains(membership.category) && kept.contains(membership.item)
        }
        let units = bundle.units.map { unit in
            CourseUnit(
                id: unit.id,
                track: unit.track,
                title: unit.title,
                lessons: unit.lessons.map { lesson in
                    Lesson(
                        id: lesson.id,
                        title: lesson.title,
                        items: lesson.items.filter { !hiddenItems.contains($0.item) },
                        letters: lesson.letters.filter { !hiddenItems.contains($0) },
                        dialogs: lesson.dialogs,
                        kind: lesson.kind,
                        categoryNumber: lesson.categoryNumber
                    )
                }
            )
        }
        let groups = bundle.nonDistractorGroups.map { group in
            group.filter { kept.contains($0) }
        }.filter { !$0.isEmpty }
        return ContentBundle(
            contentVersion: bundle.contentVersion,
            variant: bundle.variant,
            romanization: bundle.romanization,
            items: items,
            units: units,
            nonDistractorGroups: groups,
            categories: categories,
            memberships: memberships
        )
    }
}
