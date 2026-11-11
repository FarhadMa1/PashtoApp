import Foundation
import Testing
@testable import PashtoCore

struct MultipleChoiceTests {
    @Test func distractorCandidatesFollowSourceOrder() {
        let sameA = word("e-same-a", "1", "same a")
        let sameB = word("e-same-b", "2", "same b")
        let target = word("e-target", "3", "target")
        let letter = word("e-letter", "4", "letter", kind: .letter)
        let near = word("e-near", "5", "near lesson")
        let far = word("e-far", "6", "far lesson")
        let earlyA = word("e-early-a", "7", "early a")
        let earlyB = word("e-early-b", "8", "early b")
        let future = word("e-future", "9", "future")
        let exampleOnly = word("e-example", "10", "example only")

        let earlyLesson = lesson("l-early", introduce: [earlyA, earlyB])
        let farLesson = lesson("l-far", introduce: [far])
        let nearLesson = lesson("l-near", introduce: [near])
        let current = lesson(
            "l-current",
            introduce: [sameA, sameB, target],
            examples: [exampleOnly],
            letters: [letter]
        )
        let futureLesson = lesson("l-future", introduce: [future, exampleOnly])
        let bundle = bundle(units: [
            unit("u-early", lessons: [earlyLesson]),
            unit("u-mid", lessons: [farLesson, nearLesson, current]),
            unit("u-late", lessons: [futureLesson]),
        ], items: [sameA, sameB, target, letter, near, far, earlyA, earlyB, future, exampleOnly])

        let seen = [earlyLesson, farLesson, nearLesson, current, futureLesson].map(\.id)
        let context = QuizContext(bundle: bundle, seenLessonIDs: seen)
        let candidates = Distractors.candidates(for: target, in: context)

        #expect(candidates.map(\.itemID.rawValue) == [
            "e-same-a", "e-same-b",
            "e-near",
            "e-far",
            "e-early-a", "e-early-b",
        ])
        #expect(candidates.map(\.source) == [
            .sameLesson, .sameLesson,
            .earlierLessonInUnit,
            .earlierLessonInUnit,
            .earlierUnit, .earlierUnit,
        ])
        #expect(!candidates.map(\.itemID.rawValue).contains("e-letter"))
        #expect(!candidates.map(\.itemID.rawValue).contains("e-future"))
        #expect(!candidates.map(\.itemID.rawValue).contains("e-example"))
        #expect(Distractors.candidates(for: letter, in: context).isEmpty)
    }

    @Test func synonymsSharedMeaningsAndSameFormsAreExcluded() {
        let target = word(
            "e-target",
            "1",
            "hello",
            pashto: "e\u{0301}",
            translit: "ka\u{0301}r",
            pronunciation: "kha",
            enAlt: ["Hi"]
        )
        let grouped = word("e-group", "2", "peace")
        let sameEn = word("e-same-en", "3", "HELLO")
        let sameAlt = word("e-same-alt", "4", "hi there", enAlt: ["hello"])
        let targetAlt = word("e-target-alt", "5", "HI")
        let samePronunciation = word("e-same-pron", "6", "fine", pronunciation: "KHA")
        let samePashto = word("e-same-pashto", "7", "other", pashto: "\u{00E9}")
        let sameTranslit = word("e-same-translit", "8", "walk", translit: "kar")
        let keptMacron = word("e-macron", "9", "long", translit: "k\u{0101}r")
        let retired = word("e-retired", "10", "retired word")
        let keptA = word("e-kept-a", "11", "yes")
        let keptB = word("e-kept-b", "12", "no")
        let items = [
            target, grouped, sameEn, sameAlt, targetAlt, samePronunciation,
            samePashto, sameTranslit, keptMacron, retired, keptA, keptB,
        ]
        let current = lesson("l-current", introduce: items)
        let content = bundle(
            units: [unit("u-one", lessons: [current])],
            items: items,
            groups: [[target.id, grouped.id]]
        )
        let context = QuizContext(
            bundle: content,
            seenLessonIDs: [current.id],
            retiredItemIDs: [retired.id]
        )

        let candidates = Distractors.candidates(for: target, in: context)
        #expect(candidates.map(\.itemID.rawValue) == ["e-macron", "e-kept-a", "e-kept-b"])

        let retiredTarget = QuizContext(
            bundle: content,
            seenLessonIDs: [current.id],
            retiredItemIDs: [target.id]
        )
        #expect(Distractors.candidates(for: target, in: retiredTarget).isEmpty)
    }

    @Test func zeroOneAndTwoEligibleItemsReturnNilAndThreeAndFourDoNot() {
        #expect(task(itemCount: 0) == nil)
        #expect(task(itemCount: 1) == nil)
        #expect(task(itemCount: 2) == nil)

        let three = task(itemCount: 3)
        #expect(three?.options.count == 3)
        #expect(three?.kind == .meaningPashtoToEnglish)

        let four = task(itemCount: 4)
        #expect(four?.options.count == 4)

        let five = task(itemCount: 5)
        #expect(five?.options.count == 4)
        #expect(five?.options.contains { $0.itemID.rawValue == "e-1" } == true)
        let fiveIDs = Set(five?.options.map(\.itemID.rawValue) ?? [])
        #expect(fiveIDs.isSubset(of: ["e-1", "e-2", "e-3", "e-4", "e-5"]))

        for count in 3...4 {
            for kind in [TaskKind.meaningPashtoToEnglish, .meaningEnglishToPashto, .transliterationChoice] {
                let question = task(itemCount: count, kind: kind)
                #expect(question?.options.count == count)
                #expect(question?.kind == kind)
            }
        }
    }

    @Test func optionTextMatchesTheKind() {
        let question = task(itemCount: 3, kind: .meaningEnglishToPashto)
        #expect(question?.prompt == "one")
        #expect(question?.options.map(\.text).sorted() == ["1", "2", "3"])
        #expect(question?.usage == nil)

        let pronunciation = task(itemCount: 3, kind: .transliterationChoice)
        #expect(pronunciation?.prompt == "1")
        #expect(pronunciation?.options.map(\.text).sorted() == ["p-1", "p-2", "p-3"])

        let withUsage = word("e-1", "1", "one", usage: "common greeting")
        let others = [word("e-2", "2", "two"), word("e-3", "3", "three")]
        let current = lesson("l-one", introduce: [withUsage] + others)
        let content = bundle(units: [unit("u-one", lessons: [current])], items: [withUsage] + others)
        var rng = SplitMix64(seed: 1)
        let shown = PashtoToEnglishChoice().makeTask(
            for: withUsage,
            in: QuizContext(bundle: content, seenLessonIDs: [current.id]),
            using: &rng
        )
        #expect(shown?.usage == "common greeting")
        #expect(shown?.prompt == "1")
        #expect(shown?.options.map(\.text).sorted() == ["one", "three", "two"])
    }

    @Test func soundExamplesDoNotCountAsSeenAndPlacementLessonsDo() {
        let placed = word("e-placed", "1", "placed")
        let onlyExample = word("e-only", "2", "only example")
        let extra = word("e-extra", "3", "extra")
        let first = word("e-a", "4", "first")
        let second = word("e-b", "5", "second")
        let sounds = lesson("l-sounds", examples: [placed, onlyExample])
        let skipped = lesson("l-skip", introduce: [placed, extra])
        let current = lesson("l-now", introduce: [first, second])
        let future = lesson("l-future", introduce: [onlyExample])
        let content = bundle(units: [
            unit("u-sounds", lessons: [sounds]),
            unit("u-skip", lessons: [skipped]),
            unit("u-now", lessons: [current]),
            unit("u-future", lessons: [future]),
        ], items: [placed, onlyExample, extra, first, second])

        let withoutPlacement = QuizContext(
            bundle: content,
            seenLessonIDs: [sounds.id, current.id]
        )
        #expect(Distractors.candidates(for: first, in: withoutPlacement).map(\.itemID.rawValue) == ["e-b"])
        var rng = SplitMix64(seed: 1)
        #expect(PashtoToEnglishChoice().makeTask(for: first, in: withoutPlacement, using: &rng) == nil)

        let withPlacement = QuizContext(
            bundle: content,
            seenLessonIDs: [sounds.id, skipped.id, current.id]
        )
        #expect(Distractors.candidates(for: first, in: withPlacement).map(\.itemID.rawValue) == [
            "e-b", "e-placed", "e-extra",
        ])
        let question = PashtoToEnglishChoice().makeTask(for: first, in: withPlacement, using: &rng)
        #expect(question?.options.map(\.itemID.rawValue).sorted() == ["e-a", "e-b", "e-extra", "e-placed"])
        #expect(!(question?.options.map(\.itemID.rawValue).contains("e-only") ?? true))
    }

    @Test func correctAnswerAppearsOnceAndOptionsAreUnique() throws {
        for count in 3...5 {
            for kind in [TaskKind.meaningPashtoToEnglish, .meaningEnglishToPashto, .transliterationChoice] {
                let question = try #require(task(itemCount: count, kind: kind))
                expectWellFormed([question], allowed: Set(question.options.map(\.itemID)))
                let wrong = try #require(question.options.first { $0.itemID != question.targetID })
                #expect(grade(question, .choice(question.targetID)) == .correct)
                #expect(grade(question, .choice(wrong.itemID)) == .incorrect)
            }
        }
    }

    @Test func distractorsStayInTheSameKindAndTooFewReturnsNil() {
        let words = (1...4).map { word("e-w\($0)", "w\($0)", "word \($0)") }
        let phrase = word("e-phrase", "one two", "a phrase", kind: .phrase)
        let letters = (1...2).map { word("e-l\($0)", "l\($0)", "letter \($0)", kind: .letter) }
        let current = lesson("l-mix", introduce: words + [phrase], letters: letters)
        let mixedUnit = unit("u-mix", lessons: [current])
        let content = bundle(
            units: [mixedUnit],
            items: words + [phrase] + letters
        )
        let context = QuizContext(
            bundle: content,
            seenLessonIDs: [current.id],
            releasedUnitIDs: [mixedUnit.id]
        )
        var rng = SplitMix64(seed: 1)

        let wordQuestion = PashtoToEnglishChoice().makeTask(for: words[0], in: context, using: &rng)
        let wordIDs = wordQuestion?.options.map(\.itemID.rawValue) ?? []
        #expect(wordQuestion != nil)
        #expect(wordIDs.contains("e-w1"))
        #expect(wordIDs.allSatisfy { $0.hasPrefix("e-w") })
        #expect(wordQuestion?.options.count == 4)

        var phraseRNG = SplitMix64(seed: 4)
        // One phrase has no phrase distractors, so the question is skipped.
        #expect(EnglishToPashtoChoice().makeTask(for: phrase, in: context, using: &phraseRNG) == nil)

        let phrases = (1...4).map { word("e-p\($0)", "phrase \($0)", "phrase \($0)", kind: .phrase) }
        let strayWord = word("e-stray", "stray", "stray word")
        let phraseLesson = lesson("l-phrases", introduce: phrases + [strayWord])
        let phraseUnit = unit("u-phrases", lessons: [phraseLesson])
        let phraseBundle = bundle(units: [phraseUnit], items: phrases + [strayWord])
        let phraseContext = QuizContext(
            bundle: phraseBundle,
            seenLessonIDs: [phraseLesson.id],
            releasedUnitIDs: [phraseUnit.id]
        )
        var phraseOnly = SplitMix64(seed: 4)
        let phraseQuestion = EnglishToPashtoChoice().makeTask(for: phrases[0], in: phraseContext, using: &phraseOnly)
        let phraseIDs = phraseQuestion?.options.map(\.itemID.rawValue) ?? []
        #expect(phraseQuestion != nil)
        #expect(phraseIDs.contains("e-p1"))
        #expect(phraseIDs.allSatisfy { $0.hasPrefix("e-p") })
        #expect(!phraseIDs.contains("e-stray"))

        #expect(PashtoToEnglishChoice().makeTask(for: letters[0], in: context, using: &rng) == nil)
        #expect(TransliterationChoice().makeTask(for: letters[0], in: context, using: &rng) == nil)

        let third = word("e-l3", "l3", "letter 3", kind: .letter)
        let letterLesson = lesson("l-letters", introduce: [words[0]], letters: letters + [third])
        let letterBundle = bundle(
            units: [unit("u-letters", lessons: [letterLesson])],
            items: [words[0]] + letters + [third]
        )
        let letterContext = QuizContext(bundle: letterBundle, seenLessonIDs: [letterLesson.id])
        var letterRNG = SplitMix64(seed: 2)
        #expect(PashtoToEnglishChoice().makeTask(for: words[0], in: letterContext, using: &letterRNG) == nil)

        for generator in [meaningGenerator(), transliterationGenerator()] {
            var one = SplitMix64(seed: 3)
            let question = generator(letters[0], letterContext, &one)
            let ids = question?.options.map(\.itemID.rawValue) ?? []
            #expect(question != nil)
            #expect(ids.contains("e-l1"))
            #expect(ids.allSatisfy { $0.hasPrefix("e-l") })
            #expect(!ids.contains("e-w1"))
        }
    }

    @Test func nearerLevelIsFilledBeforeTheNextAndPicksVary() {
        let target = word("e-target", "t", "target")
        let sameA = word("e-same-a", "a", "same a")
        let sameB = word("e-same-b", "b", "same b")
        let earlier = (1...4).map { word("e-earlier-\($0)", "e\($0)", "earlier \($0)") }
        let older = (1...3).map { word("e-older-\($0)", "o\($0)", "older \($0)") }
        let olderLesson = lesson("l-older", introduce: older)
        let earlierLesson = lesson("l-earlier", introduce: earlier)
        let current = lesson("l-current", introduce: [target, sameA, sameB])
        let content = bundle(units: [
            unit("u-old", lessons: [olderLesson]),
            unit("u-mid", lessons: [earlierLesson, current]),
        ], items: [target, sameA, sameB] + earlier + older)
        let context = QuizContext(
            bundle: content,
            seenLessonIDs: [olderLesson.id, earlierLesson.id, current.id]
        )

        var thirds: [String] = []
        for seed in UInt64(1)...40 {
            var rng = SplitMix64(seed: seed)
            let question = PashtoToEnglishChoice().makeTask(for: target, in: context, using: &rng)
            let ids = Set(question?.options.map(\.itemID.rawValue) ?? [])
            #expect(ids.contains("e-target"))
            #expect(ids.contains("e-same-a"))
            #expect(ids.contains("e-same-b"))
            #expect(ids.count == 4)
            #expect(ids.isDisjoint(with: ["e-older-1", "e-older-2", "e-older-3"]))
            let third = ids.subtracting(["e-target", "e-same-a", "e-same-b"])
            #expect(third.count == 1)
            let picked = third.first ?? ""
            #expect(picked.hasPrefix("e-earlier-"))
            thirds.append(picked)
        }
        #expect(Set(thirds).count > 1)
    }

    @Test func distractorSetVariesAcrossSeeds() {
        var sets: [Set<String>] = []
        for seed in UInt64(1)...30 {
            let question = task(itemCount: 6, seed: seed)
            let ids = Set(question?.options.map(\.itemID.rawValue) ?? [])
            #expect(ids.contains("e-1"))
            #expect(ids.count == 4)
            #expect(ids.isSubset(of: ["e-1", "e-2", "e-3", "e-4", "e-5", "e-6"]))
            sets.append(ids)
        }
        #expect(Set(sets).count > 1)
    }

    @Test func correctAnswerPositionIsSpreadAcrossSlots() throws {
        let trials = 240
        var counts = [0, 0, 0, 0]
        for seed in 1...trials {
            let question = try #require(task(itemCount: 6, seed: UInt64(seed)))
            let index = try #require(question.options.firstIndex { $0.itemID == question.targetID })
            counts[index] += 1
        }
        let low = trials / 8
        let high = trials / 2
        for count in counts {
            #expect(count >= low)
            #expect(count <= high)
        }
    }

    @Test func optionOrderUsesTheSeedAndTheSetDoesNot() {
        var orders: [[String]] = []
        var sets: [Set<String>] = []
        for seed in UInt64(1)...5 {
            let question = task(itemCount: 4, seed: seed)
            let ids = question?.options.map(\.itemID.rawValue) ?? []
            orders.append(ids)
            sets.append(Set(ids))
        }
        #expect(sets.allSatisfy { $0 == sets[0] })
        #expect(Set(orders).count > 1)
    }

    @Test func everyLessonInContentJsonYieldsSeenQuestions() throws {
        let bundle = try loadRepositoryContent()
        let lessons = bundle.units.flatMap(\.lessons)
        #expect(lessons.map(\.id.rawValue) == [
            "l-sounds-1",
            "l-basics-learn-1",
            "l-basics-learn-2",
            "l-basics-phrases",
            "l-basics-1",
            "l-greetings-learn",
            "l-greetings-phrases-hello",
            "l-greetings-phrases-how",
            "l-greetings-phrases-goodbye",
            "l-greetings-1",
            "l-greetings-2",
            "l-greetings-3",
            "l-introductions-learn-names",
            "l-introductions-learn-be",
            "l-introductions-phrases-name",
            "l-introductions-phrases-from",
            "l-introductions-1",
            "l-introductions-2",
            "l-introductions-3",
            "l-family-learn-members",
            "l-family-learn-this",
            "l-family-phrases-this",
            "l-family-phrases-yours",
            "l-family-phrases-how",
            "l-family-1",
            "l-family-2",
            "l-family-3",
            "l-travel-learn-around",
            "l-travel-learn-money",
            "l-travel-phrases-where",
            "l-travel-phrases-buying",
            "l-travel-1",
            "l-travel-2",
            "l-time-learn-times",
            "l-time-learn-days",
            "l-time-phrases-day",
            "l-time-phrases-morning",
            "l-time-1",
            "l-time-2",
            "l-numbers-1",
            "l-numbers-2",
            "l-food-1",
            "l-food-2",
            "l-food-3",
            "l-food-4",
            "l-daily-life-1",
            "l-daily-life-2",
            "l-daily-life-3",
            "l-daily-life-4",
            "l-town-1",
            "l-town-2",
            "l-town-3",
            "l-town-4",
            "l-conversation-1",
            "l-conversation-2",
            "l-conversation-3",
        ])

        var seen: [LessonID] = []
        for lesson in lessons {
            seen.append(lesson.id)
            var rng = SplitMix64(seed: 1)
            let tasks = MultipleChoiceQuiz.questions(
                for: lesson.id,
                in: bundle,
                seenLessonIDs: seen,
                using: &rng
            )
            let introduced = Distractors.introducedItems(in: lesson.id, bundle: bundle)
            let allowed = introducedIDs(in: seen, bundle: bundle)
            // l-sounds-1 only references sound examples. Those items are not seen,
            // and the lesson introduces nothing, so it has no multiple-choice questions.
            if introduced.isEmpty {
                #expect(tasks.isEmpty)
            } else {
                #expect(!tasks.isEmpty)
            }
            expectWellFormed(tasks, allowed: allowed)
            expectSameKind(tasks, items: bundle.items)
            if lesson.id.rawValue == "l-greetings-1" {
                let targets = Set(tasks.map(\.targetID.rawValue))
                #expect(targets.isSuperset(of: [
                    "e-salam", "e-assalamu-alaykum", "e-walaykum-salam",
                    "e-xwar-ma-she", "e-xa-raghlast",
                ]))
                // Grouped with the other greetings, so fewer than two distractors remain.
                #expect(!targets.contains("e-stare-ma-she"))
                #expect(!targets.contains("e-letter-alif"))
                #expect(!targets.contains("e-letter-be"))
            }
            if lesson.id.rawValue == "l-greetings-2" {
                let letterKinds = Set(tasks.filter { $0.targetID.rawValue == "e-letter-pe" }.map(\.kind))
                // Pronunciation is on, so the old letter choices are not built.
                #expect(letterKinds.isEmpty)
            }
        }

        var greetingsRNG = SplitMix64(seed: 1)
        let greetings = MultipleChoiceQuiz.questions(
            for: lessonID("l-greetings-1"),
            in: bundle,
            seenLessonIDs: [lessonID("l-sounds-1"), lessonID("l-greetings-1")],
            using: &greetingsRNG
        )
        let greetingsIDs = Set(greetings.flatMap { $0.options.map(\.itemID.rawValue) })
        #expect(!greetingsIDs.contains("e-za"))
        #expect(!greetingsIDs.contains("e-xa"))
        let hello = try #require(greetings.first { $0.targetID.rawValue == "e-salam" && $0.kind == .meaningPashtoToEnglish })
        #expect(hello.usage == "common greeting")
        #expect(!hello.options.map(\.itemID.rawValue).contains("e-stare-ma-she"))
        #expect(!hello.options.map(\.itemID.rawValue).contains("e-assalamu-alaykum"))
    }

    @Test func oneHundredRunsWithAFixedSeedMatch() throws {
        let bundle = try loadRepositoryContent()
        let lessons = bundle.units.flatMap(\.lessons)
        let first = generate(bundle, lessons: lessons, seed: 42)
        #expect(!first.isEmpty)
        expectWellFormed(first, allowed: Set(bundle.items.map(\.id)))
        for _ in 0..<99 {
            #expect(generate(bundle, lessons: lessons, seed: 42) == first)
        }
    }
}

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

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

