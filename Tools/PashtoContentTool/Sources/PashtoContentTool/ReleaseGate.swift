import Foundation
import PashtoCore

/// Release checks that sit on top of `ContentValidator`.
///
/// The gate reports problems. It does not remove items. Lesson size counts
/// items that create cards. `soundExample` refs do not count. Lesson size and
/// unverified items are errors in `release` and warnings in `dev`. A difficult
/// character with no `soundExample` in the first unit is a warning in `dev`.
/// It is an error in `release` only when `u-sounds` is listed in
/// `release-units.json`. A non-empty release list that omits `u-sounds` is an
/// error. An empty list is allowed. A missing romanization table is a warning
/// in `dev` and an error in `release`. Audio in v1.0 is a warning in both modes.
public enum ReleaseGate {
    public static func issues(
        in bundle: ContentBundle,
        releaseUnitIDs: [String],
        itemUnits: [String: String],
        specialSounds: [SpecialSound],
        mode: ToolMode
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let releaseSeverity: ValidationSeverity = mode == .release ? .error : .warning
        let knownUnits = Set(bundle.units.map(\.id.rawValue))
        var seenRelease: Set<String> = []
        for unitID in releaseUnitIDs {
            if !seenRelease.insert(unitID).inserted {
                issues.append(IssueText.make(.error, id: unitID, field: "release-units.json", "\(unitID) is listed more than once."))
                continue
            }
            if !knownUnits.contains(unitID) {
                issues.append(IssueText.make(
                    .error,
                    id: unitID,
                    field: "release-units.json",
                    "\(unitID) is in release-units.json and is not a unit."
                ))
            }
        }

        let releaseUnits = Set(releaseUnitIDs)
        if mode == .release, !releaseUnits.isEmpty, !releaseUnits.contains(Self.soundsUnitID) {
            issues.append(IssueText.make(
                .error,
                id: Self.soundsUnitID,
                field: "release-units.json",
                "release-units.json lists units and does not include \(Self.soundsUnitID)."
            ))
        }
        if bundle.romanization.table.isEmpty {
            issues.append(IssueText.make(
                releaseSeverity,
                id: nil,
                field: "romanization.table",
                "romanization.table is missing. Pashto Expert has not supplied it."
            ))
        }
        var reportedItems: Set<String> = []
        for unit in bundle.units where releaseUnits.contains(unit.id.rawValue) {
            for itemID in itemIDs(in: unit) {
                guard reportedItems.insert(itemID).inserted else { continue }
                guard let item = bundle.items.first(where: { $0.id.rawValue == itemID }) else { continue }
                if item.verification.status != .verified {
                    issues.append(IssueText.make(
                        releaseSeverity,
                        id: itemID,
                        field: "verification.status",
                        "\(itemID) in \(unit.id.rawValue) is \(item.verification.status.rawValue). Every item in a release unit must be verified."
                    ))
                }
            }
        }
        for (itemID, unitID) in itemUnits.sorted(by: { $0.key < $1.key }) where releaseUnits.contains(unitID) {
            guard reportedItems.insert(itemID).inserted else { continue }
            guard let item = bundle.items.first(where: { $0.id.rawValue == itemID }) else { continue }
            if item.verification.status != .verified {
                issues.append(IssueText.make(
                    releaseSeverity,
                    id: itemID,
                    field: "verification.status",
                    "\(itemID) in \(unitID) is \(item.verification.status.rawValue). Every item in a release unit must be verified."
                ))
            }
        }

        for unit in bundle.units {
            for lesson in unit.lessons {
                // Lessons in the sounds unit are exempt from the size rule.
                // Instead, every lesson in u-sounds must contain at least one soundExample.
                if unit.id.rawValue == Self.soundsUnitID {
                    let hasSoundExample = lesson.items.contains { $0.role == .soundExample }
                    if !hasSoundExample {
                        issues.append(IssueText.make(
                            .error,
                            id: lesson.id.rawValue,
                            field: "items",
                            "\(lesson.id.rawValue) in \(Self.soundsUnitID) must contain at least one soundExample."
                        ))
                    }
                } else {
                    let count = cardCount(in: lesson)
                    if count < 4 {
                        issues.append(IssueText.make(
                            releaseSeverity,
                            id: lesson.id.rawValue,
                            field: "items",
                            "\(lesson.id.rawValue) has \(count) items. A lesson needs at least 4."
                        ))
                    } else if count < 6 {
                        issues.append(IssueText.make(
                            .warning,
                            id: lesson.id.rawValue,
                            field: "items",
                            "\(lesson.id.rawValue) has \(count) items. The target is 6 to 8."
                        ))
                    }
                }
            }
        }

        for item in bundle.items where item.hasAudio {
            issues.append(IssueText.make(
                .warning,
                id: item.id.rawValue,
                field: "audio",
                "\(item.id.rawValue) has audio. v1.0 does not ship audio."
            ))
        }

        // Dev always warns, so a missing example stays visible.
        // Release runs the check when u-sounds is on the list.
        if mode == .dev {
            issues.append(contentsOf: soundExampleIssues(in: bundle, specialSounds: specialSounds, severity: .warning))
        } else if releaseUnits.contains(Self.soundsUnitID) {
            issues.append(contentsOf: soundExampleIssues(in: bundle, specialSounds: specialSounds, severity: .error))
        }
        return issues
    }

