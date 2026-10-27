import Foundation
import Testing
@testable import PashtoCore

struct ContentValidatorTests {
    @Test func validWordProducesNoIssues() {
        #expect(validate(makeBundle(items: [makeItem()])).isEmpty)
    }

    @Test func releaseModeMatchesAuthoringUntilTheToolExists() {
        let bundle = makeBundle(items: [makeItem()])
        #expect(validate(bundle, mode: .release) == validate(bundle, mode: .authoring))
    }

    @Test func yehInsideAWordFailsAndYehAtTheEndIsAccepted() {
        let inside = makeBundle(items: [makeItem(pashto: "\u{064A}\u{0633}\u{0644}\u{0627}\u{0645}")])
        let insideIssues = validate(inside)
        #expect(insideIssues.count == 1)
        #expect(insideIssues.first?.message.contains("U+064A") == true)

        let end = makeItem(
            pashto: "\u{0645}\u{0647}\u{0631}\u{0628}\u{0627}\u{0646}\u{064A}",
            translit: "mehrab\u{0101}n\u{00ED}",
            pronunciation: "meh-ra-baa-NEE",
            en: "kindness"
        )
        #expect(validate(makeBundle(items: [end])).isEmpty)
    }

    @Test func arabicKafAlefMaksuraAndPersianGafFail() {
        #expect(validate(makeBundle(items: [makeItem(pashto: "\u{0643}")])).first?.message.contains("U+0643") == true)
        #expect(validate(makeBundle(items: [makeItem(pashto: "\u{0649}")])).first?.message.contains("U+0649") == true)
        let gaf = validate(makeBundle(items: [makeItem(pashto: "\u{06AF}")]))
        #expect(gaf.count == 1)
        #expect(gaf.first?.message.contains("U+06AB") == true)
    }

    @Test func nonNFCInvisibleMarksDigitsAndDoubleSpaceFail() {
        let composed = validate(makeBundle(items: [makeItem(pashto: "\u{0627}\u{0654}")]))
        #expect(composed.count == 1)
        #expect(composed.first?.message.contains("NFC") == true)

        for sample in ["\u{200C}", "\u{00A0}", "\u{0640}", "  ", "1", "\u{0660}", "\u{06F0}"] {
            let issues = validate(makeBundle(items: [makeItem(pashto: "سلام\(sample)")]))
            #expect(!issues.isEmpty, "expected an issue for \(sample)")
        }
    }

    @Test func acuteOnANonVowelFailsAndCaronIsAccepted() {
        let acute = validate(makeBundle(items: [makeItem(translit: "\u{01F5}a", pronunciation: "ga")]))
        #expect(acute.count == 1)
        #expect(acute.first?.field == "translit")
        #expect(acute.first?.message.contains("not a vowel") == true)

        let caron = makeItem(translit: "\u{01E7}", pronunciation: "g")
        #expect(validate(makeBundle(items: [caron])).isEmpty)
    }

    @Test func stressMarksHyphenAsOneWordAndSkipsLetters() {
        let rule = PashtoStressRule()
        let list = standardUnstressed

        #expect(!rule.issues(in: "w\u{0259}k\u{1E5B}\u{0259}y", unstressedWords: list, id: "e-1").isEmpty)
        #expect(rule.issues(in: "w\u{0259}\u{0301}k\u{1E5B}\u{0259}\u{0301}y", unstressedWords: list, id: "e-1").first?.message.contains("2 stress marks") == true)
        #expect(rule.issues(in: "as-sal\u{0101}\u{0301}m", unstressedWords: list, id: "e-1").isEmpty)
        #expect(rule.issues(in: "as-sal\u{0101}m", unstressedWords: list, id: "e-1").first?.message.contains("no stress mark") == true)
        #expect(rule.issues(in: "\u{00E1}s-sal\u{0101}\u{0301}m", unstressedWords: list, id: "e-1").first?.message.contains("2 stress marks") == true)
        #expect(rule.issues(in: "z\u{0259}", unstressedWords: list, id: "e-1").isEmpty)
        #expect(rule.issues(in: "na", unstressedWords: list, id: "e-1").isEmpty)

        let perfective = rule.issues(in: "zda k\u{1E5B}\u{0259}m", unstressedWords: list, id: "e-1")
        #expect(perfective.count == 1)
        #expect(perfective.first?.severity == .review)

        let question = "t\u{0259} d\u{0259} kum dz\u{0101}y ye?"
        #expect(rule.issues(in: question, unstressedWords: list, id: "e-1").isEmpty)

        let alif = makeItem(
            "e-letter-alif",
            kind: .letter,
            pashto: "ا",
            translit: "alif",
            pronunciation: "alif",
            en: "alif",
            name: "الف",
            forms: LetterForms(isolated: "ا", initial: "ا", medial: "ا", final: "ا"),
            sound: "a"
        )
        #expect(validate(makeBundle(items: [alif])).isEmpty)
    }

