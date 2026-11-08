import Foundation
import Testing
@testable import PashtoCore

struct QuizFindingsTests {
    @Test func dialogPromptPronouncesTheQuestionNotTheReply() throws {
        let bundle = try loadRepositoryContent()
        let lessons = bundle.units.flatMap(\.lessons)
        var seen: [LessonID] = []
        var rng = SplitMix64(seed: 1)
        var checked = 0
        for lesson in lessons {
            seen.append(lesson.id)
            let session = LessonSessionBuilder.build(
                for: lesson.id,
                in: bundle,
                seenLessonIDs: seen,
                maxQuestions: nil,
                releasedUnitIDs: nil,
                showsPronunciation: true,
                using: &rng
            )
            for task in session.tasks {
                guard case .choice(let quiz) = task.payload, quiz.kind == .dialogResponse else { continue }
                let reply = try #require(bundle.items.first { $0.id == quiz.targetID })
                let prompt = try #require(bundle.items.first { $0.id == reply.responseTo })
                #expect(quiz.promptItemID == prompt.id)
                let face = QuizPresentation.face(
                    for: quiz,
                    items: bundle.items,
                    showsPronunciation: true,
                    voiceOver: false,
                    answered: false
                )
                #expect(face.prompt.text == prompt.pashto)
                #expect(face.prompt.pronunciation == prompt.pronunciation)
                #expect(face.prompt.pronunciation != reply.pronunciation)
                #expect(face.prompt.text != reply.translit)
                checked += 1
            }
        }
        #expect(checked > 0)
    }

    @Test func findLetterOnRealContentUsesEnglishAndNeverTheGlyphOrItsTwin() throws {
        let bundle = try loadRepositoryContent()
        let lessons = bundle.units.flatMap(\.lessons)
        var seen: [LessonID] = []
        var rng = SplitMix64(seed: 3)
        var checked = 0
        for lesson in lessons {
            seen.append(lesson.id)
            let session = LessonSessionBuilder.build(
                for: lesson.id,
                in: bundle,
                seenLessonIDs: seen,
                maxQuestions: nil,
                releasedUnitIDs: nil,
                showsPronunciation: true,
                voiceOver: false,
                using: &rng
            )
            for task in session.tasks {
                guard case .choice(let quiz) = task.payload, quiz.kind == .findLetter else { continue }
                let letter = try #require(bundle.items.first { $0.id == quiz.targetID })
                #expect(quiz.prompt == letter.en)
                #expect(!quiz.prompt.contains(letter.pashto))
                #expect(quiz.prompt != letter.name)
                #expect(quiz.prompt != letter.sound)
                #expect(quiz.prompt != letter.translit)
                if let twin = LetterContrasts.entry(matching: letter.pashto)?.partnerGlyph {
                    #expect(!quiz.options.contains { Normalization.nfc($0.text) == Normalization.nfc(twin) })
                }
                let face = QuizPresentation.face(
                    for: quiz,
                    items: bundle.items,
                    showsPronunciation: true,
                    voiceOver: false,
                    answered: false
                )
                #expect(!QuizPresentation.containsArabicScript(face.prompt.text))
                #expect(face.prompt.pronunciation == nil)
                #expect(face.options.allSatisfy { $0.pronunciation == nil && $0.reservesPronunciation })
                checked += 1
            }
        }
        #expect(checked > 0)
    }

    @Test func sameSoundCoversTaRaAndZa() {
        let session = contrastSession(showsPronunciation: true)
        let hidden = contrastSession(showsPronunciation: false)
        #expect(session.tasks.contains { $0.kind == .letterContrast })
        #expect(session.tasks.contains { $0.kind == .findLetter })
        #expect(session.tasks.contains { $0.kind == .firstLetter })
        #expect(hidden.tasks.contains { $0.kind == .letterContrast })
        #expect(!hidden.tasks.contains { $0.kind == .findLetter })
        #expect(!hidden.tasks.contains { $0.kind == .firstLetter })
        let prompts = Dictionary(uniqueKeysWithValues: choiceTasks(in: session, kind: .letterContrast).map {
            ($0.targetID.rawValue, $0)
        })
        let expected: [(String, String, String)] = [
            ("e-te", "ت", "ټ"),
            ("e-tte", "ټ", "ت"),
            ("e-re", "ر", "ړ"),
            ("e-rre", "ړ", "ر"),
            ("e-zal", "ذ", "ز"),
            ("e-ze", "ز", "ذ"),
        ]
        for (id, glyph, twin) in expected {
            let task = prompts[id]
            #expect(task?.prompt == LetterContrasts.entry(matching: glyph)?.hint)
            #expect(Set(task?.options.map(\.text) ?? []) == [glyph, twin])
        }
        let off = Dictionary(uniqueKeysWithValues: choiceTasks(in: hidden, kind: .letterContrast).map {
            ($0.targetID.rawValue, Set($0.options.map(\.text)))
        })
        #expect(off["e-te"] == ["ت", "ټ"])
        #expect(off["e-re"] == ["ر", "ړ"])
        #expect(off["e-ze"] == ["ز", "ذ"])
    }

