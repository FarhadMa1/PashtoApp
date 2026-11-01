import Testing
@testable import PashtoCore

struct OrderWordsTests {
    @Test func fewerThanTwoTokensReturnsNil() {
        let missing = orderItem("e-none", tokens: nil, pashto: "none")
        let one = orderItem("e-one", tokens: ["one"], pashto: "one")
        let current = quizLesson("l-one", introduce: [missing, one])
        let content = quizBundle([current], items: [missing, one])
        var rng = SplitMix64(seed: 1)
        let context = quizContext(content, seen: ["l-one"])
        #expect(OrderWords.makeTask(for: missing, in: context, using: &rng) == nil)
        #expect(OrderWords.makeTask(for: one, in: context, using: &rng) == nil)
    }

    @Test func punctuationStaysOffTheTilesAndIsFixedAtTheEnd() {
        let question = orderItem(
            "e-ask",
            tokens: ["تاسو", "څنګه", "یاست"],
            pashto: "تاسو څنګه یاست؟"
        )
        let comma = orderItem("e-comma", tokens: ["زه", "ښه"], pashto: "زه ښه،")
        let both = orderItem("e-both", tokens: ["زه", "ښه"], pashto: "زه ښه؟،")
        let marked = orderItem("e-bad", tokens: ["زه؟", "یم"], pashto: "زه؟ یم")
        let current = quizLesson("l-one", introduce: [question, comma, both, marked])
        let content = quizBundle([current], items: [question, comma, both, marked])
        var rng = SplitMix64(seed: 1)
        let context = quizContext(content, seen: ["l-one"])

        let task = OrderWords.makeTask(for: question, in: context, using: &rng)
        #expect(task?.fixedEnding == "؟")
        #expect(task?.tokens.joined(separator: " ") == "تاسو څنګه یاست")
        #expect(task?.tiles.allSatisfy(tileHasNoSentenceMark) == true)

        let commaTask = OrderWords.makeTask(for: comma, in: context, using: &rng)
        #expect(commaTask?.fixedEnding == "،")
        #expect(commaTask?.tiles.allSatisfy(tileHasNoSentenceMark) == true)

        let bothTask = OrderWords.makeTask(for: both, in: context, using: &rng)
        #expect(bothTask?.fixedEnding == "؟،")
        #expect(bothTask?.tokens.joined(separator: " ") == TokenRules.pashtoWithoutFixedEnding(both.pashto))

        #expect(OrderWords.makeTask(for: marked, in: context, using: &rng) == nil)
    }

    @Test func nullAcceptedOrdersAcceptsOnlyTheTokenOrder() {
        let item = orderItem("e-fine", tokens: ["زه", "ښه", "یم"], pashto: "زه ښه یم", acceptedOrders: nil)
        let current = quizLesson("l-one", introduce: [item])
        let content = quizBundle([current], items: [item])
        var rng = SplitMix64(seed: 2)
        let task = OrderWords.makeTask(for: item, in: quizContext(content, seen: ["l-one"]), using: &rng)
        #expect(task?.acceptedOrders == nil)
        #expect(grade(task!, .tokenOrder([0, 1, 2])) == .correct)
        #expect(grade(task!, .tokenOrder([2, 1, 0])) == .incorrect)
        #expect(grade(task!, .tokenOrder(task!.tiles.map(\.index))) == .incorrect)
    }

    @Test func identicalTokensMaySwapAndTheShuffleIsNeverCorrect() {
        let item = orderItem("e-same", tokens: ["aa", "bb", "aa"], pashto: "aa bb aa")
        let current = quizLesson("l-one", introduce: [item])
        let content = quizBundle([current], items: [item])
        let context = quizContext(content, seen: ["l-one"])

        for seed in UInt64(1)...40 {
            var rng = SplitMix64(seed: seed)
            let task = OrderWords.makeTask(for: item, in: context, using: &rng)
            #expect(task != nil)
            #expect(grade(task!, .tokenOrder([0, 1, 2])) == .correct)
            #expect(grade(task!, .tokenOrder([2, 1, 0])) == .correct)
            #expect(grade(task!, .tokenOrder([1, 0, 2])) == .incorrect)
            #expect(grade(task!, .tokenOrder(task!.tiles.map(\.index))) == .incorrect)
        }

        let uniform = orderItem("e-uniform", tokens: ["aa", "aa"], pashto: "aa aa")
        let uniformLesson = quizLesson("l-uniform", introduce: [uniform])
        let uniformBundle = quizBundle([uniformLesson], items: [uniform])
        var uniformRNG = SplitMix64(seed: 1)
        #expect(OrderWords.makeTask(for: uniform, in: quizContext(uniformBundle, seen: ["l-uniform"]), using: &uniformRNG) == nil)
    }

    @Test func acceptedOrderIsCorrectAndTwoTokenSwapIsTheOnlyShuffle() {
        let reversed = orderItem(
            "e-rev",
            tokens: ["aa", "bb", "cc"],
            pashto: "aa bb cc",
            acceptedOrders: [[2, 1, 0]]
        )
        let pair = orderItem("e-pair", tokens: ["aa", "bb"], pashto: "aa bb")
        let bothAccepted = orderItem(
            "e-both",
            tokens: ["aa", "bb"],
            pashto: "aa bb",
            acceptedOrders: [[1, 0]]
        )
        let current = quizLesson("l-one", introduce: [reversed, pair, bothAccepted])
        let content = quizBundle([current], items: [reversed, pair, bothAccepted])
        let context = quizContext(content, seen: ["l-one"])
        var rng = SplitMix64(seed: 3)

        let task = OrderWords.makeTask(for: reversed, in: context, using: &rng)
        #expect(grade(task!, .tokenOrder([0, 1, 2])) == .correct)
        #expect(grade(task!, .tokenOrder([2, 1, 0])) == .correct)
        #expect(grade(task!, .tokenOrder([1, 0, 2])) == .incorrect)
        #expect(grade(task!, .tokenOrder(task!.tiles.map(\.index))) == .incorrect)
        #expect(grade(task!, .choice(itemID("e-rev"))) == .incorrect)

        let swapped = OrderWords.makeTask(for: pair, in: context, using: &rng)
        #expect(swapped?.tiles.map(\.index) == [1, 0])
        #expect(grade(swapped!, .tokenOrder([1, 0])) == .incorrect)
        #expect(grade(swapped!, .tokenOrder([0, 1])) == .correct)

        #expect(OrderWords.makeTask(for: bothAccepted, in: context, using: &rng) == nil)
    }

