import Foundation
import PashtoCore

/// `ContentValidator` plus the registry, the release gate, quiz-type coverage,
/// and the dialog-reply distractor count.
///
/// `ContentValidator` rules are unchanged. A verified item that lacks `checkedBy`
/// or `checkedOn` is still that validator's error, in both modes. Quiz-type
/// coverage is a warning in dev, over the whole course, and an error in
/// release, over the units `ReleaseGate` selects from `release-units.json`.
/// A dialog reply with fewer than three same-type wrong options is a warning
/// in dev and an error in release, except the replies `DialogReplyCoverage`
/// lists.
public enum ContentCheck {
    public static func issues(root: URL, mode: ToolMode) -> [ValidationIssue] {
        let outcome = ContentMerger.merge(root: root)
        var issues = outcome.issues
        let paths = ContentRoot(url: root)
        let releaseUnits = loadReleaseUnits(paths, issues: &issues)
        let registry = loadRegistry(paths, issues: &issues)
        guard let merged = outcome.merged else { return issues }
        // Unstressed-word checks always run. Each word must be one syllable and
        // use only characters that appear in the course table.
        let validated = ContentValidator.validate(merged.bundle, mode: mode.validationMode)
        issues.append(contentsOf: validated)
        issues.append(contentsOf: IDRegistryCheck.issues(entries: registry, bundle: merged.bundle))
        issues.append(contentsOf: ReleaseGate.issues(
            in: merged.bundle,
            releaseUnitIDs: releaseUnits,
            itemUnits: merged.itemUnits,
            specialSounds: merged.specialSounds,
            mode: mode
        ))
        let retiredItemIDs = registry.compactMap { entry -> ItemID? in
            guard entry.retired else { return nil }
            return ItemID(rawValue: entry.id)
        }
        issues.append(contentsOf: QuizTypeCoverage.issues(
            in: merged.bundle,
            releaseUnitIDs: releaseUnits,
            retiredItemIDs: retiredItemIDs,
            mode: mode
        ))
        issues.append(contentsOf: DialogReplyCoverage.issues(
            in: merged.bundle,
            retiredItemIDs: retiredItemIDs,
            mode: mode
        ))
        return issues
    }

    private static func loadReleaseUnits(_ paths: ContentRoot, issues: inout [ValidationIssue]) -> [String] {
        guard let data = try? Data(contentsOf: paths.releaseUnitsFile) else {
            issues.append(IssueText.make(.error, id: nil, field: "release-units.json", "content/release-units.json could not be read."))
            return []
        }
        if let unknown = try? SourceDecode.unknownKeys(in: data, allowed: ["units", "note"]), !unknown.isEmpty {
            issues.append(IssueText.make(.error, id: nil, field: "release-units.json", "content/release-units.json has unknown key(s): \(unknown.joined(separator: ", "))."))
        }
        do {
            return try JSONDecoder().decode(ReleaseUnitsFile.self, from: data).units
        } catch {
            issues.append(IssueText.make(.error, id: nil, field: "release-units.json", "content/release-units.json could not be decoded: \(error)"))
            return []
        }
    }

    private static func loadRegistry(_ paths: ContentRoot, issues: inout [ValidationIssue]) -> [RegistryEntry] {
        guard let data = try? Data(contentsOf: paths.registryFile) else {
            issues.append(IssueText.make(.error, id: nil, field: "id-registry.json", "content/id-registry.json could not be read."))
            return []
        }
        if let unknown = try? SourceDecode.unknownKeys(in: data, allowed: ["entries", "note"]), !unknown.isEmpty {
            issues.append(IssueText.make(.error, id: nil, field: "id-registry.json", "content/id-registry.json has unknown key(s): \(unknown.joined(separator: ", "))."))
        }
        do {
            let file = try JSONDecoder().decode(RegistryFile.self, from: data)
            return file.entries.map { RegistryEntry(id: $0.id, retired: $0.retired ?? false) }
        } catch {
            issues.append(IssueText.make(.error, id: nil, field: "id-registry.json", "content/id-registry.json could not be decoded: \(error)"))
            return []
        }
    }
}