    @Test func findLetterAndFirstLetterNeedTwoWrongGlyphs() {
        var only = letterCourse(words: [word("e-dar", "در", "door")], letters: [letter("e-dal", "د", "the letter da")])
        #expect(LetterTasks.findLetter(for: only.letters[0], in: only.context, using: &only.rng) == nil)
        #expect(LetterTasks.firstLetter(of: only.words[0], in: only.context, using: &only.rng) == nil)

        var twins = letterCourse(
            words: [word("e-dar", "در", "door")],
            letters: [
                letter("e-dal", "د", "the letter da"),
                letter("e-ddal", "ډ", "the letter da with a ring"),
            ]
        )
        #expect(LetterTasks.findLetter(for: twins.letters[0], in: twins.context, using: &twins.rng) == nil)
        #expect(LetterTasks.firstLetter(of: twins.words[0], in: twins.context, using: &twins.rng) == nil)
    }

    @Test func firstLetterUsesTheSoundTwinAsAWrongOption() throws {
        var course = letterCourse(
            words: [
                word("e-dar", "در", "door"),
                word("e-tar", "تر", "until"),
                word("e-rar", "رر", "flow"),
                word("e-zar", "ذر", "speck"),
            ],
            letters: [
                letter("e-dal", "د", "the letter da"),
                letter("e-ddal", "ډ", "the letter da with a ring"),
                letter("e-te", "ت", "the letter ta"),
                letter("e-tte", "ټ", "the letter ta with a ring"),
                letter("e-re", "ر", "the letter ra"),
                letter("e-rre", "ړ", "the letter ra with a ring"),
                letter("e-zal", "ذ", "the letter za, dot on da"),
                letter("e-ze", "ز", "the letter za, dot on ra"),
                letter("e-be", "ب", "the letter ba"),
            ]
        )
        let pairs = [("در", "ډ"), ("تر", "ټ"), ("رر", "ړ"), ("ذر", "ز")]
        for (prompt, twin) in pairs {
            let task = try #require(LetterTasks.firstLetter(of: course.words.first { $0.pashto == prompt }!, in: course.context, using: &course.rng))
            #expect(task.options.contains { $0.text == twin })
            let find = try #require(course.letters.first { $0.pashto == String(prompt.prefix(1)) })
            let b1 = try #require(LetterTasks.findLetter(for: find, in: course.context, using: &course.rng))
            #expect(!b1.options.contains { $0.text == twin })
            #expect(!b1.prompt.contains(find.pashto))
        }
    }