    @Test func unseenAndUnintroducedItemsReturnNil() {
        let item = orderItem("e-one", tokens: ["aa", "bb"], pashto: "aa bb")
        let current = quizLesson("l-one", introduce: [item])
        let content = quizBundle([current], items: [item])
        var rng = SplitMix64(seed: 1)
        let unseen = quizContext(content, seen: [])
        #expect(OrderWords.makeTask(for: item, in: unseen, using: &rng) == nil)
        let retired = QuizContext(
            bundle: content,
            seenLessonIDs: [lessonID("l-one")],
            retiredItemIDs: [item.id]
        )
        #expect(OrderWords.makeTask(for: item, in: retired, using: &rng) == nil)
    }

    @Test func realPhrasesKeepANullAcceptedOrder() throws {
        let bundle = try loadRepositoryContent()
        let lessons = bundle.units.flatMap(\.lessons)
        var seen: [LessonID] = []
        var tasks: [OrderWordsTask] = []
        var rng = SplitMix64(seed: 7)
        for lesson in lessons {
            seen.append(lesson.id)
            let context = QuizContext(bundle: bundle, seenLessonIDs: seen)
            for item in Distractors.introducedItems(in: lesson.id, bundle: bundle) {
                if let task = OrderWords.makeTask(for: item, in: context, using: &rng) {
                    tasks.append(task)
                }
            }
        }

        #expect(tasks.count == 11)
        for task in tasks {
            let item = try #require(bundle.items.first { $0.id == task.targetID })
            #expect(item.acceptedOrders == nil)
            #expect(task.acceptedOrders == nil)
            #expect(task.tokens.joined(separator: " ") == TokenRules.pashtoWithoutFixedEnding(item.pashto))
            #expect(task.fixedEnding == TokenRules.fixedEnding(of: item.pashto))
            #expect(task.tiles.allSatisfy(tileHasNoSentenceMark))
            #expect(grade(task, .tokenOrder(Array(0..<task.tokens.count))) == .correct)
            #expect(grade(task, .tokenOrder(Array((0..<task.tokens.count).reversed()))) == .incorrect)
            #expect(grade(task, .tokenOrder(task.tiles.map(\.index))) == .incorrect)
        }
    }
}

struct MatchPairsTests {
    @Test func fewerThanThreePairsReturnsNilAndThreeOrFourDoNot() {
        #expect(englishMatch(count: 0) == nil)
        #expect(englishMatch(count: 1) == nil)
        #expect(englishMatch(count: 2) == nil)

        let three = englishMatch(count: 3)
        #expect(three?.pairs.count == 3)
        #expect(three?.mode == .pashtoEnglish)

        let four = englishMatch(count: 4)
        #expect(four?.pairs.count == 4)

        let five = englishMatch(count: 5)
        #expect(five?.pairs.count == 4)
        #expect(five?.pairs.contains { $0.left.itemID.rawValue == "e-1" } == true)
    }

    @Test func pairsDoNotShareEnglishPronunciationOrPashto() {
        let target = quizItem("e-target", pashto: "e\u{0301}", en: "hello", pronunciation: "kha", enAlt: ["Hi"])
        let sameEn = quizItem("e-same-en", en: "HELLO")
        let sameAlt = quizItem("e-same-alt", en: "hi there", enAlt: ["hello"])
        let samePronunciation = quizItem("e-same-pron", en: "fine", pronunciation: "KHA")
        let samePashto = quizItem("e-same-pashto", pashto: "\u{00E9}", en: "other")
        let keptA = quizItem("e-kept-a", en: "yes")
        let keptB = quizItem("e-kept-b", en: "no")
        let items = [target, sameEn, sameAlt, samePronunciation, samePashto, keptA, keptB]
        let current = quizLesson("l-one", introduce: items)
        let content = quizBundle([current], items: items)
        var rng = SplitMix64(seed: 1)
        let task = MatchPairs.pashtoEnglish(
            for: target,
            in: quizContext(content, seen: ["l-one"]),
            using: &rng
        )
        #expect(task?.pairs.map(\.left.itemID.rawValue).sorted() == ["e-kept-a", "e-kept-b", "e-target"])
        #expect(task?.pairs.allSatisfy { $0.left.itemID == $0.right.itemID } == true)
        #expect(task?.pairs.contains { $0.left.itemID == target.id && $0.right.text == "hello" } == true)
    }

    @Test func lettersStayWithLetters() {
        let words = (1...2).map { quizItem("e-w\($0)", en: "word \($0)") }
        let letters = (1...4).map { quizItem("e-l\($0)", en: "letter \($0)", kind: .letter) }
        let current = quizLesson("l-mix", introduce: words, letters: letters)
        let content = quizBundle([current], items: words + letters)
        var rng = SplitMix64(seed: 1)
        let context = quizContext(content, seen: ["l-mix"])
        #expect(MatchPairs.pashtoEnglish(for: words[0], in: context, using: &rng) == nil)

        let letterTask = MatchPairs.pashtoEnglish(for: letters[0], in: context, using: &rng)
        let ids = letterTask?.pairs.map(\.left.itemID.rawValue) ?? []
        #expect(letterTask?.pairs.count == 4)
        #expect(ids.allSatisfy { $0.hasPrefix("e-l") })
        #expect(!ids.contains("e-w1"))
    }

    @Test func sameLessonIsFilledBeforeEarlierLessons() {
        let target = quizItem("e-target", en: "target")
        let sameA = quizItem("e-same-a", en: "same a")
        let sameB = quizItem("e-same-b", en: "same b")
        let earlier = (1...2).map { quizItem("e-earlier-\($0)", en: "earlier \($0)") }
        let older = (1...2).map { quizItem("e-older-\($0)", en: "older \($0)") }
        let olderLesson = quizLesson("l-older", introduce: older)
        let earlierLesson = quizLesson("l-earlier", introduce: earlier)
        let current = quizLesson("l-current", introduce: [target, sameA, sameB])
        let content = quizBundle(
            [olderLesson, earlierLesson, current],
            units: [
                quizUnit("u-old", lessons: [olderLesson]),
                quizUnit("u-mid", lessons: [earlierLesson, current]),
            ],
            items: [target, sameA, sameB] + earlier + older
        )
        let context = quizContext(content, seen: ["l-older", "l-earlier", "l-current"])

        var picked: [String] = []
        for seed in UInt64(1)...30 {
            var rng = SplitMix64(seed: seed)
            let task = MatchPairs.pashtoEnglish(for: target, in: context, using: &rng)
            let ids = Set(task?.pairs.map(\.left.itemID.rawValue) ?? [])
            #expect(ids.contains("e-target"))
            #expect(ids.contains("e-same-a"))
            #expect(ids.contains("e-same-b"))
            #expect(ids.isDisjoint(with: ["e-older-1", "e-older-2"]))
            #expect(ids.count == 4)
            let extra = ids.subtracting(["e-target", "e-same-a", "e-same-b"])
            #expect(extra.count == 1)
            picked.append(extra.first ?? "")
            expectMisaligned(task)
        }
        #expect(Set(picked) == ["e-earlier-1", "e-earlier-2"])
    }