    @Test func unstressedListRequiresOneSyllableFromTheTable() {
        let rule = PashtoStressRule()
        #expect(rule.unstressedListIssues(standardUnstressed, tableTransliterations: [standardUnstressed.joined()]).isEmpty)

        let long = rule.unstressedListIssues(["sal\u{0101}m"], tableTransliterations: ["sal\u{0101}m"])
        #expect(long.count == 1)
        #expect(long.first?.message.contains("one syllable") == true)

        let unknown = rule.unstressedListIssues(["še", "qa"], tableTransliterations: ["še"])
        #expect(unknown.count == 1)
        #expect(unknown.first?.message.contains("qa") == true)
    }

    @Test func pronunciationSyllablesAndWordCount() {
        let translit = "man\u{00E1}na"
        #expect(validate(makeBundle(items: [makeItem(translit: translit, pronunciation: "ma-NA-na")])).isEmpty)

        let missingUpper = validate(makeBundle(items: [makeItem(translit: translit, pronunciation: "mana-na")]))
        #expect(missingUpper.count == 1)
        #expect(missingUpper.first?.message.contains("exactly one uppercase") == true)

        let twoUpper = validate(makeBundle(items: [makeItem(translit: translit, pronunciation: "MA-NA-na")]))
        #expect(twoUpper.count == 1)
        #expect(twoUpper.first?.message.contains("exactly one uppercase") == true)

        let mixed = validate(makeBundle(items: [makeItem(pashto: "ها", translit: "kha", pronunciation: "Kha")]))
        #expect(mixed.count == 1)
        #expect(mixed.first?.message.contains("lowercase") == true)

        let perfective = validate(makeBundle(items: [makeItem(translit: "zda kram", pronunciation: "ZDA kram")]))
        #expect(perfective.count == 1)
        #expect(perfective.first?.severity == .review)

        let count = validate(makeBundle(items: [makeItem(pronunciation: "sa-LAAM extra")]))
        #expect(count.count == 1)
        #expect(count.first?.message.contains("2 words") == true)
    }

    @Test func pronunciationNoteIsRequiredForDifficultCharacters() {
        let pashto = "\u{0627}\u{0644}\u{0633}\u{0644}\u{0627}\u{0645} \u{0639}\u{0644}\u{06CC}\u{06A9}\u{0645}"
        let translit = "as-sal\u{0101}\u{0301}m alayk\u{00FA}m"
        let pronunciation = "as-sa-LAAM a-lay-KOOM"
        let withNote = makeItem(
            pashto: pashto,
            translit: translit,
            pronunciation: pronunciation,
            pronunciationNote: "ع is not pronounced as a separate sound."
        )
        #expect(validate(makeBundle(items: [withNote], difficult: ["\u{0639}"])).isEmpty)

        let missing = makeItem(pashto: pashto, translit: translit, pronunciation: pronunciation)
        let missingIssues = validate(makeBundle(items: [missing], difficult: ["\u{0639}"]))
        #expect(missingIssues.count == 1)
        #expect(missingIssues.first?.field == "pronunciationNote")

        let empty = makeItem(pashto: pashto, translit: translit, pronunciation: pronunciation, pronunciationNote: "   ")
        #expect(validate(makeBundle(items: [empty], difficult: ["\u{0639}"])).count == 1)
    }