    @Test func voiceOverTurnedOnMidSessionLabelsOnlyLetterGlyphs() throws {
        let started = contrastSession(showsPronunciation: true)
        #expect(started.tasks.contains { $0.kind == .findLetter })
        let find = try #require(choiceTasks(in: started, kind: .findLetter).first)
        let meaning = try #require(choiceTasks(in: started, kind: .meaningPashtoToEnglish).first)
        let voiced = QuizPresentation.face(
            for: find,
            items: contrastItems(),
            showsPronunciation: true,
            voiceOver: true,
            answered: false
        )
        #expect(voiced.options.allSatisfy {
            if case .optionNumber = $0.accessibility { return true }
            return false
        })
        let meaningFace = QuizPresentation.face(
            for: meaning,
            items: contrastItems(),
            showsPronunciation: true,
            voiceOver: true,
            answered: false
        )
        #expect(meaningFace.options.map(\.accessibility) == meaning.options.map { .visible($0.text) })
        #expect(started.tasks.contains { $0.kind == .findLetter })

        let fromTheStart = contrastSession(showsPronunciation: true, voiceOver: true)
        let letters = Set(contrastItems().filter { $0.kind == .letter }.map(\.id))
        #expect(!fromTheStart.tasks.contains { task in
            guard case .choice(let quiz) = task.payload else { return false }
            return letters.contains(quiz.targetID)
        })
    }

    @Test func orderSentencePronunciationWaitsUntilTheAnswerAndSessionsIncludeTheTask() throws {
        #expect(OrderWords.includedInSessions)
        let phrase = makeItem(
            "e-phrase",
            pashto: "زه ښه",
            translit: "za kha",
            pronunciation: "za-KHA",
            en: "I am well",
            tokens: ["زه", "ښه"],
            tokenPronunciations: ["za", "kha"]
        )
        let lesson = Lesson(
            id: lessonID("l-order"),
            title: "order",
            items: [LessonItemRef(item: phrase.id, role: .introduce)]
        )
        let bundle = makeBundle(
            items: [phrase],
            units: [CourseUnit(id: unitID("u-order"), track: "main", title: "order", lessons: [lesson])]
        )
        var rng = SplitMix64(seed: 1)
        let session = LessonSessionBuilder.build(
            for: lesson.id,
            in: bundle,
            seenLessonIDs: [lesson.id],
            maxQuestions: nil,
            releasedUnitIDs: nil,
            using: &rng
        )
        #expect(session.tasks.contains { $0.kind == .orderWords })
        guard case .orderWords(let order) = session.tasks.first(where: { $0.kind == .orderWords })?.payload else {
            Issue.record("Missing word-order task")
            return
        }
        #expect(order.tiles.compactMap(\.pronunciation).sorted() == ["kha", "za"])
        for tile in order.tiles {
            #expect(QuizPresentation.tilePronunciation(tile.pronunciation, showsPronunciation: true) == tile.pronunciation)
            #expect(QuizPresentation.tilePronunciation(tile.pronunciation, showsPronunciation: false) == nil)
        }
        var direct = SplitMix64(seed: 1)
        let context = QuizContext(bundle: bundle, seenLessonIDs: [lesson.id])
        #expect(OrderWords.makeTask(for: phrase, in: context, using: &direct) != nil)

        #expect(QuizPresentation.sentencePronunciation(item: phrase, showsPronunciation: true, answered: false) == nil)
        #expect(QuizPresentation.sentencePronunciation(item: phrase, showsPronunciation: true, answered: true) == "za-KHA")
        #expect(QuizPresentation.sentencePronunciation(item: phrase, showsPronunciation: false, answered: true) == nil)
    }

    /// Farhad approved these spellings on 2026-11-03. The test compares them character for character.
    @Test func everyOrderingTileMatchesTheApprovedPronunciation() throws {
        let bundle = try loadRepositoryContent()
        let table = approvedTilePronunciations
        #expect(table.count == 35)
        var seen: Set<String> = []
        var orderingSentences = 0
        for item in bundle.items {
            guard let tokens = item.tokens else {
                #expect(item.tokenPronunciations == nil)
                continue
            }
            orderingSentences += 1
            let spoken = try #require(item.tokenPronunciations)
            #expect(spoken.count == tokens.count)
            for (token, pronunciation) in zip(tokens, spoken) {
                #expect(!pronunciation.isEmpty)
                #expect(pronunciation == table[token])
                seen.insert(token)
            }
        }
        #expect(orderingSentences == 22)
        #expect(seen == Set(table.keys))

        let released = try releasedOrderingItems(in: bundle)
        for item in released {
            guard let tokens = item.tokens else { continue }
            let spoken = try #require(item.tokenPronunciations)
            #expect(spoken.count == tokens.count)
            for (token, pronunciation) in zip(tokens, spoken) {
                #expect(!pronunciation.isEmpty)
                #expect(pronunciation == table[token])
            }
        }

        let lessons = bundle.units.flatMap(\.lessons)
        var seenLessons: [LessonID] = []
        var rng = SplitMix64(seed: 1)
        var orderCount = 0
        for lesson in lessons {
            seenLessons.append(lesson.id)
            let session = LessonSessionBuilder.build(
                for: lesson.id,
                in: bundle,
                seenLessonIDs: seenLessons,
                maxQuestions: nil,
                releasedUnitIDs: nil,
                showsPronunciation: true,
                using: &rng
            )
            for task in session.tasks {
                guard case .orderWords(let order) = task.payload else { continue }
                orderCount += 1
                let item = try #require(bundle.items.first { $0.id == order.targetID })
                #expect(QuizPresentation.sentencePronunciation(item: item, showsPronunciation: true, answered: false) == nil)
                #expect(QuizPresentation.sentencePronunciation(item: item, showsPronunciation: session.showsPronunciation, answered: true) == item.pronunciation)
                for tile in order.tiles {
                    let pronunciation = try #require(tile.pronunciation)
                    #expect(!pronunciation.isEmpty)
                    #expect(pronunciation == table[tile.text])
                    #expect(pronunciation == item.tokenPronunciations?[tile.index])
                    #expect(QuizPresentation.tilePronunciation(pronunciation, showsPronunciation: true) == pronunciation)
                }
            }
        }
        #expect(orderCount == 22)

        var hiddenRNG = SplitMix64(seed: 1)
        let hidden = LessonSessionBuilder.build(
            for: lessonID("l-greetings-2"),
            in: bundle,
            seenLessonIDs: lessons.map(\.id),
            maxQuestions: nil,
            releasedUnitIDs: nil,
            showsPronunciation: false,
            using: &hiddenRNG
        )
        let hiddenOrders = hidden.tasks.compactMap { task -> OrderWordsTask? in
            guard case .orderWords(let order) = task.payload else { return nil }
            return order
        }
        #expect(!hiddenOrders.isEmpty)
        for order in hiddenOrders {
            for tile in order.tiles {
                #expect(QuizPresentation.tilePronunciation(tile.pronunciation, showsPronunciation: false) == nil)
            }
            let item = try #require(bundle.items.first { $0.id == order.targetID })
            #expect(QuizPresentation.sentencePronunciation(item: item, showsPronunciation: false, answered: true) == nil)
        }
    }

    @Test func matchLinksCanBeChangedAndPlacedTilesCanBeRemoved() {
        let left = itemID("e-left")
        let other = itemID("e-other")
        let right = itemID("e-right")
        let taken = itemID("e-taken")
        var links: [ItemID: ItemID] = [left: right]
        links = QuizDraft.link(links, left: other, right: right)
        #expect(links[other] == right)
        #expect(links[left] == nil)
        links = QuizDraft.unlink(links, left: other)
        #expect(links.isEmpty)
        #expect(QuizDraft.place([0, 1], tile: 1) == [0])
        #expect(QuizDraft.place([0], tile: 2) == [0, 2])
        #expect(QuizPresentation.matchAccessibilityLabel(text: "سلام", pronunciation: "sa-LAAM", linkedText: "hello") == "سلام, sa-LAAM, hello")
    }

    @Test func aWrongMatchStillMarksTheCorrectPairs() {
        let hello = itemID("e-hello")
        let helloEn = itemID("e-hello-en")
        let thanks = itemID("e-thanks")
        let thanksEn = itemID("e-thanks-en")
        let bye = itemID("e-bye")
        let byeEn = itemID("e-bye-en")
        let task = MatchPairsTask(
            mode: .pashtoEnglish,
            pairs: [
                MatchPair(left: MatchSide(itemID: hello, text: "سلام"), right: MatchSide(itemID: helloEn, text: "hello")),
                MatchPair(left: MatchSide(itemID: thanks, text: "مننه"), right: MatchSide(itemID: thanksEn, text: "thanks")),
                MatchPair(left: MatchSide(itemID: bye, text: "خدای"), right: MatchSide(itemID: byeEn, text: "bye")),
            ],
            rightOrder: [1, 2, 0]
        )
        let links = [hello: helloEn, thanks: byeEn, bye: thanksEn]
        let answer = QuizAnswer.matches(task.pairs.map { MatchLink(left: $0.left.itemID, right: links[$0.left.itemID]!) })
        #expect(grade(task, answer) == .incorrect)
        #expect(QuizDraft.pairMark(linkedRight: links[hello], correctRight: helloEn, revealed: true) == .correct)
        #expect(QuizDraft.pairMark(linkedRight: links[thanks], correctRight: thanksEn, revealed: true) == .incorrect)
        #expect(QuizDraft.pairMark(linkedRight: links[bye], correctRight: byeEn, revealed: true) == .incorrect)
        #expect(QuizDraft.pairMark(linkedRight: helloEn, correctRight: helloEn, revealed: false) == nil)
    }

    @Test func resultColorsMeetContrast() {
        for pair in QuizResultPalette.textPairs {
            let ratio = QuizResultPalette.contrastRatio(foreground: pair.foreground, background: pair.background)
            #expect(pair.minimumRatio == 4.5)
            #expect(ratio >= pair.minimumRatio)
        }
        for pair in QuizResultPalette.markPairs {
            let ratio = QuizResultPalette.contrastRatio(foreground: pair.foreground, background: pair.background)
            #expect(pair.minimumRatio == 3)
            #expect(ratio >= pair.minimumRatio)
        }
        #expect(QuizResultPalette.correctMarkLight != QuizResultPalette.correctTextLight)
        #expect(QuizResultPalette.ringLight == 0xB97D22)
        #expect(QuizResultPalette.ringDark == 0xF2B85B)
        #expect(QuizResultPalette.ringLight != 0xE8A33D)
        let selectedChoice = QuizResultPalette.markPairs.filter { $0.name.hasPrefix("selected choice frame") }
        #expect(selectedChoice.map(\.name) == [
            "selected choice frame on the page, light",
            "selected choice frame on the page, dark",
        ])
        #expect(selectedChoice.map(\.foreground) == [QuizResultPalette.ringLight, QuizResultPalette.ringDark])
        #expect(QuizResultPalette.contrastRatio(foreground: 0xE8A33D, background: QuizResultPalette.pageLight) < 3)
        let lessonBar = QuizResultPalette.markPairs.filter { $0.name.hasPrefix("lesson bar") }
        #expect(lessonBar.map(\.name) == [
            "lesson bar fill on track, light",
            "lesson bar fill on track, dark",
            "lesson bar outline on the page, light",
            "lesson bar outline on the page, dark",
        ])
        #expect(lessonBar.map(\.foreground) == [
            QuizResultPalette.lessonBarFillLight,
            QuizResultPalette.lessonBarFillDark,
            QuizResultPalette.lessonBarOutlineLight,
            QuizResultPalette.lessonBarOutlineDark,
        ])
        #expect(lessonBar.map(\.background) == [
            QuizResultPalette.lessonBarTrackLight,
            QuizResultPalette.lessonBarTrackDark,
            QuizResultPalette.pageLight,
            QuizResultPalette.pageDark,
        ])
        #expect(QuizResultPalette.lessonBarFillLight == QuizResultPalette.ringLight)
        #expect(QuizResultPalette.lessonBarFillDark == QuizResultPalette.ringDark)
        #expect(QuizResultPalette.lessonBarFillLight != 0xE8A33D)
        #expect(QuizResultPalette.lessonBarOutlineLight == 0x1E3A8A)
        #expect(QuizResultPalette.lessonBarOutlineDark == 0x93B4F5)
        #expect(QuizResultPalette.pageLight == 0xFAF7F0)
        #expect(QuizResultPalette.pageDark == 0x0F172A)
        #expect(QuizResultPalette.muted == 0x7C8799)
        #expect(QuizResultPalette.cardSurfaceDark == 0x1E293B)
        let muted = QuizResultPalette.markPairs.filter { $0.name.hasPrefix("muted track") }
        #expect(muted.map(\.name) == [
            "muted track on the page, light",
            "muted track on the page, dark",
            "muted track on the card, light",
            "muted track on the card, dark",
        ])
        #expect(muted.map(\.foreground) == Array(repeating: QuizResultPalette.muted, count: 4))
        #expect(muted.map(\.background) == [
            QuizResultPalette.pageLight,
            QuizResultPalette.pageDark,
            QuizResultPalette.white,
            QuizResultPalette.cardSurfaceDark,
        ])
        let star = QuizResultPalette.markPairs.filter { $0.name == "achievement star outline on the page, light" }
        #expect(star.map(\.foreground) == [QuizResultPalette.ringLight])
        #expect(star.map(\.background) == [QuizResultPalette.pageLight])
        #expect(QuizResultPalette.ringLight == 0xB97D22)
        #expect(QuizResultPalette.badgeLight == 0x1E3A8A)
        #expect(QuizResultPalette.badgeDark == 0x4666D2)
        #expect(QuizResultPalette.badgeInk == 0xFAF7F0)
        let badgeOnPage = QuizResultPalette.markPairs.filter { $0.name.hasPrefix("badge on the page") }
        #expect(badgeOnPage.map(\.name) == [
            "badge on the page, light",
            "badge on the page, dark",
        ])
        #expect(badgeOnPage.map(\.foreground) == [QuizResultPalette.badgeLight, QuizResultPalette.badgeDark])
        #expect(badgeOnPage.map(\.background) == [QuizResultPalette.pageLight, QuizResultPalette.pageDark])
        #expect(badgeOnPage.map(\.minimumRatio) == [3, 3])
        let badgeInk = QuizResultPalette.textPairs.filter { $0.name.hasPrefix("badge ink") }
        #expect(badgeInk.map(\.name) == [
            "badge ink on the badge, light",
            "badge ink on the badge, dark",
        ])
        #expect(badgeInk.map(\.foreground) == [QuizResultPalette.badgeInk, QuizResultPalette.badgeInk])
        #expect(badgeInk.map(\.background) == [QuizResultPalette.badgeLight, QuizResultPalette.badgeDark])
        #expect(badgeInk.map(\.minimumRatio) == [4.5, 4.5])
    }

    @Test func feedbackUsesASymbolAndTheExistingWords() {
        #expect(QuizResultMark.correct.symbolName == "checkmark")
        #expect(QuizResultMark.incorrect.symbolName == "xmark")
        #expect(QuizResultMark.correct.spokenEnglish == "Correct")
        #expect(QuizResultMark.incorrect.spokenEnglish == "Incorrect")
    }

    @Test func anEmptyReleaseListQuizzesNothing() {
        let course = letterCourse(words: [word("e-dar", "در", "door"), word("e-tab", "تب", "fever")], letters: [])
        var rng = SplitMix64(seed: 1)
        let session = LessonSessionBuilder.build(
            for: lessonID("l-letters"),
            in: course.bundle,
            seenLessonIDs: [lessonID("l-letters")],
            maxQuestions: nil,
            releasedUnitIDs: [],
            showsPronunciation: true,
            using: &rng
        )
        #expect(session.tasks.isEmpty)
        #expect(session.showsPronunciation)
    }

    @Test func firstLetterSkipsALeadingDiacritic() throws {
        var course = letterCourse(
            words: [word("e-dar", "\u{064E}در", "door"), word("e-aab", "\u{064E}آب", "water")],
            letters: [
                letter("e-dal", "د", "the letter da"),
                letter("e-te", "ت", "the letter ta"),
                letter("e-be", "ب", "the letter ba"),
            ]
        )
        let task = try #require(LetterTasks.firstLetter(of: course.words[0], in: course.context, using: &course.rng))
        #expect(task.targetID == itemID("e-dal"))
        #expect(LetterTasks.firstLetter(of: course.words[1], in: course.context, using: &course.rng) == nil)
        #expect(LetterTasks.startsWithAlefMadda("\u{064E}آب"))
    }
}