    @Test func matchSetVariesAcrossSeeds() {
        var sets: [Set<String>] = []
        for seed in UInt64(1)...20 {
            let task = englishMatch(count: 6, seed: seed)
            let ids = Set(task?.pairs.map(\.left.itemID.rawValue) ?? [])
            #expect(ids.contains("e-1"))
            #expect(ids.count == 4)
            sets.append(ids)
        }
        #expect(Set(sets).count > 1)
    }

    @Test func soundExamplesDoNotCountAndPlacementLessonsDo() {
        let target = quizItem("e-target", en: "target")
        let partner = quizItem("e-partner", en: "partner")
        let placed = quizItem("e-placed", en: "placed")
        let extra = quizItem("e-extra", en: "extra")
        let onlyExample = quizItem("e-only", en: "only")
        let future = quizItem("e-future", en: "future")
        let sounds = quizLesson("l-sounds", examples: [placed, onlyExample])
        let skipped = quizLesson("l-skip", introduce: [placed, extra])
        let current = quizLesson("l-now", introduce: [target, partner])
        let later = quizLesson("l-future", introduce: [onlyExample, future])
        let content = quizBundle(
            [sounds, skipped, current, later],
            units: [quizUnit("u-one", lessons: [sounds, skipped, current, later])],
            items: [target, partner, placed, extra, onlyExample, future]
        )

        var hidden = SplitMix64(seed: 1)
        let withoutPlacement = quizContext(content, seen: ["l-sounds", "l-now"])
        #expect(MatchPairs.pashtoEnglish(for: target, in: withoutPlacement, using: &hidden) == nil)

        var shown = SplitMix64(seed: 1)
        let withPlacement = quizContext(content, seen: ["l-sounds", "l-skip", "l-now"])
        let task = MatchPairs.pashtoEnglish(for: target, in: withPlacement, using: &shown)
        #expect(task?.pairs.map(\.left.itemID.rawValue).sorted() == ["e-extra", "e-partner", "e-placed", "e-target"])
    }

    @Test func responsePairsNeedThreeAndKeepBothSidesUnique() {
        #expect(responseMatch(count: 2) == nil)

        let three = responseMatch(count: 3)
        #expect(three?.mode == .response)
        #expect(three?.pairs.count == 3)
        #expect(three?.pairs.map(\.left.itemID.rawValue).sorted() == ["e-prompt-1", "e-prompt-2", "e-prompt-3"])
        #expect(three?.pairs.map(\.right.itemID.rawValue).sorted() == ["e-reply-1", "e-reply-2", "e-reply-3"])
        expectMisaligned(three)
        let correct = three!.pairs.map { MatchLink(left: $0.left.itemID, right: $0.right.itemID) }
        #expect(grade(three!, .matches(correct)) == .correct)
        var swapped = correct
        let firstRight = swapped[0].right
        swapped[0] = MatchLink(left: swapped[0].left, right: swapped[1].right)
        swapped[1] = MatchLink(left: swapped[1].left, right: firstRight)
        #expect(grade(three!, .matches(swapped)) == .incorrect)

        let shared = responseMatch(count: 3, sharedPashto: true)
        let ids = shared?.pairs.map(\.right.itemID.rawValue) ?? []
        #expect(shared?.pairs.count == 3)
        #expect(ids.contains("e-reply-1"))
        #expect(!ids.contains("e-reply-shared"))
    }
}

struct DialogResponseTests {
    @Test func oneReplyIsCorrectAndUsageSeparatesTwoReplies() {
        let prompt = quizItem("e-prompt", en: "prompt")
        let formal = quizItem("e-formal", en: "formal reply", usage: "formal", responseTo: "e-prompt")
        let informal = quizItem("e-informal", en: "informal reply", usage: "informal", responseTo: "e-prompt")
        let fillers = (1...3).map { quizItem("e-fill-\($0)", en: "filler \($0)") }
        let letter = quizItem("e-letter", en: "letter", kind: .letter)
        let items = [prompt, formal, informal] + fillers + [letter]
        let current = quizLesson("l-one", introduce: [prompt, formal, informal] + fillers, letters: [letter])
        let content = quizBundle([current], items: items)
        let context = quizContext(content, seen: ["l-one"])
        var rng = SplitMix64(seed: 1)

        let formalTask = DialogResponse().makeTask(for: formal, in: context, using: &rng)
        #expect(formalTask?.kind == .dialogResponse)
        #expect(formalTask?.prompt == prompt.pashto)
        #expect(formalTask?.usage == "formal")
        #expect(formalTask?.targetID == formal.id)
        #expect(formalTask?.options.count == 4)
        #expect(formalTask?.options.filter { $0.itemID == formal.id }.count == 1)
        #expect(formalTask?.options.contains { $0.itemID == informal.id } == false)
        #expect(formalTask?.options.contains { $0.itemID == letter.id } == false)
        #expect(grade(formalTask!, .choice(formal.id)) == .correct)
        let wrong = formalTask!.options.first { $0.itemID != formal.id }
        #expect(grade(formalTask!, .choice(wrong!.itemID)) == .incorrect)

        var second = SplitMix64(seed: 2)
        let informalTask = DialogResponse().makeTask(for: informal, in: context, using: &second)
        #expect(informalTask?.usage == "informal")
        #expect(informalTask?.options.contains { $0.itemID == formal.id } == false)
        #expect(informalTask?.options.filter { $0.itemID == informal.id }.count == 1)

        let clashA = quizItem("e-clash-a", en: "clash a", usage: "formal", responseTo: "e-prompt")
        let clashB = quizItem("e-clash-b", en: "clash b", usage: "FORMAL", responseTo: "e-prompt")
        let clashItems = [prompt, clashA, clashB] + fillers
        let clashLesson = quizLesson("l-clash", introduce: clashItems)
        let clashBundle = quizBundle([clashLesson], items: clashItems)
        var clashRNG = SplitMix64(seed: 1)
        let clashContext = quizContext(clashBundle, seen: ["l-clash"])
        #expect(DialogResponse().makeTask(for: clashA, in: clashContext, using: &clashRNG) == nil)
        #expect(DialogResponse().makeTask(for: clashB, in: clashContext, using: &clashRNG) == nil)
    }

