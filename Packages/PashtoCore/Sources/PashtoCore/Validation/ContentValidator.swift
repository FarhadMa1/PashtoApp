import Foundation

/// Checks a decoded content bundle.
///
/// Every problem is returned. The check does not stop at the first one.
/// `validate(_:mode:)` uses `PashtoStressRule`. Pass `stress` to run a different rule.
///
/// Release-unit membership, lesson size, and a warning for audio in v1.0 are not checked.
/// The content tool owns those gates.
/// A `soundExample` must point at an item introduced in exactly one later unit.
/// Letters are introduced through `letters`. U+0640 is allowed only in letter `forms`.
public enum ContentValidator {
    public static func validate(_ bundle: ContentBundle, mode: ValidationMode) -> [ValidationIssue] {
        validate(bundle, mode: mode, stress: PashtoStressRule())
    }

    public static func validate<Rule: StressRule>(
        _ bundle: ContentBundle,
        mode: ValidationMode,
        stress: Rule
    ) -> [ValidationIssue] {
        // Release-unit membership and lesson size are not applied in either mode.
        switch mode {
        case .authoring, .release:
            break
        }

        var report = Report()
        if bundle.variant != ContentBundle.kabulVariant {
            report.add(.error, id: nil, field: "variant", "variant must be \(ContentBundle.kabulVariant).")
        }
        report.add(contentsOf: difficultCharacterIssues(bundle.romanization.difficultCharacters))
        report.add(contentsOf: stress.unstressedListIssues(
            bundle.romanization.unstressedWords,
            tableTransliterations: bundle.romanization.table.map(\.translit)
        ))

        var itemsByID: [String: ContentItem] = [:]
        for item in bundle.items where itemsByID[item.id.rawValue] == nil {
            itemsByID[item.id.rawValue] = item
        }
        let known = Set(itemsByID.keys)
        var seenItemIDs: Set<String> = []
        var meanings: [Meaning: String] = [:]
        var firstResponse: [String: String] = [:]
        for item in bundle.items {
            let id = item.id.rawValue
            if !seenItemIDs.insert(id).inserted {
                report.add(.error, id: id, field: "id", "Item \(id) is duplicated.")
            }
            checkItem(item, bundle: bundle, stress: stress, report: &report)
            recordMeaning(item, seen: &meanings, report: &report)
            recordResponse(item, known: known, first: &firstResponse, report: &report)
        }

        var introductions: [String: [String]] = [:]
        var regularIntroductions: [String: [String]] = [:]
        var soundExamples: [String: [String]] = [:]
        var seenUnits: Set<String> = []
        var seenLessons: Set<String> = []
        var seenDialogs: Set<String> = []
        let firstUnit = bundle.units.first?.id.rawValue
        for (unitIndex, unit) in bundle.units.enumerated() {
            let unitID = unit.id.rawValue
            if !seenUnits.insert(unitID).inserted {
                report.add(.error, id: unitID, field: "id", "Unit \(unitID) is duplicated.")
            }
            for lesson in unit.lessons {
                let lessonID = lesson.id.rawValue
                if !seenLessons.insert(lessonID).inserted {
                    report.add(.error, id: lessonID, field: "id", "Lesson \(lessonID) is duplicated.")
                }
                var lessonItems: [String] = []
                for ref in lesson.items {
                    let itemID = ref.item.rawValue
                    lessonItems.append(itemID)
                    if !known.contains(itemID) {
                        report.add(.error, id: itemID, field: "items", "Lesson \(lessonID) references \(itemID), which does not exist.")
                    }
                    switch ref.role {
                    case .introduce:
                        introductions[itemID, default: []].append(lessonID)
                        if unitIndex > 0 {
                            regularIntroductions[itemID, default: []].append(lessonID)
                        }
                    case .soundExample:
                        soundExamples[itemID, default: []].append(lessonID)
                        if unitIndex != 0 {
                            let allowed = firstUnit ?? "(none)"
                            report.add(
                                .error,
                                id: itemID,
                                field: "role",
                                "soundExample \(itemID) is in \(unitID). It is only allowed in the first unit (\(allowed))."
                            )
                        }
                        if Text.isBlank(ref.sound) {
                            report.add(.error, id: itemID, field: "sound", "soundExample \(itemID) needs a sound.")
                        }
                    }
                }
                for letter in lesson.letters {
                    let itemID = letter.rawValue
                    lessonItems.append(itemID)
                    if !known.contains(itemID) {
                        report.add(.error, id: itemID, field: "letters", "Lesson \(lessonID) lists letter \(itemID), which does not exist.")
                    } else if itemsByID[itemID]?.kind != .letter {
                        report.add(.error, id: itemID, field: "letters", "\(itemID) is listed in letters but its kind is \(itemsByID[itemID]?.kind.rawValue ?? "unknown").")
                    }
                    introductions[itemID, default: []].append(lessonID)
                    if unitIndex > 0 {
                        regularIntroductions[itemID, default: []].append(lessonID)
                    }
                }
                for dialog in lesson.dialogs {
                    let dialogID = dialog.id.rawValue
                    if !seenDialogs.insert(dialogID).inserted {
                        report.add(.error, id: dialogID, field: "id", "Dialog \(dialogID) is duplicated.")
                    }
                    for turn in dialog.turns {
                        let itemID = turn.item.rawValue
                        lessonItems.append(itemID)
                        if !known.contains(itemID) {
                            report.add(
                                .error,
                                id: itemID,
                                field: "turns",
                                "Dialog \(dialogID) in \(lessonID) references \(itemID), which does not exist."
                            )
                        }
                    }
                }
                checkLessonMeanings(lessonItems, lessonID: lessonID, itemsByID: itemsByID, report: &report)
            }
        }

        for item in bundle.items {
            let id = item.id.rawValue
            let intros = introductions[id] ?? []
            let regular = regularIntroductions[id] ?? []
            let isSoundExample = !(soundExamples[id] ?? []).isEmpty
            if isSoundExample {
                // Unit 0 is the sounds unit. A regular lesson is a later unit.
                if regular.count != 1 {
                    if regular.isEmpty {
                        report.add(.error, id: id, field: "role", "\(id) is not introduced in a lesson.")
                    } else {
                        report.add(
                            .error,
                            id: id,
                            field: "role",
                            "\(id) is introduced in \(regular.joined(separator: ", ")). An item is introduced once."
                        )
                    }
                } else if intros.count != regular.count {
                    report.add(
                        .error,
                        id: id,
                        field: "role",
                        "\(id) is introduced in \(intros.joined(separator: ", ")). An item is introduced once."
                    )
                }
            } else if intros.count > 1 {
                report.add(
                    .error,
                    id: id,
                    field: "role",
                    "\(id) is introduced in \(intros.joined(separator: ", ")). An item is introduced once."
                )
            } else if intros.isEmpty {
                report.add(.error, id: id, field: "role", "\(id) is not introduced in a lesson.")
            }
        }

        report.add(contentsOf: slashReviews(in: bundle))
        for group in bundle.nonDistractorGroups {
            for item in group where !known.contains(item.rawValue) {
                report.add(
                    .error,
                    id: item.rawValue,
                    field: "nonDistractorGroups",
                    "nonDistractorGroups references \(item.rawValue), which does not exist."
                )
            }
        }
        return report.issues
    }

