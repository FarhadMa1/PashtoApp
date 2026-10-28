import Foundation
import PashtoCore

/// Loads `content/course.json`, `content/units/*.json`, and `content/difficult-characters.json`.
///
/// Unit order comes from `course.json`. The same inputs encode to the same bytes.
public struct MergedCourse: Sendable {
    public let bundle: ContentBundle
    public let itemUnits: [String: String]
    public let specialSounds: [SpecialSound]
    public let issues: [ValidationIssue]

    public init(bundle: ContentBundle, itemUnits: [String: String], specialSounds: [SpecialSound], issues: [ValidationIssue]) {
        self.bundle = bundle
        self.itemUnits = itemUnits
        self.specialSounds = specialSounds
        self.issues = issues
    }
}

public enum ContentMerger {
    public static func merge(root: URL) -> MergeOutcome {
        let paths = ContentRoot(url: root)
        var issues: [ValidationIssue] = []

        guard let courseData = optionalData(paths.courseFile, issues: &issues, label: "content/course.json") else {
            return MergeOutcome(merged: nil, bytes: nil, issues: issues)
        }
        issues.append(contentsOf: unknownKeyIssues(courseData, allowed: ["units", "nonDistractorGroups", "note"], file: "content/course.json"))
        guard let course = decode(CourseFile.self, courseData, file: "content/course.json", issues: &issues) else {
            return MergeOutcome(merged: nil, bytes: nil, issues: issues)
        }

        guard let difficultData = optionalData(paths.difficultCharactersFile, issues: &issues, label: "content/difficult-characters.json") else {
            return MergeOutcome(merged: nil, bytes: nil, issues: issues)
        }
        guard let difficult = decode(DifficultCharacterList.self, difficultData, file: "content/difficult-characters.json", issues: &issues) else {
            return MergeOutcome(merged: nil, bytes: nil, issues: issues)
        }
        issues.append(contentsOf: DifficultCharacterRules.issues(in: difficult))

        var seenUnitNames: Set<String> = []
        var items: [ContentItem] = []
        var units: [CourseUnit] = []
        var itemUnits: [String: String] = [:]
        var located: [String: String] = [:]

        for name in course.units {
            if !seenUnitNames.insert(name).inserted {
                issues.append(error("course.json lists \(name) more than once."))
                continue
            }
            let fileURL = paths.unitFile(named: name)
            let relative = "content/units/\(name).json"
            guard let data = optionalData(fileURL, issues: &issues, label: relative) else { continue }
            issues.append(contentsOf: unknownKeyIssues(data, allowed: ["id", "track", "title", "items", "lessons"], file: relative))
            guard let file = decode(UnitFile.self, data, file: relative, issues: &issues) else { continue }
            if file.id != name {
                issues.append(error("\(relative) has id \(file.id). The file name must match the unit id."))
            }
            guard let unitID = UnitID(rawValue: file.id) else {
                issues.append(error("\(relative) has id \(file.id), which is not a unit id."))
                continue
            }
            record(file.id, file: relative, kind: "Unit", located: &located, issues: &issues)
            for item in file.items {
                let id = item.id.rawValue
                record(id, file: relative, kind: "Item", located: &located, issues: &issues)
                if itemUnits[id] == nil {
                    itemUnits[id] = file.id
                    items.append(item)
                }
            }
            for lesson in file.lessons {
                record(lesson.id.rawValue, file: relative, kind: "Lesson", located: &located, issues: &issues)
                for dialog in lesson.dialogs {
                    record(dialog.id.rawValue, file: relative, kind: "Dialog", located: &located, issues: &issues)
                }
            }
            units.append(CourseUnit(id: unitID, track: file.track, title: file.title, lessons: file.lessons))
        }

        issues.append(contentsOf: extraUnitFiles(paths: paths, expected: Set(course.units)))

        var groups: [[ItemID]] = []
        for group in course.nonDistractorGroups {
            var ids: [ItemID] = []
            for raw in group {
                guard let id = ItemID(rawValue: raw) else {
                    issues.append(error("nonDistractorGroups entry \(raw) is not an item id."))
                    continue
                }
                ids.append(id)
            }
            groups.append(ids)
        }

        let bundle = ContentBundle(
            contentVersion: GeneratedBundle.contentVersion,
            variant: ContentBundle.kabulVariant,
            romanization: GeneratedBundle.romanization(from: difficult),
            items: items,
            units: units,
            nonDistractorGroups: groups
        )
        let sounds = difficult.letters.map { SpecialSound(character: $0.char, translit: $0.translit) }
        let merged = MergedCourse(bundle: bundle, itemUnits: itemUnits, specialSounds: sounds, issues: issues)
        let bytes = (try? BundleJSON.encode(bundle))
        if bytes == nil {
            issues.append(error("content.json could not be encoded."))
        }
        return MergeOutcome(merged: merged, bytes: bytes, issues: issues)
    }

    public static func checkCommittedBundle(root: URL) -> [ValidationIssue] {
        let outcome = merge(root: root)
        var issues = outcome.issues
        let paths = ContentRoot(url: root)
        guard let bytes = outcome.bytes else { return issues }
        let relative = "content/content.json"
        guard let committed = try? Data(contentsOf: paths.bundleFile) else {
            issues.append(error("\(relative) is missing. Run merge and commit the generated file."))
            return issues
        }
        if committed != bytes {
            issues.append(error("\(relative) does not match the merge output. Run merge and commit the generated file."))
        }
        return issues
    }

    private static func extraUnitFiles(paths: ContentRoot, expected: Set<String>) -> [ValidationIssue] {
        let directory = paths.unitsDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return [error("content/units is missing.")]
        }
        var issues: [ValidationIssue] = []
        for name in names.sorted() where name.hasSuffix(".json") {
            let unit = String(name.dropLast(5))
            if !expected.contains(unit) {
                issues.append(error("content/units/\(name) is not listed in course.json."))
            }
        }
        return issues
    }

    private static func record(
        _ id: String,
        file: String,
        kind: String,
        located: inout [String: String],
        issues: inout [ValidationIssue]
    ) {
        if let first = located[id] {
            if first == file {
                issues.append(error("\(kind) \(id) is repeated in \(file)."))
            } else {
                issues.append(error("\(kind) \(id) is in \(first) and \(file)."))
            }
        } else {
            located[id] = file
        }
    }

    private static func optionalData(_ url: URL, issues: inout [ValidationIssue], label: String) -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch {
            issues.append(Self.error("\(label) could not be read."))
            return nil
        }
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        _ data: Data,
        file: String,
        issues: inout [ValidationIssue]
    ) -> T? {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            issues.append(Self.error("\(file) could not be decoded: \(error)"))
            return nil
        }
    }

    private static func unknownKeyIssues(_ data: Data, allowed: Set<String>, file: String) -> [ValidationIssue] {
        do {
            let unknown = try SourceDecode.unknownKeys(in: data, allowed: allowed)
            if unknown.isEmpty { return [] }
            return [error("\(file) has unknown key(s): \(unknown.joined(separator: ", ")).")]
        } catch {
            return [Self.error("\(file) is not a JSON object.")]
        }
    }

    private static func error(_ message: String) -> ValidationIssue {
        IssueText.make(.error, id: nil, field: "merge", message)
    }
}

public struct MergeOutcome: Sendable {
    public let merged: MergedCourse?
    public let bytes: Data?
    public let issues: [ValidationIssue]
}