    @Test func distractorsUseSeenContentOfTheSameKind() {
        let prompt = quizItem("e-prompt", en: "prompt", pronunciation: "prompt-sound")
        let reply = quizItem("e-reply", en: "reply", pronunciation: "reply-sound", usage: "the reply", responseTo: "e-prompt")
        let placed = quizItem("e-placed", en: "placed")
        let extra = quizItem("e-extra", en: "extra")
        let onlyExample = quizItem("e-only", en: "only")
        let future = quizItem("e-future", en: "future")
        let letter = quizItem("e-letter", en: "letter", kind: .letter)
        let sounds = quizLesson("l-sounds", examples: [onlyExample])
        let skipped = quizLesson("l-skip", introduce: [placed, extra])
        let current = quizLesson("l-now", introduce: [prompt, reply], letters: [letter])
        let later = quizLesson("l-future", introduce: [onlyExample, future])
        let content = quizBundle(
            [sounds, skipped, current, later],
            units: [quizUnit("u-one", lessons: [sounds, skipped, current, later])],
            items: [prompt, reply, placed, extra, onlyExample, future, letter]
        )

        var hidden = SplitMix64(seed: 1)
        let withoutPlacement = quizContext(content, seen: ["l-sounds", "l-now"])
        #expect(DialogResponse().makeTask(for: reply, in: withoutPlacement, using: &hidden) == nil)

        var shown = SplitMix64(seed: 1)
        let withPlacement = quizContext(content, seen: ["l-sounds", "l-skip", "l-now"])
        let task = DialogResponse().makeTask(for: reply, in: withPlacement, using: &shown)
        let ids = (task?.options ?? []).map { $0.itemID.rawValue }.sorted()
        #expect(ids == ["e-extra", "e-placed", "e-reply"])
        #expect(task?.options.contains { $0.itemID == prompt.id } == false)
        #expect(task?.options.filter { $0.itemID == reply.id }.count == 1)
    }

    @Test func promptLineGroupAndOtherRepliesAreNeverDistractors() {
        let prompt = quizItem("e-prompt", en: "prompt")
        let reply = quizItem("e-reply", en: "reply", usage: "formal", responseTo: "e-prompt")
        let otherReply = quizItem("e-other-reply", en: "other reply", usage: "informal", responseTo: "e-prompt")
        let promptGroup = quizItem("e-prompt-group", en: "prompt group")
        let replyGroup = quizItem("e-reply-group", en: "reply group")
        let fillerA = quizItem("e-fill-a", en: "filler a")
        let fillerB = quizItem("e-fill-b", en: "filler b")
        let items = [prompt, reply, otherReply, promptGroup, replyGroup, fillerA, fillerB]
        let current = quizLesson("l-one", introduce: items)
        let content = quizBundle(
            [current],
            items: items,
            groups: [["e-prompt", "e-prompt-group"], ["e-reply", "e-reply-group"]]
        )
        let context = quizContext(content, seen: ["l-one"])
        for seed in UInt64(1)...24 {
            var rng = SplitMix64(seed: seed)
            let task = DialogResponse().makeTask(for: reply, in: context, using: &rng)
            let ids = (task?.options ?? []).map(\.itemID.rawValue).sorted()
            #expect(ids == ["e-fill-a", "e-fill-b", "e-reply"])
        }
    }

    @Test func aReplyToAnotherLineCanStillBeADistractor() {
        let prompt = quizItem("e-prompt", en: "prompt")
        let reply = quizItem("e-reply", en: "reply", usage: "the reply", responseTo: "e-prompt")
        let otherPrompt = quizItem("e-other-prompt", en: "other prompt")
        let otherReply = quizItem("e-other-reply", en: "other reply", usage: "other", responseTo: "e-other-prompt")
        let filler = quizItem("e-fill", en: "filler")
        let items = [prompt, reply, otherPrompt, otherReply, filler]
        let current = quizLesson("l-one", introduce: items)
        let content = quizBundle([current], items: items)
        var rng = SplitMix64(seed: 1)
        let task = DialogResponse().makeTask(for: reply, in: quizContext(content, seen: ["l-one"]), using: &rng)
        let ids = (task?.options ?? []).map(\.itemID.rawValue).sorted()
        #expect(ids == ["e-fill", "e-other-prompt", "e-other-reply", "e-reply"])
        #expect(task?.options.contains { $0.itemID == prompt.id } == false)
    }
}

struct LessonSessionTests {
    @Test func wrongAnswerComesBackOnceAtTheEndAndAnswersAreStored() throws {
        let first = choiceTask("e-a", "e-b", "e-c")
        let second = choiceTask("e-b", "e-a", "e-c")
        var session = LessonSession(lessonID: lessonID("l-one"), tasks: [
            SessionTask(payload: .choice(first)),
            SessionTask(payload: .choice(second)),
        ])
        var rng = SplitMix64(seed: 1)

        #expect(session.submit(.choice(itemID("e-b")), using: &rng) == .incorrect)
        #expect(session.answers.count == 1)
        #expect(session.answers[0].result == .incorrect)
        #expect(session.answers[0].task.isRepeat == false)
        #expect(session.tasks.map(\.isRepeat) == [false, true])
        let repeated = try #require(session.tasks.last)
        #expect(repeated.isRepeat)
        #expect(sameQuestion(repeated, SessionTask(payload: .choice(first))))
        #expect(presented(repeated) != presented(SessionTask(payload: .choice(first))))

        #expect(session.submit(.choice(itemID("e-b")), using: &rng) == .correct)
        #expect(session.answers.count == 2)
        #expect(session.tasks.count == 1)
        #expect(session.tasks[0].isRepeat == true)

        #expect(session.submit(.choice(itemID("e-b")), using: &rng) == .incorrect)
        #expect(session.tasks.isEmpty)
        #expect(session.answers.count == 3)
        #expect(session.answers[2].task.isRepeat == true)
        #expect(session.answers[2].result == .incorrect)
        #expect(session.submit(.choice(itemID("e-a")), using: &rng) == nil)
    }

    @Test func correctAnswerIsStoredAndNotRepeated() {
        let task = choiceTask("e-a", "e-b", "e-c")
        var session = LessonSession(
            lessonID: lessonID("l-one"),
            tasks: [SessionTask(payload: .choice(task))]
        )
        var rng = SplitMix64(seed: 1)
        #expect(session.submit(.choice(itemID("e-a")), using: &rng) == .correct)
        #expect(session.tasks.isEmpty)
        #expect(session.answers.map(\.result) == [.correct])
    }