private func word(
    _ id: String,
    _ pashto: String,
    _ en: String,
    kind: ContentKind = .word,
    pashto override: String? = nil,
    translit: String? = nil,
    pronunciation: String? = nil,
    enAlt: [String]? = nil,
    usage: String? = nil
) -> ContentItem {
    makeItem(
        id,
        kind: kind,
        pashto: override ?? pashto,
        translit: translit ?? "t-\(id)",
        pronunciation: pronunciation ?? "p-\(pashto)",
        en: en,
        enAlt: enAlt,
        usage: usage
    )
}

private func lesson(
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

private func unit(_ id: String, lessons: [Lesson]) -> CourseUnit {
    CourseUnit(id: unitID(id), track: "main", title: id, lessons: lessons)
}

private func bundle(
    units: [CourseUnit],
    items: [ContentItem],
    groups: [[ItemID]] = []
) -> ContentBundle {
    makeBundle(items: items, units: units, groups: groups)
}

private func task(
    itemCount: Int,
    kind: TaskKind = .meaningPashtoToEnglish,
    seed: UInt64 = 1
) -> QuizTask? {
    guard itemCount > 0 else {
        let outsider = word("e-outsider", "x", "outside")
        let current = lesson("l-empty")
        let content = bundle(units: [unit("u-one", lessons: [current])], items: [outsider])
        var rng = SplitMix64(seed: seed)
        return PashtoToEnglishChoice().makeTask(
            for: outsider,
            in: QuizContext(bundle: content, seenLessonIDs: [current.id]),
            using: &rng
        )
    }
    let items = (1...itemCount).map { index in
        word("e-\(index)", "\(index)", numberWord(index))
    }
    let current = lesson("l-one", introduce: items)
    let content = bundle(units: [unit("u-one", lessons: [current])], items: items)
    var rng = SplitMix64(seed: seed)
    let context = QuizContext(bundle: content, seenLessonIDs: [current.id])
    switch kind {
    case .meaningPashtoToEnglish:
        return PashtoToEnglishChoice().makeTask(for: items[0], in: context, using: &rng)
    case .meaningEnglishToPashto:
        return EnglishToPashtoChoice().makeTask(for: items[0], in: context, using: &rng)
    case .transliterationChoice:
        return TransliterationChoice().makeTask(for: items[0], in: context, using: &rng)
    case .findLetter, .letterContrast, .firstLetter, .matchPairs, .orderWords, .dialogResponse:
        return nil
    }
}

private func numberWord(_ index: Int) -> String {
    ["one", "two", "three", "four", "five", "six"][index - 1]
}

func loadRepositoryContent() throws -> ContentBundle {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
        url.deleteLastPathComponent()
    }
    url.appendPathComponent("content")
    url.appendPathComponent("content.json")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(ContentBundle.self, from: data)
}

