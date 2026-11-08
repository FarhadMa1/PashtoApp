import Foundation
import Testing
@testable import PashtoCore

struct QuizMotionTests {
    @Test func feedbackDurationsStayInsideTheApprovedRange() {
        let feedback: [TimeInterval] = [
            QuizMotion.answerPop,
            QuizMotion.checkFade,
            QuizMotion.answerShake,
            QuizMotion.progressSpring,
            QuizMotion.progressGlow,
            QuizMotion.glyphReveal,
            QuizMotion.cardFlip,
            QuizMotion.pairGlide,
            QuizMotion.pairMerge,
            QuizMotion.pairFadeOut,
            QuizMotion.reduceMotionFade,
            QuizMotion.questionSpring,
        ]
        for duration in feedback {
            #expect(duration >= 0.15)
            #expect(duration <= 0.4)
        }
        #expect(QuizMotion.answerPop == 0.25)
        #expect(QuizMotion.answerShake == 0.35)
        #expect(QuizMotion.progressSpring == 0.4)
        #expect(QuizMotion.glyphReveal == 0.35)
        #expect(QuizMotion.cardFlip == 0.4)
        #expect(QuizMotion.pairGlide == 0.2)
        #expect(QuizMotion.pairMerge == 0.4)
        #expect(QuizMotion.pairFadeOut == 0.25)
        #expect(QuizMotion.reduceMotionFade == 0.2)
        #expect(QuizMotion.checkFade == 0.2)
        #expect(QuizMotion.questionSpring == 0.28)
        #expect(QuizMotion.questionSpringDamping == 0.86)
    }

    @Test func nextQuestionSlidesFromTheRightAndDoesNotBlockInput() {
        #expect(QuestionChange.style(reduceMotion: false) == .slideFromRight)
        #expect(QuestionChange.style(reduceMotion: true) == .crossfade)
        #expect(QuestionChange.duration(reduceMotion: false) == 0.28)
        #expect(QuestionChange.duration(reduceMotion: true) == QuizMotion.reduceMotionFade)
        #expect(QuestionChange.blocksInput == false)

        let first = QuestionIdentity(answerCount: 0, isRepeat: false)
        let answered = QuestionIdentity(answerCount: 0, isRepeat: false)
        let next = QuestionIdentity(answerCount: 1, isRepeat: false)
        let repeated = QuestionIdentity(answerCount: 1, isRepeat: true)
        #expect(first == answered)
        #expect(first != next)
        #expect(next != repeated)

        var seen: Set<QuestionIdentity> = []
        for count in 0..<6 {
            let identity = QuestionIdentity(answerCount: count, isRepeat: false)
            #expect(seen.insert(identity).inserted)
            #expect(QuestionIdentity(answerCount: count, isRepeat: false) == identity)
        }
    }

    @Test func popPeaksThenReturnsAndStaysAtOneOtherwise() {
        #expect(QuizMotion.answerPopPeakScale == 1.04)
        #expect(AnswerMotion.scales(for: .pop) == [1, 1.04, 1])
        #expect(AnswerMotion.scales(for: .shake) == [1])
        #expect(AnswerMotion.scales(for: .fade) == [1])
        #expect(AnswerMotion.scales(for: .none) == [1])
        #expect(QuizMotion.glyphStartScale == 0.92)
        #expect(QuizMotion.glyphStartScale < 1)
        #expect(GlyphReveal.fadeAndScale.startScale == 0.92)
        #expect(GlyphReveal.fade.startScale == 1)
    }

    @Test func choiceMotionFollowsTheMarkAndReduceMotion() {
        #expect(AnswerMotion.choice(.correct, reduceMotion: false) == .pop)
        #expect(AnswerMotion.choice(.correct, reduceMotion: true) == .fade)
        #expect(AnswerMotion.choice(.incorrect, reduceMotion: false) == .shake)
        #expect(AnswerMotion.choice(.incorrect, reduceMotion: true) == .fade)
        #expect(AnswerMotion.choice(nil, reduceMotion: false) == .none)
        #expect(AnswerMotion.choice(nil, reduceMotion: true) == .none)
    }

    @Test func shakeIsThreeOscillationsOfSixPoints() {
        #expect(AnswerShake.positivePeaks == QuizMotion.shakeOscillations)
        #expect(AnswerShake.negativePeaks == QuizMotion.shakeOscillations)
        #expect(AnswerShake.samples.first?.offset == 0)
        #expect(AnswerShake.samples.last?.offset == 0)
        #expect(AnswerShake.samples.first?.fraction == 0)
        #expect(AnswerShake.samples.last?.fraction == 1)
        var previous = -0.01
        for sample in AnswerShake.samples {
            #expect(sample.fraction > previous)
            #expect(abs(sample.offset) <= QuizMotion.shakeAmplitude)
            previous = sample.fraction
        }
        let segments = AnswerShake.segments
        #expect(segments.count == 7)
        let total = segments.reduce(0) { $0 + $1.duration }
        #expect(abs(total - QuizMotion.answerShake) < 0.000_001)
        #expect(segments.map(\.offset) == [-6, 6, -6, 6, -6, 6, 0])
    }