    @Test func builderRepeatsTheMissedTaskOnce() throws {
        let items = (1...4).map { quizItem("e-\($0)", en: "word \($0)") }
        let current = quizLesson("l-one", introduce: items)
        let content = quizBundle([current], items: items)
        var rng = SplitMix64(seed: 4)
        var session = LessonSessionBuilder.build(
            for: lessonID("l-one"),
            in: content,
            seenLessonIDs: [lessonID("l-one")],
            using: &rng
        )
        #expect(!session.tasks.isEmpty)
        let missed = session.tasks[0]
        var answerRNG = SplitMix64(seed: 8)
        #expect(session.submit(wrongAnswer(for: missed), using: &answerRNG) == .incorrect)
        let repeated = try #require(session.tasks.last)
        #expect(repeated.isRepeat)
        #expect(sameQuestion(repeated, missed))
        #expect(presented(repeated) != presented(missed))

        var repeats = 0
        while let current = session.current {
            if current.isRepeat {
                repeats += 1
                #expect(session.submit(wrongAnswer(for: current), using: &answerRNG) == .incorrect)
            } else {
                #expect(session.submit(correctAnswer(for: current), using: &answerRNG) == .correct)
            }
        }
        #expect(repeats == 1)
        #expect(session.isComplete)
        #expect(session.answers.count == session.answers.filter { !$0.task.isRepeat }.count + 1)
    }