    private static let soundsUnitID = "u-sounds"

    /// Items that create cards: `introduce` refs and letters. A `soundExample` does not.
    private static func cardCount(in lesson: Lesson) -> Int {
        lesson.items.filter { $0.role == .introduce }.count + lesson.letters.count
    }

    private static func itemIDs(in unit: CourseUnit) -> [String] {
        var ids: [String] = []
        var seen: Set<String> = []
        for lesson in unit.lessons {
            for ref in lesson.items where seen.insert(ref.item.rawValue).inserted {
                ids.append(ref.item.rawValue)
            }
            for letter in lesson.letters where seen.insert(letter.rawValue).inserted {
                ids.append(letter.rawValue)
            }
            for dialog in lesson.dialogs {
                for turn in dialog.turns where seen.insert(turn.item.rawValue).inserted {
                    ids.append(turn.item.rawValue)
                }
            }
        }
        return ids
    }

    private static func soundExampleIssues(
        in bundle: ContentBundle,
        specialSounds: [SpecialSound],
        severity: ValidationSeverity
    ) -> [ValidationIssue] {
        guard let unit = bundle.units.first else {
            if specialSounds.isEmpty { return [] }
            return [IssueText.make(.error, id: nil, field: "soundExample", "The course has no units, so special sounds have no soundExample.")]
        }
        var sounds: Set<String> = []
        for lesson in unit.lessons {
            for ref in lesson.items where ref.role == .soundExample {
                if let sound = ref.sound, !IssueText.isBlank(sound) {
                    sounds.insert(Normalization.nfc(sound))
                }
            }
        }
        var issues: [ValidationIssue] = []
        var seen: Set<String> = []
        for special in specialSounds {
            let key = Normalization.nfc(special.character)
            guard seen.insert(key).inserted else { continue }
            let translit = Normalization.nfc(special.translit)
            if sounds.contains(key) || sounds.contains(translit) { continue }
            issues.append(IssueText.make(
                severity,
                id: unit.id.rawValue,
                field: "soundExample",
                "\(special.character) (\(special.translit)) has no soundExample in \(unit.id.rawValue)."
            ))
        }
        return issues
    }
}

public enum IDRegistryCheck {
    public static func issues(entries: [RegistryEntry], bundle: ContentBundle) -> [ValidationIssue] {
        let present = contentIDs(in: bundle)
        var issues: [ValidationIssue] = []
        var seen: Set<String> = []
        for entry in entries {
            if !seen.insert(entry.id).inserted {
                issues.append(IssueText.make(.error, id: entry.id, field: "id-registry.json", "\(entry.id) is repeated in id-registry.json."))
                continue
            }
            let used = present.contains(entry.id)
            if entry.retired, used {
                issues.append(IssueText.make(
                    .error,
                    id: entry.id,
                    field: "id-registry.json",
                    "\(entry.id) is retired in id-registry.json and is used again."
                ))
            } else if !entry.retired, !used {
                issues.append(IssueText.make(
                    .error,
                    id: entry.id,
                    field: "id-registry.json",
                    "\(entry.id) is in id-registry.json and is not retired, but it is not in the content."
                ))
            }
        }
        return issues
    }

    public static func contentIDs(in bundle: ContentBundle) -> Set<String> {
        var ids = Set(bundle.items.map(\.id.rawValue))
        for unit in bundle.units {
            ids.insert(unit.id.rawValue)
            for lesson in unit.lessons {
                ids.insert(lesson.id.rawValue)
                for dialog in lesson.dialogs {
                    ids.insert(dialog.id.rawValue)
                }
            }
        }
        return ids
    }
}