private struct LetterCourse {
    var bundle: ContentBundle
    var words: [ContentItem]
    var letters: [ContentItem]
    var context: QuizContext
    var rng = SplitMix64(seed: 1)
}

private func letterCourse(words: [ContentItem], letters: [ContentItem]) -> LetterCourse {
    let lesson = Lesson(
        id: lessonID("l-letters"),
        title: "letters",
        items: words.map { LessonItemRef(item: $0.id, role: .introduce) },
        letters: letters.map(\.id)
    )
    let bundle = makeBundle(
        items: words + letters,
        units: [CourseUnit(id: unitID("u-letters"), track: "main", title: "letters", lessons: [lesson])]
    )
    return LetterCourse(
        bundle: bundle,
        words: words,
        letters: letters,
        context: QuizContext(bundle: bundle, seenLessonIDs: [lesson.id])
    )
}

private func contrastSession(showsPronunciation: Bool, voiceOver: Bool = false) -> LessonSession {
    let items = contrastItems()
    let words = items.filter { $0.kind != .letter }
    let letters = items.filter { $0.kind == .letter }
    let lesson = Lesson(
        id: lessonID("l-contrast"),
        title: "contrast",
        items: words.map { LessonItemRef(item: $0.id, role: .introduce) },
        letters: letters.map(\.id)
    )
    let bundle = makeBundle(
        items: items,
        units: [CourseUnit(id: unitID("u-contrast"), track: "main", title: "contrast", lessons: [lesson])]
    )
    var rng = SplitMix64(seed: 2)
    return LessonSessionBuilder.build(
        for: lesson.id,
        in: bundle,
        seenLessonIDs: [lesson.id],
        maxQuestions: nil,
        releasedUnitIDs: [lesson.id].compactMap { _ in unitID("u-contrast") },
        showsPronunciation: showsPronunciation,
        voiceOver: voiceOver,
        using: &rng
    )
}