private func introducedIDs(in lessons: [LessonID], bundle: ContentBundle) -> Set<ItemID> {
    var ids: [ItemID] = []
    for lesson in lessons {
        ids.append(contentsOf: Distractors.introducedItems(in: lesson, bundle: bundle).map(\.id))
    }
    return Set(ids)
}

private func generate(_ bundle: ContentBundle, lessons: [Lesson], seed: UInt64) -> [QuizTask] {
    var seen: [LessonID] = []
    var tasks: [QuizTask] = []
    var rng = SplitMix64(seed: seed)
    for lesson in lessons {
        seen.append(lesson.id)
        tasks.append(contentsOf: MultipleChoiceQuiz.questions(
            for: lesson.id,
            in: bundle,
            seenLessonIDs: seen,
            using: &rng
        ))
    }
    return tasks
}

private func meaningGenerator() -> (ContentItem, QuizContext, inout SplitMix64) -> QuizTask? {
    { item, context, rng in
        PashtoToEnglishChoice().makeTask(for: item, in: context, using: &rng)
    }
}

private func transliterationGenerator() -> (ContentItem, QuizContext, inout SplitMix64) -> QuizTask? {
    { item, context, rng in
        TransliterationChoice().makeTask(for: item, in: context, using: &rng)
    }
}

private func expectSameKind(_ tasks: [QuizTask], items: [ContentItem]) {
    var byID: [ItemID: ContentItem] = [:]
    for item in items where byID[item.id] == nil {
        byID[item.id] = item
    }
    for task in tasks {
        guard let target = byID[task.targetID] else {
            Issue.record("Missing target \(task.targetID)")
            continue
        }
        for option in task.options {
            guard let item = byID[option.itemID] else {
                Issue.record("Missing option \(option.itemID)")
                continue
            }
            #expect((item.kind == .letter) == (target.kind == .letter))
        }
    }
}

private func expectWellFormed(_ tasks: [QuizTask], allowed: Set<ItemID>) {
    for task in tasks {
        let ids = task.options.map(\.itemID)
        let texts = task.options.map(\.text)
        #expect(ids.count == 3 || ids.count == 4)
        #expect(ids.filter { $0 == task.targetID }.count == 1)
        #expect(Set(ids).count == ids.count)
        #expect(Set(texts).count == texts.count)
        #expect(Set(ids).isSubset(of: allowed))
        #expect(task.options.contains { $0.itemID == task.targetID })
    }
}