    @Test func everyOrdinaryLessonYieldsASessionAndSoundsStaysEmpty() throws {
        let bundle = try loadRepositoryContent()
        let lessons = bundle.units.flatMap(\.lessons)
        #expect(lessons.map(\.id.rawValue) == [
            "l-sounds-1",
            "l-greetings-1",
            "l-greetings-2",
            "l-greetings-3",
            "l-introductions-1",
            "l-introductions-2",
            "l-introductions-3",
        ])

        var seen: [LessonID] = []
        var allowed: [ItemID] = []
        for lesson in lessons {
            seen.append(lesson.id)
            allowed.append(contentsOf: Distractors.introducedItems(in: lesson.id, bundle: bundle).map(\.id))
            var rng = SplitMix64(seed: 1)
            let session = LessonSessionBuilder.build(
                for: lesson.id,
                in: bundle,
                seenLessonIDs: seen,
                using: &rng
            )
            let introduced = Distractors.introducedItems(in: lesson.id, bundle: bundle)
            if introduced.isEmpty {
                #expect(session.tasks.isEmpty)
            } else {
                #expect(!session.tasks.isEmpty)
            }
            let allowedIDs = Set(allowed)
            for task in session.tasks {
                #expect(Set(itemIDs(in: task)).isSubset(of: allowedIDs))
            }
        }

        var soundsRNG = SplitMix64(seed: 1)
        let sounds = LessonSessionBuilder.build(
            for: lessonID("l-sounds-1"),
            in: bundle,
            seenLessonIDs: lessons.map(\.id),
            using: &soundsRNG
        )
        // l-sounds-1 only references sound examples. Those items are not seen,
        // and the lesson introduces nothing, so the session is empty.
        #expect(sounds.tasks.isEmpty)
    }

    @Test func realContentProducesOrderAndDialogTasksFromExistingFields() throws {
        let bundle = try loadRepositoryContent()
        let sessions = try courseSessions(bundle, seed: 1)
        let greetings = try #require(sessions.first { $0.lessonID.rawValue == "l-greetings-1" })
        #expect(greetings.tasks.filter { $0.kind == .orderWords }.isEmpty)
        // Both replies share a nonDistractorGroup with the other seen phrases,
        // so fewer than two distractors remain and the questions are skipped.
        #expect(greetings.tasks.filter { $0.kind == .dialogResponse }.isEmpty)
        #expect(greetings.tasks.contains { task in
            guard case .matchPairs(let match) = task.payload else { return false }
            return match.mode == .pashtoEnglish
        })

        let howAreYou = try #require(sessions.first { $0.lessonID.rawValue == "l-greetings-2" })
        #expect(howAreYou.tasks.filter { $0.kind == .orderWords }.count == 2)

        var orderCount = 0
        var dialogCount = 0
        var responseMatchCount = 0
        for session in sessions {
            for task in session.tasks {
                switch task.payload {
                case .orderWords(let order):
                    orderCount += 1
                    #expect(order.acceptedOrders == nil)
                case .choice(let quiz) where quiz.kind == .dialogResponse:
                    dialogCount += 1
                    let reply = try #require(bundle.items.first { $0.id == quiz.targetID })
                    let prompt = try #require(bundle.items.first { $0.id == reply.responseTo })
                    #expect(quiz.prompt == prompt.pashto)
                    #expect(quiz.options.filter { $0.itemID == reply.id }.count == 1)
                    #expect(quiz.options.contains { $0.itemID == prompt.id } == false)
                    let replies = quiz.options.compactMap { option in
                        bundle.items.first { $0.id == option.itemID && $0.responseTo == prompt.id }
                    }
                    #expect(replies.count == 1)
                    let blocked = bundle.nonDistractorGroups.filter { group in
                        group.contains(prompt.id) || group.contains(reply.id)
                    }
                    for option in quiz.options where option.itemID != reply.id {
                        #expect(option.itemID != prompt.id)
                        let item = try #require(bundle.items.first { $0.id == option.itemID })
                        #expect(item.responseTo != prompt.id)
                        for group in blocked {
                            #expect(!group.contains(option.itemID))
                        }
                    }
                    #expect(grade(quiz, .choice(reply.id)) == .correct)
                case .matchPairs(let match) where match.mode == .response:
                    responseMatchCount += 1
                default:
                    break
                }
            }
        }
        #expect(orderCount == 11)
        #expect(dialogCount == 0)
        #expect(responseMatchCount == 0)
    }

    @Test func oneHundredRunsWithAFixedSeedMatch() throws {
        let bundle = try loadRepositoryContent()
        let first = try courseSessions(bundle, seed: 42)
        #expect(first.contains { !$0.tasks.isEmpty })
        for _ in 0..<99 {
            let again = try courseSessions(bundle, seed: 42)
            #expect(again == first)
        }
    }

    @Test func repeatedQuestionIsReshuffledUnlessNoOtherOrderExists() {
        let choice = choiceTask("e-a", "e-b", "e-c")
        for seed in UInt64(1)...30 {
            var session = LessonSession(
                lessonID: lessonID("l-one"),
                tasks: [SessionTask(payload: .choice(choice))]
            )
            var rng = SplitMix64(seed: seed)
            #expect(session.submit(.choice(itemID("e-b")), using: &rng) == .incorrect)
            let repeated = session.tasks[0]
            #expect(repeated.isRepeat)
            #expect(sameQuestion(repeated, SessionTask(payload: .choice(choice))))
            #expect(presented(repeated) != presented(SessionTask(payload: .choice(choice))))
        }

        let pairs = (1...3).map { index in
            MatchPair(
                left: MatchSide(itemID: itemID("e-\(index)"), text: "left-\(index)"),
                right: MatchSide(itemID: itemID("e-\(index)"), text: "right-\(index)")
            )
        }
        let match = MatchPairsTask(mode: .pashtoEnglish, pairs: pairs, rightOrder: [1, 2, 0])
        var matchSession = LessonSession(
            lessonID: lessonID("l-one"),
            tasks: [SessionTask(payload: .matchPairs(match))]
        )
        var matchRNG = SplitMix64(seed: 3)
        #expect(matchSession.submit(.matches([]), using: &matchRNG) == .incorrect)
        guard case .matchPairs(let reshuffledMatch) = matchSession.tasks[0].payload else {
            Issue.record("Missing reshuffled match")
            return
        }
        #expect(reshuffledMatch != match)
        #expect(sameQuestion(
            SessionTask(payload: .matchPairs(reshuffledMatch)),
            SessionTask(payload: .matchPairs(match))
        ))
        #expect(reshuffledMatch.rightOrder != Array(0..<reshuffledMatch.pairs.count))

        let three = OrderWordsTask(
            targetID: itemID("e-three"),
            tiles: [
                WordTile(index: 1, text: "bb"),
                WordTile(index: 0, text: "aa"),
                WordTile(index: 2, text: "cc"),
            ],
            fixedEnding: "",
            tokens: ["aa", "bb", "cc"],
            acceptedOrders: nil
        )
        var orderSession = LessonSession(
            lessonID: lessonID("l-one"),
            tasks: [SessionTask(payload: .orderWords(three))]
        )
        var orderRNG = SplitMix64(seed: 4)
        #expect(orderSession.submit(.tokenOrder(three.tiles.map(\.index)), using: &orderRNG) == .incorrect)
        guard case .orderWords(let reshuffledOrder) = orderSession.tasks[0].payload else {
            Issue.record("Missing reshuffled order")
            return
        }
        #expect(reshuffledOrder.tiles.map(\.index) != three.tiles.map(\.index))
        #expect(grade(reshuffledOrder, .tokenOrder(reshuffledOrder.tiles.map(\.index))) == .incorrect)
        #expect(grade(reshuffledOrder, .tokenOrder([0, 1, 2])) == .correct)

        let pair = OrderWordsTask(
            targetID: itemID("e-pair"),
            tiles: [WordTile(index: 1, text: "bb"), WordTile(index: 0, text: "aa")],
            fixedEnding: "",
            tokens: ["aa", "bb"],
            acceptedOrders: nil
        )
        var pairSession = LessonSession(
            lessonID: lessonID("l-one"),
            tasks: [SessionTask(payload: .orderWords(pair))]
        )
        var pairRNG = SplitMix64(seed: 5)
        #expect(pairSession.submit(.tokenOrder([1, 0]), using: &pairRNG) == .incorrect)
        #expect(pairSession.tasks[0].payload == .orderWords(pair))
    }

    @Test func maxQuestionsCapsTheFirstPassAndStaysDeterministic() {
        let items = (1...4).map { quizItem("e-\($0)", en: "word \($0)") }
        let current = quizLesson("l-one", introduce: items)
        let content = quizBundle([current], items: items)
        let lesson = lessonID("l-one")

        var openRNG = SplitMix64(seed: 11)
        let open = LessonSessionBuilder.build(for: lesson, in: content, seenLessonIDs: [lesson], using: &openRNG)
        var wideRNG = SplitMix64(seed: 11)
        let wide = LessonSessionBuilder.build(
            for: lesson,
            in: content,
            seenLessonIDs: [lesson],
            maxQuestions: 100,
            using: &wideRNG
        )
        #expect(open.tasks.count == 13)
        #expect(wide == open)

        var cappedRNG = SplitMix64(seed: 11)
        let capped = LessonSessionBuilder.build(
            for: lesson,
            in: content,
            seenLessonIDs: [lesson],
            maxQuestions: 4,
            using: &cappedRNG
        )
        var againRNG = SplitMix64(seed: 11)
        let again = LessonSessionBuilder.build(
            for: lesson,
            in: content,
            seenLessonIDs: [lesson],
            maxQuestions: 4,
            using: &againRNG
        )
        #expect(capped.tasks.count == 4)
        #expect(again == capped)
        #expect(Set(capped.tasks.compactMap(anchorID).map(\.rawValue)) == ["e-1", "e-2", "e-3", "e-4"])

        var midRNG = SplitMix64(seed: 11)
        let mid = LessonSessionBuilder.build(
            for: lesson,
            in: content,
            seenLessonIDs: [lesson],
            maxQuestions: 6,
            using: &midRNG
        )
        #expect(mid.tasks.count == 6)
        #expect(Set(mid.tasks.compactMap(anchorID).map(\.rawValue)) == ["e-1", "e-2", "e-3", "e-4"])

        for seed in UInt64(1)...15 {
            var rng = SplitMix64(seed: seed)
            let session = LessonSessionBuilder.build(
                for: lesson,
                in: content,
                seenLessonIDs: [lesson],
                maxQuestions: 4,
                using: &rng
            )
            #expect(session.tasks.count == 4)
            #expect(Set(session.tasks.compactMap(anchorID).map(\.rawValue)) == ["e-1", "e-2", "e-3", "e-4"])

            var tight = SplitMix64(seed: seed)
            let two = LessonSessionBuilder.build(
                for: lesson,
                in: content,
                seenLessonIDs: [lesson],
                maxQuestions: 2,
                using: &tight
            )
            #expect(two.tasks.count == 2)
            let anchors = two.tasks.compactMap(anchorID).map(\.rawValue)
            #expect(anchors.count == 2)
            #expect(anchors[0] != anchors[1])
        }

        var zeroRNG = SplitMix64(seed: 11)
        let empty = LessonSessionBuilder.build(
            for: lesson,
            in: content,
            seenLessonIDs: [lesson],
            maxQuestions: 0,
            using: &zeroRNG
        )
        #expect(empty.tasks.isEmpty)

        var differed = false
        for seed in UInt64(12)...30 {
            var rng = SplitMix64(seed: seed)
            let other = LessonSessionBuilder.build(
                for: lesson,
                in: content,
                seenLessonIDs: [lesson],
                maxQuestions: 4,
                using: &rng
            )
            if other != capped {
                differed = true
            }
        }
        #expect(differed)

        var sessionRNG = SplitMix64(seed: 11)
        var session = LessonSessionBuilder.build(
            for: lesson,
            in: content,
            seenLessonIDs: [lesson],
            maxQuestions: 2,
            using: &sessionRNG
        )
        var answerRNG = SplitMix64(seed: 1)
        let missed = session.tasks[0]
        #expect(session.submit(wrongAnswer(for: missed), using: &answerRNG) == .incorrect)
        #expect(session.tasks.count == 2)
        #expect(session.tasks.filter(\.isRepeat).count == 1)
        #expect(presented(session.tasks[1]) != presented(missed))
        while let current = session.current {
            #expect(session.submit(wrongAnswer(for: current), using: &answerRNG) == .incorrect)
        }
        #expect(session.answers.filter { !$0.task.isRepeat }.count == 2)
        #expect(session.answers.filter(\.task.isRepeat).count == 2)
    }

    @Test func sessionsVaryAcrossSeeds() throws {
        let bundle = try loadRepositoryContent()
        let first = try courseSessions(bundle, seed: 1)
        var differed = false
        for seed in UInt64(2)...10 {
            let other = try courseSessions(bundle, seed: seed)
            if other != first {
                differed = true
            }
        }
        #expect(differed)
    }
}