private func contrastItems() -> [ContentItem] {
    [
        word("e-door", "در", "door"),
        word("e-fever", "تب", "fever"),
        word("e-on", "بر", "on"),
        letter("e-dal", "د", "the letter da"),
        letter("e-ddal", "ډ", "the letter da with a ring"),
        letter("e-te", "ت", "the letter ta"),
        letter("e-tte", "ټ", "the letter ta with a ring"),
        letter("e-re", "ر", "the letter ra"),
        letter("e-rre", "ړ", "the letter ra with a ring"),
        letter("e-zal", "ذ", "the letter za, dot on da"),
        letter("e-ze", "ز", "the letter za, dot on ra"),
        letter("e-be", "ب", "the letter ba"),
    ]
}

private func choiceTasks(in session: LessonSession, kind: TaskKind) -> [QuizTask] {
    session.tasks.compactMap { task in
        guard case .choice(let quiz) = task.payload, quiz.kind == kind else { return nil }
        return quiz
    }
}

private func word(_ id: String, _ pashto: String, _ en: String) -> ContentItem {
    makeItem(id, pashto: pashto, translit: en + "-scholar", pronunciation: en, en: en)
}

private func releasedOrderingItems(in bundle: ContentBundle) throws -> [ContentItem] {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
        url.deleteLastPathComponent()
    }
    url.appendPathComponent("content")
    url.appendPathComponent("release-units.json")
    let file = try JSONDecoder().decode(ReleaseUnitsFile.self, from: Data(contentsOf: url))
    let released = Set(file.units)
    var ids: Set<ItemID> = []
    for unit in bundle.units where released.contains(unit.id.rawValue) {
        for lesson in unit.lessons {
            for ref in lesson.items {
                ids.insert(ref.item)
            }
            for letter in lesson.letters {
                ids.insert(letter)
            }
        }
    }
    return bundle.items.filter { ids.contains($0.id) }
}

