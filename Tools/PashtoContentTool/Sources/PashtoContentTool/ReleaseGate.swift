import Foundation
import PashtoCore

/// Release checks that sit on top of `ContentValidator`.
///
/// The gate reports problems. It does not remove items. Lesson size and
/// unverified items are errors in `release` and warnings in `dev`. A difficult
/// character with no `soundExample` in the first unit is a warning in `dev`.
/// It is an error in `release` only when that first unit is listed in
/// `release-units.json`. Audio in v1.0 is a warning in both modes.
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
                let count = lesson.items.count + lesson.letters.count
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

        for item in bundle.items where item.hasAudio {
            issues.append(IssueText.make(
                .warning,
                id: item.id.rawValue,
                field: "audio",
                "\(item.id.rawValue) has audio. v1.0 does not ship audio."
            ))
        }

        // Dev always warns, so a missing example stays visible.
        // Release errors only when the first unit, the sounds unit, is on the release list.
        if mode == .dev {
            issues.append(contentsOf: soundExampleIssues(in: bundle, specialSounds: specialSounds, severity: .warning))
        } else if let soundsUnit = bundle.units.first, releaseUnits.contains(soundsUnit.id.rawValue) {
            issues.append(contentsOf: soundExampleIssues(in: bundle, specialSounds: specialSounds, severity: .error))
        }
        return issues
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
