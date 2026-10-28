import Foundation

/// Hides `draft` and `check` items for a Debug or dev build.
///
/// A release build must not use this. The release gate reports those items
/// and leaves them in the bundle. Nothing here runs unless a dev build asks.
/// A `responseTo` that points at a hidden item is cleared. A `responseTo`
/// that names an id the bundle never had is left in place so validation
/// can report it.
public enum ContentFilter {
    public static func devBuild(_ bundle: ContentBundle) -> ContentBundle {
        let hidden = Set(bundle.items.filter { $0.verification.status != .verified }.map(\.id))
        let items = bundle.items.compactMap { item -> ContentItem? in
            guard !hidden.contains(item.id) else { return nil }
            return item.clearingResponseToHidden(in: hidden)
        }
        let units = bundle.units.map { unit in
            CourseUnit(
                id: unit.id,
                track: unit.track,
                title: unit.title,
                lessons: unit.lessons.map { filter($0, hiding: hidden) }
            )
        }
        let groups = bundle.nonDistractorGroups.compactMap { group -> [ItemID]? in
            let kept = group.filter { !hidden.contains($0) }
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

    private static func filter(_ lesson: Lesson, hiding hidden: Set<ItemID>) -> Lesson {
        let dialogs = lesson.dialogs.compactMap { dialog -> Dialog? in
            let turns = dialog.turns.filter { !hidden.contains($0.item) }
            guard !turns.isEmpty else { return nil }
            return Dialog(id: dialog.id, turns: turns)
        }
        return Lesson(
            id: lesson.id,
            title: lesson.title,
            items: lesson.items.filter { !hidden.contains($0.item) },
            letters: lesson.letters.filter { !hidden.contains($0) },
            dialogs: dialogs
        )
    }
}

private extension ContentItem {
    func clearingResponseToHidden(in hidden: Set<ItemID>) -> ContentItem {
        guard let responseTo, hidden.contains(responseTo) else { return self }
        return ContentItem(
            id: id,
            kind: kind,
            pashto: pashto,
            translit: translit,
            pronunciation: pronunciation,
            en: en,
            verification: verification,
            enAlt: enAlt,
            usage: usage,
            pronunciationNote: pronunciationNote,
            responseTo: nil,
            tokens: tokens,
            acceptedOrders: acceptedOrders,
            audio: audio,
            name: name,
            forms: forms,
            sound: sound
        )
    }
}