    @Test func unknownKeysAndPartialAudioFailDecoding() {
        expectDecodeFailure(
            ContentItem.self,
            itemJSON(extra: #""pronounciationNote": "x","#),
            mentioning: "pronounciationNote"
        )
        expectDecodeFailure(
            ContentItem.self,
            itemJSON(extra: #""audio": {},"#),
            mentioning: "normal"
        )
    }

    @Test func verifiedRequiresSignerAndISODate() {
        let unsigned = makeItem(verification: Verification(status: .verified, checkedBy: "farhad"))
        let unsignedIssues = validate(makeBundle(items: [unsigned]))
        #expect(unsignedIssues.count == 1)
        #expect(unsignedIssues.first?.field == "verification.checkedOn")

        let blankSigner = makeItem(verification: Verification(status: .verified, checkedBy: " ", checkedOn: "2026-10-27"))
        #expect(validate(makeBundle(items: [blankSigner])).first?.field == "verification.checkedBy")

        let badDay = makeItem(verification: Verification(status: .verified, checkedBy: "farhad", checkedOn: "2026-02-30"))
        #expect(validate(makeBundle(items: [badDay])).first?.field == "verification.checkedOn")

        let dated = makeItem(verification: Verification(status: .verified, checkedBy: "farhad", checkedOn: "2026-10-27T00:00:00Z"))
        #expect(validate(makeBundle(items: [dated])).isEmpty)
        #expect(ISO8601Date.isValid("2024-02-29"))
        #expect(!ISO8601Date.isValid("2026-02-29"))
        #expect(!ISO8601Date.isValid("1900-02-29"))
        #expect(ISO8601Date.isValid("2000-02-29"))
    }

    @Test func tokensJoinWithoutSentencePunctuation() {
        let pashto = "\u{0632}\u{0647} \u{06CC}\u{0645}"
        let tokens = ["\u{0632}\u{0647}", "\u{06CC}\u{0645}"]
        let phrase = makeItem(
            pashto: pashto + "\u{061F}",
            translit: "z\u{0259} y\u{0259}m",
            pronunciation: "za yam",
            tokens: tokens,
            acceptedOrders: [[1, 0]]
        )
        #expect(validate(makeBundle(items: [phrase])).isEmpty)

        let marked = makeItem(
            pashto: pashto,
            translit: "z\u{0259} y\u{0259}m",
            pronunciation: "za yam",
            tokens: ["\u{0632}\u{0647}\u{061F}", "\u{06CC}\u{0645}"]
        )
        #expect(validate(makeBundle(items: [marked])).first?.message.contains("\u{061F}") == true)

        let comma = makeItem(
            pashto: pashto,
            translit: "z\u{0259} y\u{0259}m",
            pronunciation: "za yam",
            tokens: ["\u{0632}\u{0647}\u{060C}", "\u{06CC}\u{0645}"]
        )
        #expect(validate(makeBundle(items: [comma])).contains { $0.message.contains("\u{060C}") })

        let badOrder = makeItem(
            pashto: pashto,
            translit: "z\u{0259} y\u{0259}m",
            pronunciation: "za yam",
            tokens: tokens,
            acceptedOrders: [[0, 0], [0, 1]]
        )
        let orderIssues = validate(makeBundle(items: [badOrder]))
        #expect(orderIssues.count == 2)
        #expect(orderIssues.allSatisfy { $0.field == "acceptedOrders" })
    }

    @Test func duplicateIDsMeaningsAndLessonGlosses() {
        let first = makeItem("e-salam", en: "hello")
        let second = makeItem("e-salam-2", pashto: "نه", translit: "na", pronunciation: "na", en: "hello")
        let sameLesson = validate(makeBundle(items: [first, second]))
        #expect(sameLesson.count == 1)
        #expect(sameLesson.first?.message.contains("l-greetings-1") == true)

        let otherLesson = Lesson(
            id: lessonID("l-greetings-2"),
            title: "Next",
            items: [LessonItemRef(item: second.id, role: .introduce)]
        )
        let split = makeBundle(
            items: [first, second],
            units: [
                CourseUnit(
                    id: unitID("u-greetings"),
                    track: "main",
                    title: "Greetings",
                    lessons: [
                        Lesson(id: lessonID("l-greetings-1"), title: "One", items: [LessonItemRef(item: first.id, role: .introduce)]),
                        otherLesson,
                    ]
                ),
            ]
        )
        #expect(validate(split).isEmpty)

        let twin = makeItem("e-salam-2", en: "hello")
        let global = validate(makeBundle(items: [first, twin], units: [
            CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [
                Lesson(id: lessonID("l-greetings-1"), title: "One", items: [LessonItemRef(item: first.id, role: .introduce)]),
                Lesson(id: lessonID("l-greetings-2"), title: "Two", items: [LessonItemRef(item: twin.id, role: .introduce)]),
            ]),
        ]))
        #expect(global.contains { $0.field == "pashto" && $0.message.contains("e-salam") })

        let duplicated = validate(makeBundle(items: [
            first,
            makeItem("e-salam", pashto: "نه", translit: "na", pronunciation: "na", en: "no"),
        ]))
        #expect(duplicated.contains { $0.field == "id" })
    }

    @Test func slashGlossesAreReviewUnlessGrouped() {
        let trip = makeItem("e-trip", pashto: "ښه", translit: "x\u{030C}a", pronunciation: "kha", en: "have a good trip / goodbye", pronunciationNote: "ښ")
        let bye = makeItem("e-bye", pashto: "نه", translit: "na", pronunciation: "na", en: "goodbye")
        let review = validate(makeBundle(items: [trip, bye], difficult: ["ښ"]))
        #expect(review.count == 1)
        #expect(review.first?.severity == .review)

        let grouped = validate(makeBundle(
            items: [trip, bye],
            difficult: ["ښ"],
            groups: [[trip.id, bye.id]]
        ))
        #expect(grouped.isEmpty)
    }

    @Test func responsesNeedDistinctUsage() {
        let greeting = makeItem()
        let first = makeItem("e-reply", pashto: "نه", translit: "na", pronunciation: "na", en: "one", responseTo: "e-salam")
        let second = makeItem("e-other", pashto: "هو", translit: "ho", pronunciation: "ho", en: "two", responseTo: "e-salam")
        let clashing = validate(makeBundle(items: [greeting, first, second]))
        #expect(clashing.count == 1)
        #expect(clashing.first?.field == "responseTo")

        let distinct = makeItem(
            "e-other",
            pashto: "هو",
            translit: "ho",
            pronunciation: "ho",
            en: "two",
            usage: "informal",
            responseTo: "e-salam"
        )
        #expect(validate(makeBundle(items: [greeting, first, distinct])).isEmpty)

        let turns = Lesson(
            id: lessonID("l-greetings-1"),
            title: "Hello",
            items: [greeting, first].map { LessonItemRef(item: $0.id, role: .introduce) },
            dialogs: [Dialog(id: dialogID("d-greetings-1"), turns: [
                DialogTurn(speaker: "A", item: greeting.id),
                DialogTurn(speaker: "B", item: first.id),
                DialogTurn(speaker: "B", item: first.id),
            ])]
        )
        let script = makeBundle(
            items: [greeting, first],
            units: [CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [turns])]
        )
        #expect(validate(script).isEmpty)
    }