    @Test func progressJumpsForReduceMotionAndGlowsOnlyWhenFull() {
        #expect(ProgressAdvance.style(reduceMotion: false) == .spring)
        #expect(ProgressAdvance.style(reduceMotion: true) == .jump)
        #expect(QuizMotion.playsGlow(barIsFull: true, reduceMotion: false))
        #expect(!QuizMotion.playsGlow(barIsFull: true, reduceMotion: true))
        #expect(!QuizMotion.playsGlow(barIsFull: false, reduceMotion: false))
    }

    @Test func lessonBarCountsTheOpenAnswerAndAQueuedRepeat() {
        let fresh = LessonBar.measure(submitted: 0, remaining: 10, revealed: nil, currentIsRepeat: false)
        #expect(fresh.answered == 0)
        #expect(fresh.total == 10)
        #expect(fresh.fraction == 0)
        #expect(!fresh.showsGlow)

        let correct = LessonBar.measure(submitted: 3, remaining: 7, revealed: .correct, currentIsRepeat: false)
        #expect(correct.answered == 4)
        #expect(correct.total == 10)
        #expect(abs(correct.fraction - 0.4) < 0.000_001)

        let wrong = LessonBar.measure(submitted: 9, remaining: 1, revealed: .incorrect, currentIsRepeat: false)
        #expect(wrong.answered == 10)
        #expect(wrong.total == 11)
        #expect(!wrong.showsGlow)

        let askedAgain = LessonBar.measure(submitted: 10, remaining: 1, revealed: .correct, currentIsRepeat: true)
        #expect(askedAgain.answered == 11)
        #expect(askedAgain.total == 11)
        #expect(askedAgain.showsGlow)
        #expect(askedAgain.fraction == 1)

        let finished = LessonBar.measure(submitted: 9, remaining: 1, revealed: .correct, currentIsRepeat: false)
        #expect(finished.showsGlow)

        let empty = LessonBar.measure(submitted: 0, remaining: 0, revealed: nil, currentIsRepeat: false)
        #expect(empty.fraction == 0)
        #expect(!empty.showsGlow)

        let clamped = LessonBar.measure(submitted: -2, remaining: -1, revealed: .correct, currentIsRepeat: false)
        #expect(clamped.answered == 0)
        #expect(clamped.total == 0)
    }

    @Test func glyphAndFlipDropMovementForReduceMotion() {
        #expect(GlyphReveal.style(reduceMotion: false) == .fadeAndScale)
        #expect(GlyphReveal.style(reduceMotion: true) == .fade)
        #expect(CardFlip.style(reduceMotion: false) == .rotation)
        #expect(CardFlip.style(reduceMotion: true) == .fade)
    }

    @Test func glyphCardKeepsPronunciationAndHidesTheUnansweredGloss() {
        let hidden = GlyphCardModel.make(
            glyph: "سلام",
            pronunciation: "sa-LAAM",
            meaning: "hello",
            kind: .meaningPashtoToEnglish,
            answered: false
        )
        #expect(hidden.front.pronunciation == "sa-LAAM")
        #expect(hidden.front.meaning == nil)
        #expect(hidden.back.meaning == nil)
        #expect(hidden.back.pronunciation == "sa-LAAM")
        #expect(!hidden.canFlip)

        let shown = GlyphCardModel.make(
            glyph: "سلام",
            pronunciation: "sa-LAAM",
            meaning: "hello",
            kind: .meaningPashtoToEnglish,
            answered: true
        )
        #expect(shown.front.meaning == nil)
        #expect(shown.back.meaning == "hello")
        #expect(shown.back.pronunciation == "sa-LAAM")
        #expect(shown.canFlip)

        let other = GlyphCardModel.make(
            glyph: "سلام",
            pronunciation: nil,
            meaning: "hello",
            kind: .dialogResponse,
            answered: false
        )
        #expect(other.front.pronunciation == nil)
        #expect(other.back.pronunciation == nil)
        #expect(other.back.meaning == nil)
        #expect(!other.canFlip)

        let otherAnswered = GlyphCardModel.make(
            glyph: "سلام",
            pronunciation: nil,
            meaning: "hello",
            kind: .dialogResponse,
            answered: true
        )
        #expect(otherAnswered.back.meaning == "hello")
        #expect(otherAnswered.canFlip)

        let blank = GlyphCardModel.make(
            glyph: "ا",
            pronunciation: "   ",
            meaning: " ",
            kind: .firstLetter,
            answered: false
        )
        #expect(blank.front.pronunciation == nil)
        #expect(blank.back.meaning == nil)
        #expect(!blank.canFlip)

        let letter = GlyphCardModel.make(
            glyph: "مننه",
            pronunciation: "ma-NA-na",
            meaning: "thank you",
            kind: .firstLetter,
            answered: false
        )
        #expect(letter.back.meaning == nil)
        #expect(letter.back.pronunciation == "ma-NA-na")
        #expect(!letter.canFlip)

        let letterAnswered = GlyphCardModel.make(
            glyph: "مننه",
            pronunciation: "ma-NA-na",
            meaning: "thank you",
            kind: .firstLetter,
            answered: true
        )
        #expect(letterAnswered.back.meaning == "thank you")
        #expect(letterAnswered.back.pronunciation == "ma-NA-na")
        #expect(letterAnswered.canFlip)
    }