struct ShuffleTests {
    @Test func fisherYatesPositionIsRoughlyUniform() {
        let values = [0, 1, 2, 3]
        var counts = Array(repeating: Array(repeating: 0, count: 4), count: 4)
        for seed in 1...1000 {
            var rng = SplitMix64(seed: UInt64(seed))
            let order = shuffled(values, using: &rng)
            for (position, value) in order.enumerated() {
                counts[position][value] += 1
            }
        }
        for position in 0..<4 {
            for value in 0..<4 {
                let count = counts[position][value]
                #expect(count > 180 && count < 320)
            }
        }
    }

    @Test func rejectedShuffleDoesNotPreferOneFixedOrder() {
        let identity = [0, 1, 2]
        let allowed = [
            [0, 2, 1],
            [1, 0, 2],
            [1, 2, 0],
            [2, 0, 1],
            [2, 1, 0],
        ]
        var counts = Array(repeating: 0, count: allowed.count)
        for seed in 1...1000 {
            var rng = SplitMix64(seed: UInt64(seed))
            let order = shuffledUntil(identity, using: &rng) { $0 != identity }
            guard let order, let index = allowed.firstIndex(of: order) else {
                Issue.record("Missing allowed order")
                continue
            }
            counts[index] += 1
        }
        for count in counts {
            #expect(count > 140 && count < 270)
        }
    }

    @Test func matchRightColumnIsRoughlyUniform() {
        let allowed = [
            [0, 2, 1],
            [1, 0, 2],
            [1, 2, 0],
            [2, 0, 1],
            [2, 1, 0],
        ]
        var counts = Array(repeating: 0, count: allowed.count)
        for seed in 1...1000 {
            let task = englishMatch(count: 3, seed: UInt64(seed))
            guard let order = task?.rightOrder, let index = allowed.firstIndex(of: order) else {
                Issue.record("Right column was aligned or missing")
                continue
            }
            counts[index] += 1
        }
        for count in counts {
            #expect(count > 140 && count < 270)
        }
    }

    @Test func incorrectWordOrderIsRoughlyUniform() {
        let item = orderItem("e-fine", tokens: ["aa", "bb", "cc"], pashto: "aa bb cc")
        let current = quizLesson("l-one", introduce: [item])
        let content = quizBundle([current], items: [item])
        let context = quizContext(content, seen: ["l-one"])
        let allowed = [
            [0, 2, 1],
            [1, 0, 2],
            [1, 2, 0],
            [2, 0, 1],
            [2, 1, 0],
        ]
        var counts = Array(repeating: 0, count: allowed.count)
        for seed in 1...1000 {
            var rng = SplitMix64(seed: UInt64(seed))
            let task = OrderWords.makeTask(for: item, in: context, using: &rng)
            guard let indexes = task?.tiles.map(\.index), let found = allowed.firstIndex(of: indexes) else {
                Issue.record("Tile order was correct or missing")
                continue
            }
            counts[found] += 1
        }
        for count in counts {
            #expect(count > 140 && count < 270)
        }
    }
}

private func tileHasNoSentenceMark(_ tile: WordTile) -> Bool {
    !tile.text.unicodeScalars.contains(PashtoScript.arabicQuestion)
        && !tile.text.unicodeScalars.contains(PashtoScript.arabicComma)
}

private func orderItem(
    _ id: String,
    tokens: [String]?,
    pashto: String,
    acceptedOrders: [[Int]]? = nil
) -> ContentItem {
    quizItem(id, pashto: pashto, en: id, tokens: tokens, acceptedOrders: acceptedOrders)
}

private func englishMatch(count: Int, seed: UInt64 = 1) -> MatchPairsTask? {
    guard count > 0 else {
        let outsider = quizItem("e-outsider", en: "outside")
        let current = quizLesson("l-empty")
        let content = quizBundle([current], items: [outsider])
        var rng = SplitMix64(seed: seed)
        return MatchPairs.pashtoEnglish(
            for: outsider,
            in: quizContext(content, seen: ["l-empty"]),
            using: &rng
        )
    }
    let items = (1...count).map { quizItem("e-\($0)", en: "word \($0)") }
    let current = quizLesson("l-one", introduce: items)
    let content = quizBundle([current], items: items)
    var rng = SplitMix64(seed: seed)
    return MatchPairs.pashtoEnglish(for: items[0], in: quizContext(content, seen: ["l-one"]), using: &rng)
}

private func responseMatch(count: Int, sharedPashto: Bool = false) -> MatchPairsTask? {
    var items: [ContentItem] = []
    for index in 1...count {
        items.append(quizItem("e-prompt-\(index)", pashto: "prompt-\(index)", en: "prompt \(index)"))
        items.append(quizItem(
            "e-reply-\(index)",
            pashto: "reply-\(index)",
            en: "reply \(index)",
            responseTo: "e-prompt-\(index)"
        ))
    }
    if sharedPashto {
        items.append(quizItem("e-prompt-shared", pashto: "reply-1", en: "prompt shared"))
        items.append(quizItem(
            "e-reply-shared",
            pashto: "reply-shared",
            en: "reply shared",
            responseTo: "e-prompt-shared"
        ))
    }
    let replies = items.filter { $0.responseTo != nil }
    let current = quizLesson("l-one", introduce: items)
    let content = quizBundle([current], items: items)
    var rng = SplitMix64(seed: 1)
    return MatchPairs.response(for: replies[0], in: quizContext(content, seen: ["l-one"]), using: &rng)
}

