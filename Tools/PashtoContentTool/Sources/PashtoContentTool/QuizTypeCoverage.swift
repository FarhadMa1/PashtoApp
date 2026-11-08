import PashtoCore

/// Each `TaskKind` must show up at least once in generated questions.
///
/// The questions come from `LessonSessionBuilder`, not from raw fields such
/// as `tokens` or `responseTo`. Lessons run in course order. A lesson counts
/// as seen together with the lessons before it, and a `soundExample` does
/// not introduce an item. Retired ids are left out. Those are the seen-content
/// rules the session builder uses.
///
/// Release counts the units `ReleaseGate.releasedUnits` returns, and treats
/// only those lessons as seen. Dev counts every lesson in the course. Both
/// walks follow course order.
///
/// The count uses `maxQuestions: nil`. The lesson cap is 20 and keeps a
/// shuffled subset, so one seed can drop a type that another seed keeps.
/// With the cap off, every question the generators return is counted. Each
/// lesson is walked twice: once with pronunciation shown and once with it
/// hidden. A pronunciation choice is not built on either walk. B1 and B3 exist
/// only in the first walk, and only when the lesson still introduces letters.
/// B2 exists in both walks in that case. Release does not require the letter
/// tasks or the pronunciation choice: units 1–3 hide their letters. Word order
/// is required while sessions include it. The seed is fixed only so the walk
/// can be repeated. It does not decide which types are present. A missing
/// required type is a warning in dev and an error in release.
enum QuizTypeCoverage {
    static func issues(
        in bundle: ContentBundle,
        releaseUnitIDs: [String],
        retiredItemIDs: [ItemID],
        mode: ToolMode
    ) -> [ValidationIssue] {
        let severity: ValidationSeverity = mode == .release ? .error : .warning
        let listed: [String]? = mode == .release ? releaseUnitIDs : nil
        let counts = questionCounts(
            in: bundle,
            releaseUnitIDs: listed,
            retiredItemIDs: retiredItemIDs,
            seed: coverageSeed
        )
        return requiredKinds(for: mode).compactMap { kind in
            guard counts[kind, default: 0] == 0 else { return nil }
            return IssueText.make(
                severity,
                id: kind.rawValue,
                field: "quizType",
                "quiz type \(kind.rawValue) produces 0 questions in released content"
            )
        }
    }

    /// `releaseUnitIDs == nil` walks the whole course. A list walks only the
    /// released units, and only those lessons count as seen.
    static func questionCounts(
        in bundle: ContentBundle,
        releaseUnitIDs: [String]?,
        retiredItemIDs: [ItemID],
        seed: UInt64 = coverageSeed
    ) -> [TaskKind: Int] {
        let course = releaseUnitIDs == nil ? bundle : PlayableCourse.hidingScript(bundle)
        let lessons: [Lesson]
        if let releaseUnitIDs {
            lessons = ReleaseGate.releasedUnits(in: course, releaseUnitIDs: releaseUnitIDs).flatMap(\.lessons)
        } else {
            lessons = course.units.flatMap(\.lessons)
        }
        var counts = Dictionary(uniqueKeysWithValues: TaskKind.allCases.map { ($0, 0) })
        var seen: [LessonID] = []
        var rng = SplitMix64(seed: seed)
        // Neither walk builds a pronunciation choice. B1 and B3 are built only
        // while pronunciation is shown and the lesson still introduces letters.
        // B2 is built in both walks in that case. Word order counts when
        // sessions include it.
        // A kind counts when either walk produces it.
        let released = releaseUnitIDs?.compactMap(UnitID.init(rawValue:))
        for lesson in lessons {
            seen.append(lesson.id)
            for showsPronunciation in [true, false] {
                let session = LessonSessionBuilder.build(
                    for: lesson.id,
                    in: course,
                    seenLessonIDs: seen,
                    retiredItemIDs: retiredItemIDs,
                    maxQuestions: nil,
                    releasedUnitIDs: released,
                    showsPronunciation: showsPronunciation,
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

    /// Word order is required only while sessions build it.
    ///
    /// Release does not require letter tasks or a pronunciation choice.
    /// Dev still requires letter tasks, because the source course still has them.
    private static func requiredKinds(for mode: ToolMode) -> [TaskKind] {
        TaskKind.allCases.filter { kind in
            if kind == .orderWords, !OrderWords.includedInSessions { return false }
            if kind == .transliterationChoice { return false }
            if mode == .release, PlayableCourse.retiredQuizKinds.contains(kind) { return false }
            return true
        }
    }
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