    private static func checkItem<Rule: StressRule>(
        _ item: ContentItem,
        bundle: ContentBundle,
        stress: Rule,
        report: inout Report
    ) {
        let id = item.id.rawValue
        if Text.isBlank(item.pashto) {
            report.add(.error, id: id, field: "pashto", "pashto is required.")
        } else {
            report.add(contentsOf: PashtoScript.issues(in: item.pashto, id: id, field: "pashto"))
        }
        if Text.isBlank(item.translit) {
            report.add(.error, id: id, field: "translit", "translit is required.")
        } else {
            report.add(contentsOf: TranslitRules.issues(in: item.translit, id: id))
            if item.kind != .letter {
                report.add(contentsOf: stress.issues(
                    in: item.translit,
                    unstressedWords: bundle.romanization.unstressedWords,
                    id: id
                ))
            }
        }
        if Text.isBlank(item.pronunciation) {
            report.add(.error, id: id, field: "pronunciation", "pronunciation is required.")
        } else if !Text.isBlank(item.translit) {
            report.add(contentsOf: PronunciationRules.issues(
                translit: item.translit,
                pronunciation: item.pronunciation,
                id: id,
                syllableCount: { stress.syllableCount(in: $0) },
                requireHyphenWhenMultiSyllable: item.kind != .letter
            ))
        }
        if Text.isBlank(item.en) {
            report.add(.error, id: id, field: "en", "en is required.")
        }

        let hits = bundle.romanization.difficultCharacters.filter { character in
            !Text.isBlank(character) && PashtoScript.containsSequence(character, in: item.pashto)
        }
        if !hits.isEmpty, Text.isBlank(item.pronunciationNote) {
            report.add(
                .error,
                id: id,
                field: "pronunciationNote",
                "pronunciationNote is required because pashto contains \(hits.joined(separator: ", "))."
            )
        }

        if item.kind == .letter {
            checkLetterFields(item, report: &report)
        } else {
            if item.name != nil {
                report.add(.error, id: id, field: "name", "name is only used on letters.")
            }
            if item.forms != nil {
                report.add(.error, id: id, field: "forms", "forms is only used on letters.")
            }
            if item.sound != nil {
                report.add(.error, id: id, field: "sound", "sound is only used on letters.")
            }
            report.add(contentsOf: TokenRules.issues(for: item))
        }

        if item.verification.status == .verified {
            if Text.isBlank(item.verification.checkedBy) {
                report.add(.error, id: id, field: "verification.checkedBy", "verified items need a non-empty checkedBy.")
            }
            if !ISO8601Date.isValid(item.verification.checkedOn ?? "") {
                report.add(.error, id: id, field: "verification.checkedOn", "verified items need a valid ISO-8601 date in checkedOn.")
            }
        }
    }

