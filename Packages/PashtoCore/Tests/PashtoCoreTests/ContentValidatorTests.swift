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

    @Test func yehBeforePunctuationIsTheEndOfTheWord() {
        let translit = "mehrab\u{0101}n\u{00ED}"
        let pronunciation = "meh-ra-baa-NEE"
        let word = "\u{0645}\u{0647}\u{0631}\u{0628}\u{0627}\u{0646}\u{064A}"
        let samples = [
            word + "\u{061F}",
            word + "\u{060C}",
            "\u{00AB}" + word + "\u{00BB}",
            "\u{064A}\u{061F}\u{0633}\u{0644}\u{0627}\u{0645}",
        ]
        for pashto in samples {
            let item = makeItem(pashto: pashto, translit: translit, pronunciation: pronunciation, en: "kindness")
            #expect(validate(makeBundle(items: [item])).isEmpty, "expected \(pashto) to pass")
        }
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

        for sample in ["\u{200C}", "\u{00A0}", "\u{0640}", "  "] {
            let issues = validate(makeBundle(items: [makeItem(pashto: "سلام\(sample)")]))
            #expect(!issues.isEmpty, "expected an issue for \(sample)")
        }
        // Digits stay an error until a numbers unit is agreed.
        for sample in ["1", "\u{0660}", "\u{06F0}"] {
            let issues = validate(makeBundle(items: [makeItem(pashto: "سلام\(sample)")]))
            #expect(issues.contains { $0.message.contains("digit") }, "expected a digit issue for \(sample)")
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

    @Test func unhyphenatedMultiSyllablePronunciationFails() {
        let spoken = validate(makeBundle(items: [makeItem(pronunciation: "salaam")]))
        #expect(spoken.count == 1)
        #expect(spoken.first?.field == "pronunciation")
        #expect(spoken.first?.message == "\"salaam\" needs a hyphen and one uppercase syllable. The transliteration has 2 syllables.")
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

    @Test func aMissingIDIsAnErrorInEveryMode() {
        let reply = makeItem("e-reply", pashto: "نه", translit: "na", pronunciation: "na", en: "no", responseTo: "e-missing")
        let lesson = Lesson(
            id: lessonID("l-greetings-1"),
            title: "Hello",
            items: [
                LessonItemRef(item: reply.id, role: .introduce),
                LessonItemRef(item: itemID("e-gone"), role: .introduce),
            ]
        )
        let bundle = makeBundle(
            items: [reply],
            units: [CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [lesson])]
        )
        for mode in [ValidationMode.authoring, ValidationMode.release] {
            let issues = validate(bundle, mode: mode)
            let missing = issues.filter { $0.severity == .error && $0.message.contains("does not exist") }
            #expect(missing.contains { $0.field == "responseTo" && $0.message.contains("e-missing") })
            #expect(missing.contains { $0.field == "items" && $0.message.contains("e-gone") })
        }
    }

    @Test func anEmptyLessonIsAnErrorInEveryMode() {
        let lesson = Lesson(id: lessonID("l-greetings-1"), title: "Empty", items: [])
        let bundle = makeBundle(
            items: [],
            units: [CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [lesson])]
        )
        for mode in [ValidationMode.authoring, ValidationMode.release] {
            let issues = validate(bundle, mode: mode)
            #expect(issues.contains { $0.severity == .error && $0.id == "l-greetings-1" && $0.message.contains("is empty") })
        }

        let draft = makeItem("e-draft", pashto: "نه", translit: "na", pronunciation: "na", en: "no")
        let onlyDraft = makeBundle(
            items: [draft],
            units: [CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [
                Lesson(id: lessonID("l-greetings-2"), title: "Drafts", items: [LessonItemRef(item: draft.id, role: .introduce)]),
            ])]
        )
        let filtered = ContentFilter.devBuild(onlyDraft)
        let afterFilter = validate(filtered)
        #expect(filtered.units[0].lessons[0].items.isEmpty)
        #expect(afterFilter.contains { $0.severity == .error && $0.message.contains("l-greetings-2") && $0.message.contains("is empty") })
    }

    @Test func introductionAndSoundExampleRules() {
        let orphan = validate(makeBundle(
            items: [makeItem()],
            units: [CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [
                Lesson(id: lessonID("l-greetings-1"), title: "Empty", items: []),
            ])]
        ))
        #expect(orphan.count == 2)
        #expect(orphan.contains { $0.message.contains("is empty") })
        #expect(orphan.contains { $0.message.contains("not introduced") })

        let twice = makeBundle(
            items: [makeItem()],
            units: [CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [
                Lesson(id: lessonID("l-greetings-1"), title: "One", items: [LessonItemRef(item: itemID("e-salam"), role: .introduce)]),
                Lesson(id: lessonID("l-greetings-2"), title: "Two", items: [LessonItemRef(item: itemID("e-salam"), role: .introduce)]),
            ])]
        )
        #expect(validate(twice).first?.message.contains("introduced in") == true)

        let example = makeItem("e-tol", pashto: "ټول", translit: "\u{1E6D}ol", pronunciation: "tol", pronunciationNote: "ټ")
        let soundRef = LessonItemRef(item: example.id, role: .soundExample, sound: "ṭ")
        let sounds = CourseUnit(id: unitID("u-sounds"), track: "main", title: "Sounds", lessons: [
            Lesson(id: lessonID("l-sounds-1"), title: "Sounds", items: [soundRef]),
        ])
        let soundOnly = validate(makeBundle(items: [example], units: [sounds], difficult: ["ټ"]))
        #expect(soundOnly.count == 1)
        #expect(soundOnly.first?.message == "e-tol is not introduced in a lesson.")

        let introducedInSounds = CourseUnit(id: unitID("u-sounds"), track: "main", title: "Sounds", lessons: [
            Lesson(id: lessonID("l-sounds-1"), title: "Sounds", items: [
                soundRef,
                LessonItemRef(item: example.id, role: .introduce),
            ]),
        ])
        let soundsIntroduction = validate(makeBundle(items: [example], units: [introducedInSounds], difficult: ["ټ"]))
        #expect(soundsIntroduction.count == 1)
        #expect(soundsIntroduction.first?.message == "e-tol is not introduced in a lesson.")

        let greetings = CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [
            Lesson(id: lessonID("l-greetings-1"), title: "Later", items: [
                LessonItemRef(item: example.id, role: .introduce),
            ]),
        ])
        #expect(validate(makeBundle(items: [example], units: [sounds, greetings], difficult: ["ټ"])).isEmpty)

        let alsoInSounds = CourseUnit(id: unitID("u-sounds"), track: "main", title: "Sounds", lessons: [
            Lesson(id: lessonID("l-sounds-1"), title: "Sounds", items: [
                soundRef,
                LessonItemRef(item: example.id, role: .introduce),
            ]),
        ])
        let twiceAcrossUnits = validate(makeBundle(items: [example], units: [alsoInSounds, greetings], difficult: ["ټ"]))
        #expect(twiceAcrossUnits.count == 1)
        #expect(twiceAcrossUnits.first?.message == "e-tol is introduced in l-sounds-1, l-greetings-1. An item is introduced once.")

        let later = CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [
            Lesson(id: lessonID("l-greetings-1"), title: "Later", items: [soundRef]),
        ])
        let outside = validate(makeBundle(items: [example], units: [sounds, later], difficult: ["ټ"]))
        #expect(outside.map(\.field) == ["role", "role"])
        #expect(outside[0].message.contains("first unit"))
        #expect(outside[1].message == "e-tol is not introduced in a lesson.")

        let quiet = LessonItemRef(item: example.id, role: .soundExample, sound: " ")
        let missingSound = validate(makeBundle(
            items: [example],
            units: [CourseUnit(id: unitID("u-sounds"), track: "main", title: "Sounds", lessons: [
                Lesson(id: lessonID("l-sounds-1"), title: "Sounds", items: [quiet]),
            ])],
            difficult: ["ټ"]
        ))
        #expect(missingSound.map(\.field) == ["sound", "role"])
        #expect(missingSound[1].message == "e-tol is not introduced in a lesson.")
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

    @Test func pashtoIsArabicScriptWithoutEdgeSpace() {
        let latin = validate(makeBundle(items: [makeItem(pashto: "سلامabc")]))
        #expect(latin.map(\.message) == [
            "pashto contains \"a\" (U+0061), which is not Arabic script.",
            "pashto contains \"b\" (U+0062), which is not Arabic script.",
            "pashto contains \"c\" (U+0063), which is not Arabic script.",
        ])

        let spaced = validate(makeBundle(items: [makeItem(pashto: " سلام ")]))
        #expect(spaced.count == 1)
        #expect(spaced.first?.message == "pashto has leading or trailing space.")
    }

    @Test func difficultCharactersMustBeOneCharacter() {
        let issues = validate(makeBundle(items: [makeItem()], difficult: ["ab"]))
        #expect(issues.count == 1)
        #expect(issues.first?.field == "difficultCharacters")
        #expect(issues.first?.message == "difficultCharacters entry \"ab\" must be one character.")
    }

    @Test func tatweelIsAllowedOnlyInLetterForms() {
        let dze = makeItem(
            "e-letter-dze",
            kind: .letter,
            pashto: "ځ",
            translit: "dze",
            pronunciation: "dze",
            en: "dze",
            pronunciationNote: "ځ",
            name: "ځ",
            forms: LetterForms(
                isolated: "ځ",
                initial: "ځ",
                medial: "\u{0640}ځ\u{0640}",
                final: "ځ"
            ),
            sound: "dz"
        )
        #expect(validate(makeBundle(items: [dze], difficult: ["ځ"])).isEmpty)

        let alif = makeItem(
            "e-letter-alif",
            kind: .letter,
            pashto: "ا",
            translit: "alif",
            pronunciation: "alif",
            en: "alif",
            name: "الف",
            forms: LetterForms(isolated: "ا", initial: "\u{0640}ا", medial: "\u{0640}ا", final: "ا"),
            sound: "a"
        )
        #expect(validate(makeBundle(items: [alif])).isEmpty)

        let inPashto = validate(makeBundle(items: [makeItem(pashto: "س\u{0640}لام")]))
        #expect(inPashto.contains { $0.field == "pashto" && $0.message.contains("tatweel (U+0640)") })

        let named = makeItem(
            "e-letter-alif",
            kind: .letter,
            pashto: "ا",
            translit: "alif",
            pronunciation: "alif",
            en: "alif",
            name: "ال\u{0640}ف",
            forms: LetterForms(isolated: "ا", initial: "ا", medial: "ا", final: "ا"),
            sound: "a"
        )
        #expect(validate(makeBundle(items: [named])).contains { $0.field == "name" && $0.message.contains("tatweel (U+0640)") })

        let phrase = makeItem(
            pashto: "سلام نه",
            translit: "sal\u{0101}\u{0301}m na",
            pronunciation: "sa-LAAM na",
            tokens: ["س\u{0640}لام", "نه"],
            acceptedOrders: [[1, 0]]
        )
        #expect(validate(makeBundle(items: [phrase])).contains { $0.field == "tokens" && $0.message.contains("tatweel (U+0640)") })
    }

    @Test func aDifferentStressRuleReplacesThePashtoRule() {
        let bundle = makeBundle(items: [makeItem(translit: "w\u{0259}k\u{1E5B}\u{0259}y", pronunciation: "wa-KRAY")])
        let issues = ContentValidator.validate(bundle, mode: .authoring, stress: StubStressRule())
        #expect(issues.count == 1)
        #expect(issues.first?.severity == .review)
        #expect(issues.first?.message == "stub")
    }

    @Test func injectedStressRuleOwnsSyllablesAndTheUnstressedList() {
        let bundle = makeBundle(
            items: [makeItem(pronunciation: "salaam")],
            unstressed: ["sal\u{0101}m"]
        )
        let swapped = ContentValidator.validate(bundle, mode: .authoring, stress: PermissiveStressRule())
        #expect(swapped.isEmpty)

        let pashto = validate(bundle)
        #expect(pashto.map(\.field) == ["unstressedWords", "pronunciation"])
        #expect(pashto[0].message.contains("one syllable"))
        #expect(pashto[1].message.contains("salaam"))
    }
}

private struct StubStressRule: StressRule {
    func issues(in translit: String, unstressedWords: [String], id: String?) -> [ValidationIssue] {
        [ValidationIssue(id: id, field: "translit", message: "stub", severity: .review)]
    }

    func syllableCount(in word: String) -> Int { 1 }

    func unstressedListIssues(_ words: [String], tableTransliterations: [String]) -> [ValidationIssue] { [] }
}

private struct PermissiveStressRule: StressRule {
    func issues(in translit: String, unstressedWords: [String], id: String?) -> [ValidationIssue] { [] }

    func syllableCount(in word: String) -> Int { 1 }

    func unstressedListIssues(_ words: [String], tableTransliterations: [String]) -> [ValidationIssue] { [] }
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