private func expectMisaligned(_ task: MatchPairsTask?) {
    guard let task else {
        Issue.record("Missing match task")
        return
    }
    #expect(task.rightOrder.count == task.pairs.count)
    #expect(task.rightOrder.sorted() == Array(0..<task.pairs.count))
    if task.pairs.count >= 2 {
        #expect(task.rightOrder != Array(0..<task.pairs.count))
    }
}

private func choiceTask(_ correct: String, _ others: String...) -> QuizTask {
    let options = ([correct] + others).map { QuizOption(itemID: itemID($0), text: $0) }
    return QuizTask(
        kind: .meaningPashtoToEnglish,
        targetID: itemID(correct),
        prompt: correct,
        usage: nil,
        options: options
    )
}

private func quizItem(
    _ id: String,
    pashto: String? = nil,
    en: String,
    kind: ContentKind = .word,
    pronunciation: String? = nil,
    enAlt: [String]? = nil,
    usage: String? = nil,
    responseTo: String? = nil,
    tokens: [String]? = nil,
    acceptedOrders: [[Int]]? = nil
) -> ContentItem {
    makeItem(
        id,
        kind: kind,
        pashto: pashto ?? id,
        translit: "t-\(id)",
        pronunciation: pronunciation ?? "p-\(id)",
        en: en,
        enAlt: enAlt,
        usage: usage,
        responseTo: responseTo,
        tokens: tokens,
        acceptedOrders: acceptedOrders
    )
}

private func quizLesson(
    _ id: String,
    introduce: [ContentItem] = [],
    examples: [ContentItem] = [],
    letters: [ContentItem] = []
) -> Lesson {
    let introduced = introduce.map { LessonItemRef(item: $0.id, role: .introduce) }
    let shown = examples.map { LessonItemRef(item: $0.id, role: .soundExample, sound: "a") }
    return Lesson(
        id: lessonID(id),
        title: id,
        items: introduced + shown,
        letters: letters.map(\.id)
    )
}

private func quizUnit(_ id: String, lessons: [Lesson]) -> CourseUnit {
    CourseUnit(id: unitID(id), track: "main", title: id, lessons: lessons)
}

private func quizBundle(
    _ lessons: [Lesson],
    units: [CourseUnit]? = nil,
    items: [ContentItem],
    groups: [[String]] = []
) -> ContentBundle {
    let resolved = units ?? [quizUnit("u-one", lessons: lessons)]
    return makeBundle(items: items, units: resolved, groups: groups.map { $0.map(itemID) })
}

private func quizContext(_ bundle: ContentBundle, seen: [String], retired: [String] = []) -> QuizContext {
    QuizContext(
        bundle: bundle,
        seenLessonIDs: seen.map(lessonID),
        retiredItemIDs: retired.map(itemID)
    )
}

private func courseSessions(_ bundle: ContentBundle, seed: UInt64) throws -> [LessonSession] {
    var seen: [LessonID] = []
    var sessions: [LessonSession] = []
    var rng = SplitMix64(seed: seed)
    for lesson in bundle.units.flatMap(\.lessons) {
        seen.append(lesson.id)
        sessions.append(LessonSessionBuilder.build(
            for: lesson.id,
            in: bundle,
            seenLessonIDs: seen,
            using: &rng
        ))
    }
    return sessions
}

private func anchorID(_ task: SessionTask) -> ItemID? {
    switch task.payload {
    case .choice(let quiz):
        return quiz.targetID
    case .orderWords(let order):
        return order.targetID
    case .matchPairs:
        return nil
    }
}

private func sameQuestion(_ lhs: SessionTask, _ rhs: SessionTask) -> Bool {
    switch (lhs.payload, rhs.payload) {
    case (.choice(let left), .choice(let right)):
        return left.kind == right.kind
            && left.targetID == right.targetID
            && left.prompt == right.prompt
            && left.options.map(\.itemID.rawValue).sorted() == right.options.map(\.itemID.rawValue).sorted()
    case (.matchPairs(let left), .matchPairs(let right)):
        return left.mode == right.mode
            && left.pairs.map(\.left.itemID.rawValue).sorted() == right.pairs.map(\.left.itemID.rawValue).sorted()
    case (.orderWords(let left), .orderWords(let right)):
        return left.targetID == right.targetID && left.tokens == right.tokens
    default:
        return false
    }
}

private func presented(_ task: SessionTask) -> [String] {
    switch task.payload {
    case .choice(let quiz):
        return quiz.options.map(\.itemID.rawValue)
    case .matchPairs(let match):
        return match.pairs.map(\.left.itemID.rawValue) + ["|"] + match.rightColumn.map(\.itemID.rawValue)
    case .orderWords(let order):
        return order.tiles.map { "\($0.index)" }
    }
}

private func itemIDs(in task: SessionTask) -> [ItemID] {
    switch task.payload {
    case .choice(let quiz):
        return quiz.options.map(\.itemID)
    case .matchPairs(let match):
        return match.pairs.flatMap { [$0.left.itemID, $0.right.itemID] }
    case .orderWords(let order):
        return [order.targetID]
    }
}

private func correctAnswer(for task: SessionTask) -> QuizAnswer {
    switch task.payload {
    case .choice(let quiz):
        return .choice(quiz.targetID)
    case .matchPairs(let match):
        return .matches(match.pairs.map { MatchLink(left: $0.left.itemID, right: $0.right.itemID) })
    case .orderWords(let order):
        return .tokenOrder(Array(0..<order.tokens.count))
    }
}

private func wrongAnswer(for task: SessionTask) -> QuizAnswer {
    switch task.payload {
    case .choice(let quiz):
        let wrong = quiz.options.first { $0.itemID != quiz.targetID }?.itemID ?? quiz.targetID
        return .choice(wrong)
    case .matchPairs(let match):
        var links = match.pairs.map { MatchLink(left: $0.left.itemID, right: $0.right.itemID) }
        if links.count >= 2 {
            let firstRight = links[0].right
            links[0] = MatchLink(left: links[0].left, right: links[1].right)
            links[1] = MatchLink(left: links[1].left, right: firstRight)
        }
        return .matches(links)
    case .orderWords(let order):
        return .tokenOrder(order.tiles.map(\.index))
    }
}