    private static func checkLetterFields(_ item: ContentItem, report: inout Report) {
        let id = item.id.rawValue
        if Text.isBlank(item.name) {
            report.add(.error, id: id, field: "name", "name is required on a letter.")
        } else if let name = item.name {
            report.add(contentsOf: PashtoScript.issues(in: name, id: id, field: "name"))
        }
        if let forms = item.forms {
            let parts = [
                ("forms.isolated", forms.isolated),
                ("forms.initial", forms.initial),
                ("forms.medial", forms.medial),
                ("forms.final", forms.final),
            ]
            for (field, value) in parts {
                if Text.isBlank(value) {
                    report.add(.error, id: id, field: field, "\(field) is required on a letter.")
                } else {
                    report.add(contentsOf: PashtoScript.issues(in: value, id: id, field: field, allowTatweel: true))
                }
            }
        } else {
            report.add(.error, id: id, field: "forms", "forms is required on a letter.")
        }
        if Text.isBlank(item.sound) {
            report.add(.error, id: id, field: "sound", "sound is required on a letter.")
        }
        if item.tokens != nil {
            report.add(.error, id: id, field: "tokens", "tokens are only used on words and phrases.")
        }
        if item.acceptedOrders != nil {
            report.add(.error, id: id, field: "acceptedOrders", "acceptedOrders is only used on words and phrases.")
        }
        if item.responseTo != nil {
            report.add(.error, id: id, field: "responseTo", "responseTo is only used on words and phrases.")
        }
    }

    private static func recordMeaning(_ item: ContentItem, seen: inout [Meaning: String], report: inout Report) {
        let meaning = Meaning(
            pashto: Normalization.nfc(item.pashto),
            en: Normalization.comparisonKey(item.en ?? ""),
            usage: Normalization.comparisonKey(item.usage ?? "")
        )
        let id = item.id.rawValue
        if let first = seen[meaning] {
            report.add(.error, id: id, field: "pashto", "pashto, en, and usage match \(first).")
        } else {
            seen[meaning] = id
        }
    }