    @Test func introductionAndSoundExampleRules() {
        let orphan = validate(makeBundle(
            items: [makeItem()],
            units: [CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [
                Lesson(id: lessonID("l-greetings-1"), title: "Empty", items: []),
            ])]
        ))
        #expect(orphan.count == 1)
        #expect(orphan.first?.message.contains("not introduced") == true)

        let twice = makeBundle(
            items: [makeItem()],
            units: [CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [
                Lesson(id: lessonID("l-greetings-1"), title: "One", items: [LessonItemRef(item: itemID("e-salam"), role: .introduce)]),
                Lesson(id: lessonID("l-greetings-2"), title: "Two", items: [LessonItemRef(item: itemID("e-salam"), role: .introduce)]),
            ])]
        )
        #expect(validate(twice).first?.message.contains("introduced in") == true)

        let example = makeItem("e-tol", pashto: "ټول", translit: "\u{1E6D}ol", pronunciation: "tol", pronunciationNote: "ټ")
        let sounds = CourseUnit(id: unitID("u-sounds"), track: "main", title: "Sounds", lessons: [
            Lesson(id: lessonID("l-sounds-1"), title: "Sounds", items: [
                LessonItemRef(item: example.id, role: .soundExample, sound: "ṭ"),
            ]),
        ])
        #expect(validate(makeBundle(items: [example], units: [sounds], difficult: ["ټ"])).isEmpty)

        let later = CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [
            Lesson(id: lessonID("l-greetings-1"), title: "Later", items: [
                LessonItemRef(item: example.id, role: .soundExample, sound: "ṭ"),
            ]),
        ])
        let outside = validate(makeBundle(items: [example], units: [sounds, later], difficult: ["ټ"]))
        #expect(outside.count == 1)
        #expect(outside.first?.field == "role")

        let quiet = LessonItemRef(item: example.id, role: .soundExample, sound: " ")
        let missingSound = validate(makeBundle(
            items: [example],
            units: [CourseUnit(id: unitID("u-sounds"), track: "main", title: "Sounds", lessons: [
                Lesson(id: lessonID("l-sounds-1"), title: "Sounds", items: [quiet]),
            ])],
            difficult: ["ټ"]
        ))
        #expect(missingSound.count == 1)
        #expect(missingSound.first?.field == "sound")
    }

    @Test func lettersAreIntroducedByTheLettersArray() {
        let alif = makeItem(
            "e-letter-alif",
            kind: .letter,
            pashto: "ا",
            translit: "alif",
            pronunciation: "alif",
            en: nil,
            name: "الف"
        )
        let issues = validate(makeBundle(items: [alif]))
        #expect(issues.map(\.field) == ["en", "forms", "sound"])

        let wordInLetters = validate(makeBundle(
            items: [makeItem()],
            units: [CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [
                Lesson(id: lessonID("l-greetings-1"), title: "Letters", items: [], letters: [itemID("e-salam")]),
            ])]
        ))
        #expect(wordInLetters.count == 1)
        #expect(wordInLetters.first?.field == "letters")
    }

    @Test func aDifferentStressRuleReplacesThePashtoRule() {
        let bundle = makeBundle(items: [makeItem(translit: "w\u{0259}k\u{1E5B}\u{0259}y", pronunciation: "wa-KRAY")])
        let issues = ContentValidator.validate(bundle, mode: .authoring, stress: StubStressRule())
        #expect(issues.count == 1)
        #expect(issues.first?.severity == .review)
        #expect(issues.first?.message == "stub")
    }
}

private struct StubStressRule: StressRule {
    func issues(in translit: String, unstressedWords: [String], id: String?) -> [ValidationIssue] {
        [ValidationIssue(id: id, field: "translit", message: "stub", severity: .review)]
    }
}

private func itemJSON(extra: String) -> String {
    """
    {
      "id": "e-salam",
      "kind": "word",
      "pashto": "سلام",
      "translit": "salām",
      "pronunciation": "sa-LAAM",
      "en": "hello",
      \(extra)
      "verification": {"status": "draft"}
    }
    """
}

private func expectDecodeFailure<T: Decodable>(_ type: T.Type, _ json: String, mentioning needle: String) {
    do {
        _ = try JSONDecoder().decode(T.self, from: Data(json.utf8))
        Issue.record("Expected \(T.self) to reject the JSON")
    } catch {
        #expect(String(describing: error).contains(needle), "\(error)")
    }
}
