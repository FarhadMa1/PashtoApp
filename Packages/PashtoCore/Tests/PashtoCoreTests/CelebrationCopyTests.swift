import Foundation
import Testing
@testable import PashtoCore

struct CelebrationCopyTests {
    @Test func wordCountFollowsTheCount() {
        #expect(CelebrationCopy.wordCount(1) == "1 word")
        #expect(CelebrationCopy.wordCount(2) == "2 words")
        #expect(CelebrationCopy.wordCount(0) == "0 words")
        #expect(CelebrationCopy.wordCount(10) == "10 words")
    }

    @Test func dailyGoalCountsNewWordsAgainstTheStoredLimit() {
        #expect(CelebrationCopy.dailyGoalSpoken(done: 6, goal: 10) == "Daily goal: 6 of 10 words, 4 to go")
        #expect(CelebrationCopy.dailyGoalSpoken(done: 1, goal: 10) == "Daily goal: 1 of 10 words, 9 to go")
        #expect(CelebrationCopy.dailyGoalSpoken(done: 1, goal: 1) == "Daily goal: 1 of 1 word, Goal reached")
        #expect(CelebrationCopy.dailyGoalSpoken(done: 0, goal: 5) == "Daily goal: 0 of 5 words, 5 to go")
        #expect(CelebrationCopy.dailyGoalSpoken(done: 4, goal: 5) == "Daily goal: 4 of 5 words, 1 to go")
        #expect(CelebrationCopy.dailyGoalSpoken(done: 5, goal: 5) == "Daily goal: 5 of 5 words, Goal reached")
        #expect(CelebrationCopy.dailyGoalSpoken(done: 10, goal: 10) == "Daily goal: 10 of 10 words, Goal reached")
        #expect(CelebrationCopy.dailyGoalSpoken(done: 14, goal: 15) == "Daily goal: 14 of 15 words, 1 to go")
        #expect(CelebrationCopy.dailyGoalSpoken(done: 15, goal: 15) == "Daily goal: 15 of 15 words, Goal reached")
        #expect(CelebrationCopy.dailyGoalSpoken(done: 16, goal: 15) == "Daily goal: 16 of 15 words, Goal reached")
        #expect(CelebrationCopy.dailyGoalSpoken(done: 1, goal: 0) == "Daily goal: 1 of 0 words")
        #expect(CelebrationCopy.dailyGoalSpoken(done: -3, goal: 10) == "Daily goal: 0 of 10 words, 10 to go")

        let correctAnswers = LessonFinishStats(answered: 6, correct: 4)
        let speech = CelebrationCopy.accessibleResult(
            stats: correctAnswers,
            praise: .kha,
            showsPronunciation: true,
            reduceMotion: true,
            voiceOver: true
        )
        #expect(!speech.contains("word"))
        #expect(!speech.contains("6"))
    }

    @Test func streakKeepsTheApprovedLabelForEveryCount() {
        #expect(CelebrationCopy.streakSpoken(0) == "0 day streak")
        #expect(CelebrationCopy.streakSpoken(1) == "1 day streak")
        #expect(CelebrationCopy.streakSpoken(2) == "2 day streak")
        #expect(CelebrationCopy.streakSpoken(-4) == "0 day streak")
        #expect(!CelebrationCopy.streakSpoken(2).contains("days"))
    }

    @Test func praiseIsOnlyTheTwoApprovedLinesAndStaysWithItsPronunciation() {
        #expect(LessonPraise.allCases.map(\.pashto) == ["ښه", "ډېره ښه"])
        #expect(LessonPraise.allCases.map(\.pronunciation) == ["kha", "DE-ra kha"])
        #expect(LessonPraise.kha.pashto == "ښه")
        #expect(LessonPraise.deraKha.pashto == "ډېره ښه")
        for praise in LessonPraise.allCases {
            #expect(praise.pashto != "شاباس")
            #expect(praise.pashto != "آفرین")
            #expect(!praise.pashto.contains("شاباس"))
            #expect(!praise.pashto.contains("آفرین"))
        }

        let home = lessonID("l-a")
        let other = lessonID("l-b")
        #expect(LessonPraise.select(lessonID: home) == .kha)
        #expect(LessonPraise.select(lessonID: other) == .deraKha)
        #expect(LessonPraise.select(lessonID: home) == LessonPraise.select(lessonID: home))
        #expect(UserSettings.initial.showTransliteration == true)
    }