    @Test func aSpaceKeepsThePromptAtTitleSize() {
        #expect(GlyphPromptScaleChoice.scale(for: "ا") == .prominent)
        #expect(GlyphPromptScaleChoice.scale(for: "سلام") == .prominent)
        #expect(GlyphPromptScaleChoice.scale(for: "مننه") == .prominent)
        #expect(GlyphPromptScaleChoice.scale(for: "") == .prominent)
        #expect(GlyphPromptScaleChoice.scale(for: "ستاسو په لیدو خوشحاله شوم") == .title)
        #expect(GlyphPromptScaleChoice.scale(for: "hello world") == .title)
        #expect(GlyphPromptScaleChoice.scale(for: " ") == .title)
    }

    @Test func pairsGlideThenMergeAndWrongPairsStayMarked() {
        let correct = PairMergePlan.frames(mark: .correct, reduceMotion: false)
        #expect(correct.map(\.step) == [.glide, .merged, .gone])
        #expect(correct.map(\.time).elementsEqual([0, 0.2, 0.6]) { abs($0 - $1) < 0.000_001 })

        let quietCorrect = PairMergePlan.frames(mark: .correct, reduceMotion: true)
        #expect(quietCorrect.map(\.step) == [.fade, .gone])
        #expect(!quietCorrect.map(\.step).contains(.glide))
        #expect(quietCorrect.map(\.time) == [0, QuizMotion.reduceMotionFade])

        let wrong = PairMergePlan.frames(mark: .incorrect, reduceMotion: false)
        #expect(wrong.map(\.step) == [.shake, .hold])
        #expect(wrong.map(\.time) == [0, QuizMotion.answerShake])

        let quietWrong = PairMergePlan.frames(mark: .incorrect, reduceMotion: true)
        #expect(quietWrong.map(\.step) == [.fade, .hold])
        #expect(!quietWrong.map(\.step).contains(.shake))
        #expect(!quietWrong.map(\.step).contains(.glide))
    }

    @Test @MainActor func pairClockPlaysTheMergeThenTheShake() async {
        let hello = ItemID(rawValue: "e-hello")
        let thanks = ItemID(rawValue: "e-thanks")
        #expect(hello != nil)
        #expect(thanks != nil)
        guard let hello, let thanks else { return }

        let correct = PairMergeClock(sleep: { _ in })
        correct.play(events: [(id: hello, mark: .correct)], reduceMotion: false)
        #expect(correct.steps[hello] == .glide)
        #expect(correct.shakeToken == 0)
        await correct.waitUntilIdle()
        #expect(correct.played.map(\.step) == [.glide, .merged, .gone])
        #expect(correct.played.map(\.time).elementsEqual(
            [0, QuizMotion.pairGlide, QuizMotion.pairGlide + QuizMotion.pairMerge]
        ) { abs($0 - $1) < 0.000_001 })
        #expect(correct.steps[hello] == .gone)

        let wrong = PairMergeClock(sleep: { _ in })
        wrong.play(events: [(id: thanks, mark: .incorrect)], reduceMotion: false)
        await wrong.waitUntilIdle()
        #expect(wrong.played.map(\.step) == [.shake, .hold])
        #expect(wrong.played.map(\.time).elementsEqual([0, QuizMotion.answerShake]) { abs($0 - $1) < 0.000_001 })
        #expect(wrong.shakeToken == 1)
        #expect(wrong.steps[thanks] == .hold)

        let quiet = PairMergeClock(sleep: { _ in })
        quiet.play(
            events: [(id: thanks, mark: .incorrect), (id: hello, mark: .correct)],
            reduceMotion: true
        )
        await quiet.waitUntilIdle()
        #expect(quiet.shakeToken == 0)
        #expect(quiet.played.map(\.step) == [.fade, .fade, .gone, .hold])
        #expect(quiet.played.map(\.id) == [thanks, hello, hello, thanks])
        #expect(!quiet.played.map(\.step).contains(.glide))
        #expect(!quiet.played.map(\.step).contains(.shake))

        let stopped = PairMergeClock { _ in
            try? await Task.sleep(for: .seconds(30))
        }
        stopped.play(events: [(id: hello, mark: .correct)], reduceMotion: false)
        stopped.stop()
        #expect(stopped.steps.isEmpty)
        #expect(stopped.played.isEmpty)
        await stopped.waitUntilIdle()
        #expect(stopped.steps.isEmpty)
    }
}
