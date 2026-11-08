import Foundation

/// Approved celebration, streak, daily-goal, and path words.
///
/// The English matches `PashtoApp/Localizable.xcstrings`. The app passes those
/// catalog strings in. The defaults are the same English, so a test can read
/// the sentence without the app bundle. A count of new words is not a
/// first-try correct count, and a finished lesson is not quiz feedback.
public enum CelebrationCopy {
    public static let lessonComplete = "Lesson complete"
    public static let correct = "correct"
    public static let dayStreak = "day streak"
    public static let dailyGoal = "Daily goal"
    public static let toGo = "to go"
    public static let goalReached = "Goal reached"
    public static let wordOne = "word"
    public static let wordOther = "words"

    /// `1 word`, `2 words`. Zero and every count other than 1 use the plural.
    public static func wordCount(
        _ count: Int,
        one: String = wordOne,
        other: String = wordOther
    ) -> String {
        let unit = count == 1 ? one : other
        return "\(count) \(unit)"
    }

    /// New words today against the stored limit.
    ///
    /// The approved shape is `Daily goal: 6 of 10 words, 4 to go`. The noun
    /// follows the limit. `Goal reached` replaces `to go` once the shown count
    /// meets a limit above zero, including when a lesson runs past the limit.
    /// A limit of zero draws no check, so the sentence has no status clause.
    public static func dailyGoalSpoken(
        done: Int,
        goal: Int,
        title: String = dailyGoal,
        one: String = wordOne,
        other: String = wordOther,
        toGo: String = toGo,
        goalReached: String = goalReached
    ) -> String {
        let shown = max(0, done)
        let limit = max(0, goal)
        let head = "\(title): \(shown) of \(wordCount(limit, one: one, other: other))"
        guard limit > 0 else { return head }
        if shown >= limit {
            return "\(head), \(goalReached)"
        }
        return "\(head), \(limit - shown) \(toGo)"
    }

    /// The stored streak count with the approved label. The label does not change with the count.
    public static func streakSpoken(_ count: Int, label: String = dayStreak) -> String {
        "\(max(0, count)) \(label)"
    }

    /// What VoiceOver reads when the lesson finishes.
    ///
    /// `CounterPlan.spoken` is the final correct count in every mode, including
    /// while a sighted counter is still stepping. The answered count is not
    /// included: it is not a new-word count, and it has no approved name.
    /// Pronunciation is included only when this session is already showing it.
    public static func accessibleResult(
        stats: LessonFinishStats,
        praise: LessonPraise,
        showsPronunciation: Bool,
        reduceMotion: Bool,
        voiceOver: Bool,
        title: String = lessonComplete,
        correct: String = correct
    ) -> String {
        let finalCorrect = CounterPlan.plan(
            target: stats.correct,
            reduceMotion: reduceMotion,
            voiceOver: voiceOver,
            skipped: false
        ).spoken
        var parts = [title, praise.pashto]
        if showsPronunciation {
            let pronunciation = praise.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pronunciation.isEmpty {
                parts.append(pronunciation)
            }
        }
        parts.append("\(finalCorrect) \(correct)")
        return parts.joined(separator: ", ")
    }
}

/// The two praise lines Farhad approved. Nothing else is offered.
public enum LessonPraise: Equatable, Sendable, CaseIterable {
    case kha
    case deraKha

    public var pashto: String {
        switch self {
        case .kha: "ښه"
        case .deraKha: "ډېره ښه"
        }
    }

    /// Simple pronunciation, the same field the quiz draws under Pashto.
    public var pronunciation: String {
        switch self {
        case .kha: "kha"
        case .deraKha: "DE-ra kha"
        }
    }

    /// Same lesson, same praise. Even totals of the id bytes are `ښه`.
    public static func select(lessonID: LessonID) -> LessonPraise {
        let sum = lessonID.rawValue.utf8.reduce(0) { $0 + Int($1) }
        return sum.isMultiple(of: 2) ? .kha : .deraKha
    }
}

/// `Now` and `Locked` for the course path. A finished lesson has neither.
///
/// Quiz `Correct` is not a path label. A lesson is `Locked` only when the
/// caller says it cannot be opened. The home can open every released lesson,
/// so it passes an empty locked set and those rows stay unlabeled.
public enum CoursePathCopy {
    public static let now = "Now"
    public static let locked = "Locked"

    public enum Mark: Equatable, Sendable {
        case now
        case locked
        case plain
    }

    public static func mark(
        id: LessonID,
        order: [LessonID],
        finished: Set<LessonID>,
        locked: Set<LessonID>
    ) -> Mark {
        if finished.contains(id) { return .plain }
        if CoursePathMotion.next(in: order, finished: finished) == id { return .now }
        if locked.contains(id) { return .locked }
        return .plain
    }

    public static func accessibilityLabel(
        title: String,
        mark: Mark,
        now: String = now,
        locked: String = locked
    ) -> String {
        switch mark {
        case .now:
            return "\(title), \(now)"
        case .locked:
            return "\(title), \(locked)"
        case .plain:
            return title
        }
    }
}