    @Test func accessibleResultIsFinalForVoiceOverAndReduceMotion() {
        let stats = LessonFinishStats(answered: 6, correct: 4)
        let modes = [(false, false), (true, false), (false, true), (true, true)]
        let withPronunciation = modes.map { reduce, voice in
            CelebrationCopy.accessibleResult(
                stats: stats,
                praise: .kha,
                showsPronunciation: true,
                reduceMotion: reduce,
                voiceOver: voice
            )
        }
        #expect(withPronunciation.allSatisfy { $0 == "Lesson complete, ښه, kha, 4 correct" })

        let hidden = CelebrationCopy.accessibleResult(
            stats: stats,
            praise: .deraKha,
            showsPronunciation: false,
            reduceMotion: true,
            voiceOver: true
        )
        #expect(hidden == "Lesson complete, ډېره ښه, 4 correct")
        #expect(!hidden.contains("DE-ra kha"))

        let one = CelebrationCopy.accessibleResult(
            stats: LessonFinishStats(answered: 6, correct: 1),
            praise: .kha,
            showsPronunciation: false,
            reduceMotion: false,
            voiceOver: true
        )
        #expect(one == "Lesson complete, ښه, 1 correct")
        #expect(!one.contains("word"))
        #expect(!one.contains("6"))

        for (reduce, voice) in [(true, false), (false, true), (true, true)] {
            let correct = CounterPlan.plan(target: 4, reduceMotion: reduce, voiceOver: voice, skipped: false)
            let answered = CounterPlan.plan(target: 6, reduceMotion: reduce, voiceOver: voice, skipped: false)
            #expect(correct.start == 4)
            #expect(correct.end == 4)
            #expect(correct.spoken == 4)
            #expect(correct.animates == false)
            #expect(answered.start == 6)
            #expect(answered.spoken == 6)
            #expect(answered.animates == false)
        }

        let moving = CounterPlan.plan(target: 4, reduceMotion: false, voiceOver: false, skipped: false)
        #expect(Array(moving.start...moving.end) == [0, 1, 2, 3, 4])
        #expect(moving.spoken == 4)
        let speech = withPronunciation[0]
        for step in moving.start..<moving.end {
            #expect(!speech.contains("\(step) correct"))
        }
        #expect(speech.contains("4 correct"))
    }

    @Test func theLabelledFractionIsTheOnlyAnsweredTotal() {
        let stats = LessonFinishStats(answered: 6, correct: 4)
        let modes = [(false, false), (true, false), (false, true), (true, true)]
        for (reduce, voice) in modes {
            let layout = CelebrationCopy.resultLayout(
                stats: stats,
                reduceMotion: reduce,
                voiceOver: voice
            )
            #expect(layout.fraction == "4/6")
            #expect(layout.label == "correct")
            #expect(layout.labelledLines == ["4/6", "correct"])
            #expect(layout.showsSeparateAnsweredCount == false)
            #expect(layout.unlabeledLines.isEmpty)
            #expect(layout.correctPlan.spoken == 4)
            #expect(layout.answeredTotal == 6)

            let speech = CelebrationCopy.accessibleResult(
                stats: stats,
                praise: .kha,
                showsPronunciation: true,
                reduceMotion: reduce,
                voiceOver: voice
            )
            #expect(speech == "Lesson complete, ښه, kha, 4 correct")
            #expect(!speech.contains("6"))
            #expect(speech.split(separator: " ").filter { $0 == "6" }.isEmpty)
        }

        let quiet = CelebrationCopy.resultLayout(
            stats: stats,
            reduceMotion: true,
            voiceOver: true
        )
        #expect(quiet.correctPlan.start == 4)
        #expect(quiet.correctPlan.animates == false)
        let read = CelebrationCopy.resultLayout(
            stats: stats,
            reduceMotion: false,
            voiceOver: true
        )
        #expect(read.correctPlan.start == read.correctPlan.spoken)
        #expect(read.fraction == "4/6")

        let tied = LessonFinishStats(answered: 6, correct: 6)
        let tiedLayout = CelebrationCopy.resultLayout(
            stats: tied,
            reduceMotion: false,
            voiceOver: true
        )
        #expect(tiedLayout.fraction == "6/6")
        #expect(tiedLayout.unlabeledLines.isEmpty)
        let tiedSpeech = CelebrationCopy.accessibleResult(
            stats: tied,
            praise: .kha,
            showsPronunciation: false,
            reduceMotion: true,
            voiceOver: true
        )
        #expect(tiedSpeech == "Lesson complete, ښه, 6 correct")
        #expect(!tiedSpeech.contains("6/6"))
    }