private struct ReleaseUnitsFile: Decodable {
    let units: [String]
}

/// Spellings Farhad approved on 2026-11-03. Compared character for character.
private let approvedTilePronunciations: [String: String] = [
    "دا": "daa",
    "دی": "day",
    "ده": "da",
    "د": "da",
    "زه": "za",
    "ته": "ta",
    "زما": "zmaa",
    "ستا": "staa",
    "تاسو": "TAA-so",
    "ستاسو": "STAA-so",
    "هغه": "ha-GHA",
    "یم": "yam",
    "یاست": "yaast",
    "یې": "ye",
    "ښه": "kha",
    "څوک": "tsok",
    "څه": "tsa",
    "څنګه": "TSAN-ga",
    "دې": "dey",
    "کوم": "koom",
    "ځای": "dzaay",
    "نوم": "noom",
    "مور": "mor",
    "پلار": "plaar",
    "ورور": "wror",
    "خور": "khor",
    "احمد": "AH-mad",
    "افغان": "af-GHAAN",
    "افغانه": "af-GHAA-na",
    "ښوونکی": "kho-WOON-kay",
    "له": "la",
    "ناروې": "naar-WEY",
    "څخه": "TSA-kha",
    "پښتو": "pakh-TO",
    "زده کوم": "zda ka-WAM",
]

private func letter(_ id: String, _ pashto: String, _ en: String) -> ContentItem {
    makeItem(
        id,
        kind: .letter,
        pashto: pashto,
        translit: en,
        pronunciation: en,
        en: en,
        name: pashto + "ال",
        forms: LetterForms(isolated: pashto, initial: pashto, medial: pashto, final: pashto),
        sound: en
    )
}