    private static func recordResponse(
        _ item: ContentItem,
        known: Set<String>,
        first: inout [String: String],
        report: inout Report
    ) {
        guard item.kind != .letter, let target = item.responseTo else { return }
        let id = item.id.rawValue
        if !known.contains(target.rawValue) {
            report.add(.error, id: id, field: "responseTo", "responseTo \(target.rawValue) does not exist.")
        }
        let key = target.rawValue + "\n" + Normalization.comparisonKey(item.usage ?? "")
        if let earlier = first[key] {
            report.add(
                .error,
                id: id,
                field: "responseTo",
                "responseTo \(target.rawValue) and usage match \(earlier). usage must distinguish the answers."
            )
        } else {
            first[key] = id
        }
    }

    private static func checkLessonMeanings(
        _ itemIDs: [String],
        lessonID: String,
        itemsByID: [String: ContentItem],
        report: inout Report
    ) {
        var seenIDs: Set<String> = []
        var seenKeys: [String: String] = [:]
        for itemID in itemIDs {
            guard seenIDs.insert(itemID).inserted, let item = itemsByID[itemID] else { continue }
            guard let en = item.en, !Text.isBlank(en) else { continue }
            let key = Normalization.comparisonKey(en) + "\n" + Normalization.comparisonKey(item.usage ?? "")
            if let first = seenKeys[key] {
                report.add(.error, id: itemID, field: "en", "en and usage match \(first) in \(lessonID).")
            } else {
                seenKeys[key] = itemID
            }
        }
    }

    private static func slashReviews(in bundle: ContentBundle) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for item in bundle.items {
            guard let en = item.en, en.contains("/") else { continue }
            let segments = en.split(separator: "/").map { segment -> String in
                Normalization.comparisonKey(trim(String(segment)))
            }.filter { !$0.isEmpty }
            guard !segments.isEmpty else { continue }
            for other in bundle.items where other.id != item.id {
                guard let otherEn = other.en, !Text.isBlank(otherEn) else { continue }
                let otherKey = Normalization.comparisonKey(otherEn)
                guard segments.contains(otherKey) else { continue }
                guard !sharesGroup(item.id, other.id, bundle.nonDistractorGroups) else { continue }
                issues.append(ValidationIssue(
                    id: item.id.rawValue,
                    field: "en",
                    message: "en \"\(en)\" overlaps \(other.id.rawValue) (\"\(otherEn)\"), and they are not in the same nonDistractorGroup.",
                    severity: .review
                ))
            }
        }
        return issues
    }

    private static func sharesGroup(_ lhs: ItemID, _ rhs: ItemID, _ groups: [[ItemID]]) -> Bool {
        for group in groups where group.contains(lhs) && group.contains(rhs) {
            return true
        }
        return false
    }

    private static func difficultCharacterIssues(_ characters: [String]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var seen: [String] = []
        for character in characters {
            if Text.isBlank(character) {
                issues.append(ValidationIssue(
                    id: nil,
                    field: "difficultCharacters",
                    message: "difficultCharacters contains an empty entry.",
                    severity: .error
                ))
                continue
            }
            let scalars = Normalization.unicodeScalars(Normalization.nfc(character))
            if scalars.count != 1 {
                issues.append(ValidationIssue(
                    id: nil,
                    field: "difficultCharacters",
                    message: "difficultCharacters entry \"\(character)\" must be one character.",
                    severity: .error
                ))
                continue
            }
            let key = Normalization.nfc(character)
            if seen.contains(key) {
                issues.append(ValidationIssue(
                    id: nil,
                    field: "difficultCharacters",
                    message: "difficultCharacters repeats \(character).",
                    severity: .error
                ))
            } else {
                seen.append(key)
            }
        }
        return issues
    }

    private static func trim(_ text: String) -> String {
        var scalars = Array(text.unicodeScalars)
        while let first = scalars.first, Character(first).isWhitespace {
            scalars.removeFirst()
        }
        while let last = scalars.last, Character(last).isWhitespace {
            scalars.removeLast()
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private struct Meaning: Hashable {
        var pashto: String
        var en: String
        var usage: String
    }

    private struct Report {
        var issues: [ValidationIssue] = []

        mutating func add(_ severity: ValidationSeverity, id: String?, field: String, _ message: String) {
            issues.append(ValidationIssue(id: id, field: field, message: message, severity: severity))
        }

        mutating func add(contentsOf newIssues: [ValidationIssue]) {
            issues.append(contentsOf: newIssues)
        }
    }
}