    @Test func coursePathUsesNowAndLockedAndNotQuizCorrect() {
        let first = lessonID("l-a")
        let current = lessonID("l-b")
        let later = lessonID("l-c")
        let order = [first, current, later]
        let finished: Set<LessonID> = [first]
        let locked: Set<LessonID> = [later, first]

        #expect(CoursePathCopy.mark(id: first, order: order, finished: finished, locked: locked) == .plain)
        #expect(CoursePathCopy.mark(id: current, order: order, finished: finished, locked: locked) == .now)
        #expect(CoursePathCopy.mark(id: later, order: order, finished: finished, locked: locked) == .locked)
        #expect(CoursePathCopy.mark(id: later, order: order, finished: finished, locked: []) == .plain)

        #expect(CoursePathCopy.accessibilityLabel(title: "Hello", mark: .plain) == "Hello")
        #expect(CoursePathCopy.accessibilityLabel(title: "Hello", mark: .now) == "Hello, Now")
        #expect(CoursePathCopy.accessibilityLabel(title: "Hello", mark: .locked) == "Hello, Locked")
        for mark in [CoursePathCopy.Mark.plain, .now, .locked] {
            let label = CoursePathCopy.accessibilityLabel(title: "Hello", mark: mark)
            #expect(!label.contains("Correct"))
            #expect(label != "Hello, correct")
        }
        #expect(QuizResultMark.correct.spokenEnglish == "Correct")
        #expect(CoursePathCopy.now != QuizResultMark.correct.spokenEnglish)
        #expect(CoursePathCopy.locked != QuizResultMark.correct.spokenEnglish)
    }

    @Test func nowUsesBodyTextAndClearsNormalContrastOnTheDarkPage() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let lapis = try String(contentsOf: root.appendingPathComponent("PashtoApp/Design/LapisStyle.swift"), encoding: .utf8)
        let screen = try String(contentsOf: root.appendingPathComponent("PashtoApp/ContentView.swift"), encoding: .utf8)
        let textDark = try dynamicHex("text", dark: true, in: lapis)
        let pageDark = try dynamicHex("background", dark: true, in: lapis)
        #expect(textDark == 0xF1F5F9)
        #expect(pageDark == QuizResultPalette.pageDark)
        #expect(pageDark == 0x0F172A)
        #expect(textDark != QuizResultPalette.badgeDark)
        #expect(QuizResultPalette.badgeDark == 0x4666D2)
        let ratio = QuizResultPalette.contrastRatio(foreground: textDark, background: pageDark)
        #expect(ratio >= 4.5)

        let now = try #require(screen.range(of: "ApprovedCopy.now"))
        let caption = screen[now.lowerBound...].prefix(180)
        #expect(caption.contains("foregroundStyle(Lapis.text)"))
        #expect(!caption.contains("Lapis.badge"))
    }

    @Test func catalogMatchesTheApprovedEnglish() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PashtoApp/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("شاباس"))
        #expect(!text.contains("آفرین"))
        #expect(try catalogValue("celebration.lessonComplete", in: data) == CelebrationCopy.lessonComplete)
        #expect(try catalogValue("celebration.correct", in: data) == CelebrationCopy.correct)
        #expect(try catalogValue("celebration.dayStreak", in: data) == CelebrationCopy.dayStreak)
        #expect(try catalogValue("celebration.streakFreezeEarned", in: data) == CelebrationCopy.streakFreezeEarned)
        #expect(try catalogValue("today.wordOfTheDay", in: data) == DailyWordCopy.title)
        #expect(try catalogValue("today.showMeaning", in: data) == DailyWordCopy.showMeaning)
        #expect(try catalogValue("celebration.dailyGoal", in: data) == CelebrationCopy.dailyGoal)
        #expect(try catalogValue("celebration.toGo", in: data) == CelebrationCopy.toGo)
        #expect(try catalogValue("celebration.goalReached", in: data) == CelebrationCopy.goalReached)
        #expect(try catalogValue("celebration.word.one", in: data) == CelebrationCopy.wordOne)
        #expect(try catalogValue("celebration.word.other", in: data) == CelebrationCopy.wordOther)
        #expect(try catalogValue("path.now", in: data) == CoursePathCopy.now)
        #expect(try catalogValue("path.locked", in: data) == CoursePathCopy.locked)
        #expect(try catalogValue("quiz.feedback.correct", in: data) == "Correct")
    }

    private func dynamicHex(_ name: String, dark: Bool, in source: String) throws -> UInt32 {
        let line = try #require(source.split(separator: "\n").first {
            $0.contains("static let \(name) = dynamic(")
        })
        let key = dark ? "dark: 0x" : "light: 0x"
        let rest = try #require(line.split(separator: key).dropFirst().first)
        let digits = rest.prefix { $0.isHexDigit }
        return try #require(UInt32(digits, radix: 16))
    }

    private func catalogValue(_ key: String, in data: Data) throws -> String {
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        let entry = try #require(strings[key] as? [String: Any])
        let localizations = try #require(entry["localizations"] as? [String: Any])
        let english = try #require(localizations["en"] as? [String: Any])
        let unit = try #require(english["stringUnit"] as? [String: Any])
        return try #require(unit["value"] as? String)
    }
}
