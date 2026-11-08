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
    /// Visible line on the freeze card. The VoiceOver sentence lowercases it after the count.
    public static let streakFreezeEarned = "Streak freeze earned"
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
    /// while a sighted counter is still stepping. The answered total is the
    /// denominator of the labelled fraction, so this sentence does not repeat it.
    /// Pronunciation is included. The stored preference does not leave it out.
    public static func accessibleResult(
        stats: LessonFinishStats,
        praise: LessonPraise,
        showsPronunciation _: Bool,
        reduceMotion: Bool,
        voiceOver: Bool,
        title: String = lessonComplete,
        correct: String = correct
    ) -> String {
        let layout = resultLayout(
            stats: stats,
            reduceMotion: reduceMotion,
            voiceOver: voiceOver,
            label: correct
        )
        var parts = [title, praise.pashto]
        let pronunciation = praise.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pronunciation.isEmpty {
            parts.append(pronunciation)
        }
        parts.append("\(layout.correctPlan.spoken) \(correct)")
        return parts.joined(separator: ", ")
    }

    /// The one labelled figure on the finished lesson.
    ///
    /// The answered total is the denominator of `fraction`. It is not returned
    /// again as its own number.
    public static func resultLayout(
        stats: LessonFinishStats,
        reduceMotion: Bool,
        voiceOver: Bool,
        skipped: Bool = false,
        label: String = correct
    ) -> CelebrationResultLayout {
        CelebrationResultLayout(
            correctPlan: CounterPlan.plan(
                target: stats.correct,
                reduceMotion: reduceMotion,
                voiceOver: voiceOver,
                skipped: skipped
            ),
            answeredTotal: max(0, stats.answered),
            label: label,
            showsSeparateAnsweredCount: false
        )
    }
}

/// The finished-lesson numbers the screen is allowed to draw.
///
/// `fraction` is the correct count over the answered total, with `label`
/// under it. `unlabeledLines` is empty: that answered total is not drawn again.
public struct CelebrationResultLayout: Equatable, Sendable {
    public var correctPlan: CounterPlan
    public var answeredTotal: Int
    public var label: String
    public var showsSeparateAnsweredCount: Bool

    public init(
        correctPlan: CounterPlan,
        answeredTotal: Int,
        label: String,
        showsSeparateAnsweredCount: Bool
    ) {
        self.correctPlan = correctPlan
        self.answeredTotal = answeredTotal
        self.label = label
        self.showsSeparateAnsweredCount = showsSeparateAnsweredCount
    }

    /// Final correct count over the answered total, such as `4/6`.
    public var fraction: String {
        "\(correctPlan.spoken)/\(answeredTotal)"
    }

    /// The fraction and its label. Nothing else.
    public var labelledLines: [String] {
        [fraction, label]
    }

    /// Numbers with no label. The answered total is not one of these.
    public var unlabeledLines: [String] {
        showsSeparateAnsweredCount ? ["\(answeredTotal)"] : []
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
