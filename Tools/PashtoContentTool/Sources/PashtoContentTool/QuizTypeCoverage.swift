import PashtoCore

/// Each `TaskKind` must show up at least once in generated questions.
///
/// The questions come from `LessonSessionBuilder`, not from raw fields such
/// as `tokens` or `responseTo`. Lessons run in course order. A lesson counts
/// as seen together with the lessons before it, and a `soundExample` does
/// not introduce an item. Retired ids are left out. Those are the seen-content
/// rules the session builder uses.
///
/// The count uses `maxQuestions: nil`. The lesson cap is 20 and keeps a
/// shuffled subset, so one seed can drop a type that another seed keeps.
/// With the cap off, every question the generators return is counted. The
/// seed is fixed only so the walk can be repeated. It does not decide which
/// types are present. A missing type is a warning in dev and an error in release.
enum QuizTypeCoverage {
    static func issues(
        in bundle: ContentBundle,
        retiredItemIDs: [ItemID],
        mode: ToolMode
    ) -> [ValidationIssue] {
        let severity: ValidationSeverity = mode == .release ? .error : .warning
        let counts = questionCounts(in: bundle, retiredItemIDs: retiredItemIDs, seed: coverageSeed)
        return TaskKind.allCases.compactMap { kind in
            guard counts[kind, default: 0] == 0 else { return nil }
            return IssueText.make(
                severity,
                id: kind.rawValue,
                field: "quizType",
                "quiz type \(kind.rawValue) produces 0 questions in released content"
            )
        }
    }

    static func questionCounts(
        in bundle: ContentBundle,
        retiredItemIDs: [ItemID],
        seed: UInt64 = coverageSeed
    ) -> [TaskKind: Int] {
        var counts = Dictionary(uniqueKeysWithValues: TaskKind.allCases.map { ($0, 0) })
        var seen: [LessonID] = []
        var rng = SplitMix64(seed: seed)
        for unit in bundle.units {
            for lesson in unit.lessons {
                seen.append(lesson.id)
                let session = LessonSessionBuilder.build(
                    for: lesson.id,
                    in: bundle,
                    seenLessonIDs: seen,
                    retiredItemIDs: retiredItemIDs,
                    maxQuestions: nil,
                    using: &rng
                )
                for task in session.tasks {
                    counts[task.kind, default: 0] += 1
                }
            }
        }
        return counts
    }

    /// Fixed seed for a repeatable walk. Kind totals stay the same for any other seed.
    private static let coverageSeed: UInt64 = 1
}

/// Deterministic generator. Same step as the SplitMix64 in the PashtoCore tests.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
