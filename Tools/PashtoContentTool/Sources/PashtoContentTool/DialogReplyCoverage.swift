import PashtoCore

/// Dialog replies need three wrong options of the same shape as the answer.
///
/// The count is `DialogResponse.eligibleDistractors`, built the way a lesson
/// quiz is built: every lesson up to and including the reply's lesson is seen.
/// The walk is the whole course. `release-units.json` may be empty, and an
/// answer task in that course still has to meet the minimum. Release mode
/// reports a shortage as an error. Dev mode reports it as a warning.
///
/// Two replies are exempt. Approved by Farhad 2026-11-02. Both are in
/// `l-greetings-1`, and both keep `responseTo`. The lesson quiz still skips
/// them, because they have fewer than three same-type wrong options:
/// `e-walaykum-salam` (the reply to السلام علیکم) and `e-xwar-ma-she` (the
/// reply to ستړی مه شې). An exempt reply that reaches three wrong options
/// warns, so the list does not stay after the reason is gone.
enum DialogReplyCoverage {
    /// Replies the release gate allows below `DialogResponse.minimumDistractors`.
    static let exceptions: Set<String> = [
        "e-walaykum-salam",
        "e-xwar-ma-she",
    ]

    static func issues(
        in bundle: ContentBundle,
        retiredItemIDs: [ItemID],
        mode: ToolMode,
        exceptions: Set<String> = DialogReplyCoverage.exceptions
    ) -> [ValidationIssue] {
        let severity: ValidationSeverity = mode == .release ? .error : .warning
        var issues: [ValidationIssue] = []
        var seen: [LessonID] = []
        var replies: Set<String> = []
        for lesson in bundle.units.flatMap(\.lessons) {
            seen.append(lesson.id)
            let context = QuizContext(
                bundle: bundle,
                seenLessonIDs: seen,
                retiredItemIDs: retiredItemIDs
            )
            for item in Distractors.introducedItems(in: lesson.id, bundle: bundle) {
                guard item.responseTo != nil else { continue }
                replies.insert(item.id.rawValue)
                switch DialogResponse.skipReason(for: item, in: context) {
                case .sharedUsage:
                    issues.append(IssueText.make(
                        severity,
                        id: item.id.rawValue,
                        field: field,
                        "\(item.id.rawValue) in \(lesson.id.rawValue) is not asked as a dialog reply because another seen reply to the same line has the same usage."
                    ))
                    continue
                case .unavailable:
                    continue
                case nil:
                    break
                }
                let count = DialogResponse.eligibleDistractors(for: item, in: context).count
                if exceptions.contains(item.id.rawValue) {
                    if count >= DialogResponse.minimumDistractors {
                        issues.append(IssueText.make(
                            .warning,
                            id: item.id.rawValue,
                            field: field,
                            "\(item.id.rawValue) in \(lesson.id.rawValue) is on the dialog-reply exception list and has \(count) wrong options of the same type. The exception is no longer needed."
                        ))
                    }
                    continue
                }
                if count < DialogResponse.minimumDistractors {
                    issues.append(IssueText.make(
                        severity,
                        id: item.id.rawValue,
                        field: field,
                        "\(item.id.rawValue) in \(lesson.id.rawValue) has \(count) wrong options of the same type for its dialog reply question. At least \(DialogResponse.minimumDistractors) are needed."
                    ))
                }
            }
        }
        for id in exceptions.sorted() where !replies.contains(id) {
            issues.append(IssueText.make(
                .warning,
                id: id,
                field: field,
                "\(id) is on the dialog-reply exception list and is not a dialog reply in the course."
            ))
        }
        return issues
    }

    private static let field = "dialogReply"
}
