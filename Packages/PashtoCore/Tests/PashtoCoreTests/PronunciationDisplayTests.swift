import Foundation
import Testing
@testable import PashtoCore

struct PronunciationDisplayTests {
    @Test func examplesLowercaseTheStoredFieldAndWeightTheStressedSyllable() {
        expect(
            "ho-TAL CHER-ta day?",
            text: ["ho", hyphen, "tal", " ", "cher", hyphen, "ta", " ", "day?"],
            stressed: [false, false, true, false, true, false, false, false, false]
        )
        expect(
            "ko-ra-NAY",
            text: ["ko", hyphen, "ra", hyphen, "nay"],
            stressed: [false, false, false, false, true]
        )
        expect(
            "ma-NA-na",
            text: ["ma", hyphen, "na", hyphen, "na"],
            stressed: [false, false, true, false, false]
        )
        expect(
            "sa-LAAM",
            text: ["sa", hyphen, "laam"],
            stressed: [false, false, true]
        )
        expect(
            "DE-ra kha",
            text: ["de", hyphen, "ra", " ", "kha"],
            stressed: [true, false, false, false, false]
        )
        expect("plaar", text: ["plaar"], stressed: [false])

        #expect(PronunciationDisplay.boldTextUnderlineThickness == 2)
        #expect(PronunciationDisplay.boldTextUnderlineOffset == 4)
        #expect(PronunciationDisplay.unstressedWeight == 400)
        #expect(PronunciationDisplay.stressedWeight == 700)
        #expect(PronunciationDisplay.boldTextUnstressedWeight == 600)
        #expect(PronunciationDisplay.boldTextStressedWeight == 800)
    }

    @Test func aLongWordScalesDownToTheLineAndAShortWordStaysFullSize() {
        let stored = "cha-haar-shan-BA"
        let tokens = PronunciationDisplay.tokens(in: stored)
        #expect(tokens.count == 1)
        #expect(tokens[0].runs.map(\.text).joined() == "cha\(hyphen)haar\(hyphen)shan\(hyphen)ba")
        #expect(tokens[0].runs.contains { $0.text == "ba" && $0.stressed })
        #expect(PronunciationDisplay.spoken(stored) == stored)

        let column = 140.0
        let scale = PronunciationFit.lineScale(tokenWidths: [320], availableWidth: column)
        #expect(scale < 1)
        #expect(abs((320 * scale) - column) < 0.001)
        #expect(320 * scale <= column)

        let praise = PronunciationDisplay.tokens(in: "DE-ra kha")
        #expect(praise.count == 2)
        #expect(praise[0].runs.map(\.text).joined() == "de\(hyphen)ra")
        #expect(praise[1].runs.map(\.text).joined() == "kha")
        #expect(praise[0].runs.allSatisfy { !$0.text.contains("-") })
        #expect(PronunciationFit.lineScale(tokenWidths: [70, 40], availableWidth: column) == 1)
        let shared = PronunciationFit.lineScale(tokenWidths: [320, 40], availableWidth: column)
        #expect(shared == scale)
        #expect(40 * shared < 40)

        #expect(PronunciationFit.lineScale(tokenWidths: [48], availableWidth: 180) == 1)
        #expect(PronunciationFit.lineScale(tokenWidths: [48], availableWidth: 48) == 1)
        #expect(PronunciationFit.lineScale(tokenWidths: [48], availableWidth: 0) == 1)
        #expect(PronunciationFit.lineScale(tokenWidths: [], availableWidth: 40) == 1)
    }

    @Test func aFullyUppercaseSyllableIsStressedAndPunctuationStays() {
        #expect(PronunciationDisplay.isStressedSyllable("TAL"))
        #expect(PronunciationDisplay.isStressedSyllable("NAY?"))
        #expect(!PronunciationDisplay.isStressedSyllable("day?"))
        #expect(!PronunciationDisplay.isStressedSyllable("Day"))
        #expect(!PronunciationDisplay.isStressedSyllable("?"))
        let asked = PronunciationDisplay.runs(in: "NAY?")
        #expect(asked.map(\.text) == ["nay?"])
        #expect(asked.map(\.stressed) == [true])
        #expect(asked.map { $0.weight(boldText: false) } == [700])
        #expect(asked.map { $0.underlined(boldText: true) } == [true])
    }

    @Test func hyphensStayInsideTheToken() {
        let tokens = PronunciationDisplay.tokens(in: "ho-TAL CHER-ta day?")
        #expect(tokens.count == 3)
        #expect(tokens.map { $0.runs.map(\.text).joined() } == ["ho\(hyphen)tal", "cher\(hyphen)ta", "day?"])
        for token in tokens {
            #expect(token.runs.allSatisfy { !$0.text.contains { $0.isWhitespace } })
            #expect(token.runs.allSatisfy { !$0.text.contains("-") })
        }
    }

    @Test func storedCapitalsRemainAndVoiceOverReadsThatString() throws {
        let bundle = try loadCourse().bundle
        let stored = Set(bundle.items.map(\.pronunciation))
        #expect(stored.contains("ho-TAL CHER-ta day?"))
        #expect(stored.contains("ko-ra-NAY"))
        #expect(stored.contains("ma-NA-na"))
        #expect(stored.contains("sa-LAAM"))
        #expect(CategoryCelebration.praise.pronunciation == "DE-ra kha")
        #expect(!stored.contains("ho-tal cher-ta day?"))

        for item in bundle.items {
            #expect(PronunciationDisplay.spoken(item.pronunciation) == item.pronunciation)
            let display = PronunciationDisplay.displayText(stored: item.pronunciation)
            #expect(display == item.pronunciation.lowercased().replacingOccurrences(
                of: "-",
                with: String(PronunciationDisplay.nonBreakingHyphen)
            ))
            #expect(!display.unicodeScalars.contains { (65...90).contains($0.value) })
            let runs = PronunciationDisplay.runs(in: item.pronunciation)
            for run in runs {
                #expect(run.weight(boldText: false) == (run.stressed ? 700 : 400))
                #expect(run.weight(boldText: true) == (run.stressed ? 800 : 600))
                #expect(run.underlined(boldText: false) == false)
                #expect(run.underlined(boldText: true) == run.stressed)
            }
        }
    }

    @Test func everySurfacePassesTheStoredPronunciationToTheSharedRenderer() throws {
        let root = repositoryRoot()
        let appFiles = try swiftFiles(under: root.appendingPathComponent("PashtoApp"))
        #expect(appFiles.count > 5)

        let study = try source("PashtoApp/Quiz/StudyCardScreen.swift")
        let learn = try section("struct LearnListScreen", until: nil, in: study)
        #expect(learn.contains("PronunciationText(stored: row.pronunciation"))
        #expect(learn.contains("points: pronunciationSize"))
        #expect(!learn.contains("row.displayedPronunciation"))
        let cards = try section("struct StudyCardLines", until: "struct LearnListScreen", in: study)
        #expect(cards.contains("PronunciationText(stored: card.pronunciation"))
        #expect(cards.contains("if let note = card.pronunciationNote"))

        let quiz = try source("PashtoApp/Quiz/QuizScreen.swift")
        let line = try section("struct PashtoLine", until: "private struct FitSingleWord", in: quiz)
        #expect(line.contains("PronunciationText(stored: stored"))
        #expect(!line.contains("Text(pronunciation"))
        #expect(!line.contains("Text(verbatim: pronunciation"))
        let order = try section("private func orderWords", until: "private func wordButton", in: quiz)
        #expect(order.contains("PronunciationText("))
        #expect(order.contains("stored: pronunciation"))
        #expect(quiz.contains("QuizCopy.choiceLabel"))
        #expect(quiz.contains("option.pronunciation"))

        let home = try source("PashtoApp/ContentView.swift")
        let row = try section("private struct FamilyWordRowView", until: "private struct DailyGoalRing", in: home)
        #expect(row.contains("PronunciationText("))
        #expect(row.contains("stored: pronunciation"))
        #expect(row.contains("row.accessibilityLabel"))
        let daily = try section("private struct DailyWordCard", until: "private struct DailyWordSpin", in: home)
        #expect(daily.contains("PashtoLine("))
        #expect(daily.contains("pronunciation: word.pronunciation"))
        #expect(daily.contains("pronunciationLeads: pronunciationLeads"))
        #expect(daily.contains("Lapis.wordListPashto"))
        #expect(daily.contains("DailyWordSpeech.active"))
        let celebration = try section("struct CategoryCelebrationScreen", until: "\n#Preview", in: home)
        #expect(celebration.contains("PronunciationText("))
        #expect(celebration.contains("stored: CategoryCelebration.praise.pronunciation"))

        let glyph = try source("PashtoApp/Quiz/GlyphCard.swift")
        #expect(glyph.contains("PashtoLine("))
        #expect(glyph.contains("pronunciation: side.pronunciation"))
        let match = try source("PashtoApp/Quiz/MatchingBoard.swift")
        #expect(match.contains("PashtoLine("))
        #expect(match.contains("pronunciation: spoken"))

        let renderer = try source("PashtoApp/Quiz/PronunciationText.swift")
        #expect(renderer.contains("PronunciationDisplay.tokens"))
        #expect(renderer.contains("PronunciationDisplay.spoken(stored)"))
        #expect(renderer.contains("accessibilityElement(children: .ignore)"))
        #expect(renderer.contains("accessibilityLabel(Text(verbatim: PronunciationDisplay.spoken(stored)))"))
        #expect(renderer.contains("legibilityWeight"))
        #expect(renderer.contains("boldTextUnderlineThickness"))
        #expect(renderer.contains("boldTextUnderlineOffset"))
        #expect(renderer.contains("underlined(boldText:"))
        #expect(renderer.contains("PronunciationFit.lineScale"))
        #expect(renderer.contains("typeSize: dynamicTypeSize"))
        #expect(renderer.contains("width: ideal.width * scale"))
        #expect(renderer.contains("scaleEffect(scale"))
        #expect(!renderer.contains("_ = dynamicTypeSize"))
        #expect(!renderer.contains("fixedSize(horizontal: true"))
        #expect(!renderer.contains("strikethrough"))
        #expect(!renderer.contains(".italic"))

        let banned = [
            "Text(verbatim: row.displayedPronunciation",
            "Text(verbatim: row.pronunciation",
            "Text(verbatim: card.pronunciation",
            "Text(verbatim: pronunciation",
            "Text(verbatim: drawnPronunciation",
            "Text(pronunciation",
            "displayedPronunciation",
        ]
        for url in appFiles {
            let text = try String(contentsOf: url, encoding: .utf8)
            for phrase in banned where text.contains(phrase) {
                Issue.record("\(url.lastPathComponent) still draws pronunciation with \(phrase)")
            }
        }

        let markers = ["æ", "ø", "å", "Æ", "Ø", "Å", "Bekreftet", "enhet", "uformelt", "shown in bold"]
        for relative in [
            "PashtoApp/Quiz/PronunciationText.swift",
            "Packages/PashtoCore/Sources/PashtoCore/Quiz/PronunciationDisplay.swift",
        ] {
            let text = try source(relative)
            for marker in markers where text.contains(marker) {
                Issue.record("\(relative) contains \(marker)")
            }
        }
    }

    @Test func rewrittenPronunciationNotesMatchTheApprovedText() throws {
        let bundle = try loadCourse().bundle
        let items = Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id.rawValue, $0) })
        #expect(rewrittenNotes.count == 62)
        #expect(clearedNotes.count == 61)
        #expect(Set(rewrittenNotes.keys).isDisjoint(with: Set(clearedNotes)))

        for (id, note) in rewrittenNotes {
            let item = try #require(items[id])
            #expect(item.pronunciationNote == note, "\(id)")
        }
        for id in clearedNotes {
            let item = try #require(items[id])
            #expect(item.pronunciationNote == nil, "\(id)")
        }

        let banned = ["capital", "Stress the syllable", "selected Kabul", "ḍ", "ṛ", "ṭ", "salā́m"]
        for item in bundle.items {
            guard let note = item.pronunciationNote else { continue }
            for word in banned where note.contains(word) {
                Issue.record("\(item.id.rawValue) note contains \(word)")
            }
        }

        let visibleUnits = ["u-numbers", "u-food", "u-town", "u-conversation", "u-travel", "u-time"]
        var showedNote: Set<String> = []
        for unit in bundle.units where visibleUnits.contains(unit.id.rawValue) {
            for lesson in unit.lessons where lesson.kind == .learn || lesson.kind == .phrases {
                let deck = try #require(StudyCourse.deck(for: lesson.id, in: bundle))
                for card in deck.cards {
                    let stored = items[card.itemID.rawValue]?.pronunciationNote?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if stored.isEmpty {
                        #expect(card.pronunciationNote == nil)
                    } else {
                        #expect(card.pronunciationNote == stored)
                        showedNote.insert(unit.id.rawValue)
                    }
                }
            }
        }
        #expect(showedNote == Set(visibleUnits))

        for rawUnitID in ["u-family", "u-travel", "u-time"] {
            for shows in [true, false] {
                let rows = FamilyWordList.rows(for: unitID(rawUnitID), in: bundle, showsPronunciation: shows)
                for row in rows {
                    let stored = items[row.itemID.rawValue]?.pronunciationNote ?? ""
                    if !stored.isEmpty {
                        #expect(!row.accessibilityLabel.contains(stored))
                    }
                    if let pronunciation = row.pronunciation {
                        #expect(pronunciation == items[row.itemID.rawValue]?.pronunciation)
                        #expect(PronunciationDisplay.spoken(pronunciation) == pronunciation)
                    }
                }
            }
        }

        let family = try #require(StudyCourse.deck(for: lessonID("l-family-learn-members"), in: bundle))
        let sister = try #require(family.cards.first { $0.itemID.rawValue == "e-xor" })
        let sisterNote = try #require(items[sister.itemID.rawValue]?.pronunciationNote)
        #expect(sister.pronunciationNote == sisterNote)

        let screen = try source("PashtoApp/Quiz/StudyCardScreen.swift")
        #expect(screen.contains("if let note = card.pronunciationNote"))
        #expect(!screen.contains("item.pronunciationNote"))
        let quiz = try source("PashtoApp/Quiz/QuizScreen.swift")
        let home = try source("PashtoApp/ContentView.swift")
        #expect(!quiz.contains("pronunciationNote"))
        #expect(!home.contains("pronunciationNote"))
    }

    @Test func pronunciationNoteDisplayStaysLeftToRightWithOneTipPerLine() throws {
        let bundle = try loadCourse().bundle
        let want = try #require(bundle.items.first { $0.id.rawValue == "e-tsa-ghwaa-rey" })
        let stored = try #require(want.pronunciationNote)
        let threeTips = "څ: ts as in cats. غ: gh, a voiced kh, close to French r. ړ: tongue tip curled back and flicked forward, like a quick r."
        #expect(stored == threeTips)
        #expect(PronunciationNotes.presented(stored) == stored)
        #expect(!stored.contains("\n"))
        #expect(!stored.contains(PronunciationNotes.leftToRightIsolate))
        #expect(!stored.contains(PronunciationNotes.popDirectionalIsolate))

        let lines = PronunciationNotes.lines(in: stored)
        #expect(lines == [
            "څ: ts as in cats.",
            "غ: gh, a voiced kh, close to French r.",
            "ړ: tongue tip curled back and flicked forward, like a quick r.",
        ])
        #expect(lines.joined(separator: " ") == stored)

        let display = PronunciationNotes.displayText(stored)
        #expect(display.hasPrefix(PronunciationNotes.leftToRightIsolate))
        #expect(display.hasSuffix(PronunciationNotes.popDirectionalIsolate))
        #expect(display == lines.map(PronunciationNotes.displayLine).joined(separator: "\n"))
        #expect(PronunciationNotes.spoken(display) == stored)
        #expect(want.pronunciationNote == threeTips)

        let food = try source("content/units/u-food.json")
        #expect(food.contains("\"pronunciationNote\": \"\(threeTips)\""))
        #expect(!food.contains(PronunciationNotes.leftToRightIsolate))

        let single = "څ: ts as in cats."
        #expect(PronunciationNotes.lines(in: single) == [single])
        #expect(PronunciationNotes.displayText(single) == PronunciationNotes.displayLine(single))
        #expect(!PronunciationNotes.displayText(single).contains("\n"))
        #expect(PronunciationNotes.spoken(PronunciationNotes.displayText(single)) == single)

        let voiced = "غ: gh, a voiced kh, close to French r."
        #expect(PronunciationNotes.lines(in: voiced) == [voiced])
        let english = "The vowel in za is short and weak, like the a in about."
        #expect(PronunciationNotes.lines(in: english) == [english])
        let dental = "The t is soft and dental: the tongue touches the back of the upper front teeth."
        #expect(PronunciationNotes.lines(in: dental) == [dental])
        let kabul = "Kabul: ho, not ao. In everyday speech people also say یې (ye) for yes."
        #expect(PronunciationNotes.lines(in: kabul) == [kabul])
        let mung = "ږ: in Kabul close to g in go; موږ is said mung. یو here means ‘are’, not ‘one’."
        #expect(PronunciationNotes.lines(in: mung) == [mung])
        #expect(PronunciationNotes.lines(in: "څغ: together.") == ["څغ: together."])
        #expect(PronunciationNotes.lines(in: "څ: one. څغ: two.") == ["څ: one.", "څغ: two."])

        for item in bundle.items {
            guard let note = item.pronunciationNote else { continue }
            #expect(!note.contains("\n"), "\(item.id.rawValue)")
            #expect(!note.contains(PronunciationNotes.leftToRightIsolate), "\(item.id.rawValue)")
            let drawn = PronunciationNotes.lines(in: note)
            #expect(drawn.joined(separator: " ") == note, "\(item.id.rawValue)")
            let shown = PronunciationNotes.displayText(note)
            #expect(shown.hasPrefix(PronunciationNotes.leftToRightIsolate), "\(item.id.rawValue)")
            #expect(PronunciationNotes.spoken(shown) == note, "\(item.id.rawValue)")
            if drawn.count == 1 {
                #expect(drawn == [note], "\(item.id.rawValue)")
                #expect(!shown.contains("\n"), "\(item.id.rawValue)")
            }
            #expect(PronunciationNotes.presented(note) == note)
        }

        let screen = try source("PashtoApp/Quiz/StudyCardScreen.swift")
        #expect(screen.contains("if let note = card.pronunciationNote"))
        #expect(screen.contains("PronunciationNotes.tips(in: note)"))
        #expect(screen.contains("PronunciationNotes.displayLine"))
        #expect(screen.contains("PronunciationNotes.spoken(note)"))
        #expect(screen.contains(".accessibilityElement(children: .combine)"))
        #expect(screen.contains(".environment(\\.layoutDirection, .leftToRight)"))
        #expect(!screen.contains("Text(verbatim: note)"))
    }

    @Test func pronunciationNoteSplitsLetterTipsFromPlainText() throws {
        let bundle = try loadCourse().bundle
        let three = "څ: ts as in cats. غ: gh, a voiced kh, close to French r. ړ: tongue tip curled back and flicked forward, like a quick r."
        let tips = PronunciationNotes.tips(in: three)
        #expect(tips.map(\.letter) == ["څ:", "غ:", "ړ:"])
        #expect(tips.map(\.text) == [
            "ts as in cats.",
            "gh, a voiced kh, close to French r.",
            "tongue tip curled back and flicked forward, like a quick r.",
        ])
        #expect(tips.map(\.stored).joined(separator: " ") == three)

        let one = "څ: ts as in cats."
        let oneTip = try #require(PronunciationNotes.tips(in: one).first)
        #expect(PronunciationNotes.tips(in: one).count == 1)
        #expect(oneTip.letter == "څ:")
        #expect(oneTip.text == "ts as in cats.")
        #expect(oneTip.stored == one)

        let plain = "The t is soft and dental: the tongue touches the back of the upper front teeth. It is not the English th. Short, weak vowel, like the a in about."
        #expect(PronunciationNotes.tips(in: plain) == [PronunciationTip(letter: nil, text: plain)])
        let ayn = "ع is not pronounced as a separate sound in Pashto."
        #expect(PronunciationNotes.tips(in: ayn) == [PronunciationTip(letter: nil, text: ayn)])

        let storedThree = try #require(bundle.items.first { $0.id.rawValue == "e-tsa-ghwaa-rey" }?.pronunciationNote)
        #expect(PronunciationNotes.tips(in: storedThree) == tips)
        let storedPlain = try #require(bundle.items.first { $0.id.rawValue == "e-ta" }?.pronunciationNote)
        #expect(storedPlain == plain)
        #expect(PronunciationNotes.tips(in: storedPlain).allSatisfy { $0.letter == nil })

        var plainNotes = 0
        var letters = Set<Character>()
        for item in bundle.items {
            guard let note = item.pronunciationNote else { continue }
            let drawn = PronunciationNotes.tips(in: note)
            #expect(!drawn.isEmpty, "\(item.id.rawValue)")
            #expect(drawn.map(\.stored).joined(separator: " ") == note, "\(item.id.rawValue)")
            if drawn.allSatisfy({ $0.letter == nil }) {
                plainNotes += 1
            }
            for tip in drawn {
                guard let letter = tip.letter else { continue }
                #expect(letter.hasSuffix(":"), "\(item.id.rawValue)")
                let mark = letter.dropLast()
                #expect(mark.count == 1, "\(item.id.rawValue) \(letter)")
                if let character = mark.first {
                    letters.insert(character)
                }
            }
        }
        #expect(plainNotes == 10)
        #expect(letters.count == 11)
    }

    @Test func quizCelebrationListsAndTheDailyWordKeepTheStoredPronunciation() throws {
        let bundle = try loadCourse().bundle
        let items = bundle.items
        let hello = try #require(items.first { $0.pronunciation == "sa-LAAM" })
        let face = QuizPresentation.face(
            for: QuizTask(
                kind: .meaningEnglishToPashto,
                targetID: hello.id,
                prompt: "hello",
                usage: nil,
                options: [QuizOption(itemID: hello.id, text: hello.pashto)]
            ),
            items: items,
            showsPronunciation: true,
            voiceOver: false,
            answered: false
        )
        let option = try #require(face.options.first)
        #expect(option.pronunciation == "sa-LAAM")
        #expect(PronunciationDisplay.runs(in: option.pronunciation ?? "").contains { $0.stressed && $0.weight(boldText: false) == 700 })
        #expect(QuizPresentation.spokenPronunciation(text: hello.pashto, item: hello, showsPronunciation: false) == "sa-LAAM")

        let praise = PronunciationDisplay.runs(in: CategoryCelebration.praise.pronunciation)
        #expect(praise.first?.text == "de")
        #expect(praise.first?.stressed == true)
        #expect(praise.first?.weight(boldText: false) == 700)
        #expect(praise.first?.underlined(boldText: true) == true)

        let members = try #require(LearnList.make(
            for: lessonID("l-basics-learn-polite"),
            in: bundle,
            finishedLessonIDs: [],
            audioItemIDs: []
        ))
        let thanks = try #require(members.rows.first { $0.pronunciation == "ma-NA-na" })
        #expect(thanks.pronunciation == "ma-NA-na")
        let thanksRuns = PronunciationDisplay.runs(in: thanks.pronunciation)
        #expect(thanksRuns.map(\.stressed) == [false, false, true, false, false])
        #expect(thanksRuns.map { $0.weight(boldText: true) } == [600, 600, 800, 600, 600])

        let travel = try #require(LearnList.make(
            for: lessonID("l-travel-learn-around"),
            in: bundle,
            finishedLessonIDs: [],
            audioItemIDs: []
        ))
        let hotel = try #require(travel.rows.first { $0.pronunciation == "ho-TAL" })
        #expect(PronunciationDisplay.runs(in: hotel.pronunciation).contains { $0.text == "tal" && $0.stressed })

        let listed = FamilyWordList.rows(for: unitID("u-family"), in: bundle, showsPronunciation: true)
        #expect(listed.contains { $0.pronunciation == "ko-ra-NAY" })
        let familyRow = try #require(listed.first { $0.pronunciation == "ko-ra-NAY" })
        #expect(familyRow.accessibilityLabel.contains("ko-ra-NAY"))
        #expect(!familyRow.accessibilityLabel.contains("ko-ra-nay"))

        let day = LocalDay(year: 2026, month: 11, day: 12)
        let card = ReviewCard.introduced(itemID: thanks.itemID, on: day)
        let word = try #require(DailyWordSelection.select(
            cards: [card],
            in: bundle,
            releasedUnitIDs: bundle.units.map(\.id),
            on: day,
            showsPronunciation: true
        ))
        #expect(word.pronunciation == "ma-NA-na")
        #expect(DailyWordSpeech.front(pashto: word.pashto, pronunciation: word.pronunciation) == "\(word.pashto), ma-NA-na")
        #expect(!DailyWordSpeech.front(pashto: word.pashto, pronunciation: word.pronunciation).contains("bold"))
    }

    @Test func xlNoteShotsStartAtTheTopBeforeScrolling() throws {
        let tests = try source("PashtoAppScreenshots/ScreenshotTests.swift")
        let body = try section("func testXLNotes()", until: "func testXLPlainNote()", in: tests)
        let top = try #require(body.range(of: "shot(\"notes-learn-xl-top\")"))
        let note = try #require(body.range(of: "shot(\"notes-learn-xl\")"))
        let lower = try #require(body.range(of: "shot(\"notes-learn-xl-2\")"))
        let firstScroll = try #require(body.range(of: "scrollNoteDown("))
        #expect(top.lowerBound < firstScroll.lowerBound)
        #expect(firstScroll.lowerBound < note.lowerBound)
        #expect(note.lowerBound < lower.lowerBound)
        let beforeTop = body[..<top.lowerBound]
        #expect(!beforeTop.contains("showsOnScreen(tips[0].frame"))
        let afterTop = body[top.upperBound...]
        #expect(afterTop.contains("showsOnScreen(tips[0].frame"))
        #expect(afterTop.contains("waitUntil(timeout: 4)"))
        let tipWait = try #require(afterTop.range(of: "first tip did not scroll into view"))
        let noteAfterTop = try #require(afterTop.range(of: "shot(\"notes-learn-xl\")"))
        #expect(tipWait.lowerBound < noteAfterTop.lowerBound)
        let afterNote = body[note.upperBound...]
        #expect(afterNote.contains("scrollNoteDown("))
        #expect(afterNote.contains("shot(\"notes-learn-xl-2\")"))
        #expect(body.contains("-uiTestNoteStaysAtTop"))
        #expect(body.contains("Asking for food and drink"))
        #expect(body.contains("Skip to practice"))
        #expect(body.contains("tsa ghwaa-REY?"))
        #expect(!body.contains("forDuration: 0.2, thenDragTo"))

        let study = try source("PashtoApp/Quiz/StudyCardScreen.swift")
        #expect(study.contains("!UITestLaunch.noteStaysAtTop"))
        #expect(!study.contains("noteSitsBelowCard"))
        #expect(!study.contains("fitsWithNote"))
        let scrolling = try section("private var scrollingTitle", until: "private var standardTitle", in: study)
        #expect(scrolling.contains("fixedSize(horizontal: false, vertical: true)"))
        #expect(!scrolling.contains("lineLimit"))
        #expect(!scrolling.contains("minimumScaleFactor"))
        let access = try section(
            "VStack(alignment: .leading, spacing: 14)",
            until: "Blue strip at the usual text sizes",
            in: study
        )
        #expect(access.contains("scrollingTitle"))
        #expect(access.contains("PronunciationNoteText(note: note)"))
        let title = try #require(access.range(of: "scrollingTitle"))
        let outsideNote = try #require(access.range(of: "PronunciationNoteText(note: note)"))
        #expect(title.lowerBound < outsideNote.lowerBound)
        let regular = try section("private var regularLines", until: "private var largeTypeLines", in: study)
        #expect(regular.contains("PronunciationNoteText(note: note)"))
        let meaning = try #require(regular.range(of: "meaningLine"))
        let pashto = try #require(regular.range(of: "pashtoLine"))
        let tips = try #require(regular.range(of: "PronunciationNoteText(note: note)"))
        #expect(meaning.lowerBound < pashto.lowerBound)
        #expect(pashto.lowerBound < tips.lowerBound)
        let lightNotes = try section("func testLightNotes()", until: "func testLightShell()", in: tests)
        #expect(!lightNotes.contains("-uiTestNoteStaysAtTop"))
        let plain = try section("func testXLPlainNote()", until: "func testLightNotes()", in: tests)
        #expect(!plain.contains("-uiTestNoteStaysAtTop"))

        let app = try source("PashtoApp/PashtoApp.swift")
        #expect(app.contains("-uiTestNoteStaysAtTop"))

        let exporter = try source("scripts/export-screenshots.py")
        #expect(exporter.contains("notes-learn-xl-top.png"))
        #expect(exporter.contains("notes-learn-xl.png"))
        #expect(exporter.contains("notes-learn-xl-2.png"))
        #expect(exporter.contains("notes-learn-light.png"))
    }

    @Test func pashtoLineKeepsInitializerArgumentOrder() throws {
        let labels = [
            "text:", "pronunciation:", "arabic:", "mark:", "reservesPronunciation:",
            "textColor:", "pronunciationColor:", "scriptColor:", "scriptFont:",
            "fitsWidth:", "centers:", "pronunciationSize:", "pronunciationLeads:",
        ]
        let files = [
            "PashtoApp/Quiz/QuizScreen.swift",
            "PashtoApp/Quiz/MatchingBoard.swift",
            "PashtoApp/Quiz/GlyphCard.swift",
            "PashtoApp/ContentView.swift",
        ]
        for relative in files {
            let text = try source(relative)
            let calls = pashtoLineCalls(in: text)
            #expect(!calls.isEmpty)
            for call in calls {
                var position = call.startIndex
                for label in labels {
                    guard let found = call.range(of: label) else { continue }
                    #expect(found.lowerBound >= position)
                    position = found.upperBound
                }
            }
        }
    }

    private func pashtoLineCalls(in source: String) -> [String] {
        var calls: [String] = []
        var rest = source[...]
        while let start = rest.range(of: "PashtoLine(") {
            var depth = 0
            var index = start.lowerBound
            var closed = false
            while index < rest.endIndex {
                let character = rest[index]
                if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                    if depth == 0 {
                        let end = rest.index(after: index)
                        calls.append(String(rest[start.lowerBound..<end]))
                        rest = rest[end...]
                        closed = true
                        break
                    }
                }
                index = rest.index(after: index)
            }
            if !closed { break }
        }
        return calls
    }

    private let rewrittenNotes: [String: String] = [
        "e-mung-yu": "ږ: in Kabul close to g in go; موږ is said mung. یو here means ‘are’, not ‘one’.",
        "e-daa-khaar-day": "ښ: in Kabul close to kh, like ch in Scottish loch.",
        "e-wakht": "خ: kh, like ch in Scottish loch.",
        "e-zha-ba": "ژ: zh, like s in measure.",
        "e-kha-ba-rey": "خ: kh, like ch in Scottish loch.",
        "e-za-pa-pakh-to-kha-ba-rey-ka-wam": "خ: kh, like ch in Scottish loch. ښ: in Kabul close to kh, like ch in Scottish loch.",
        "e-za-pa-ang-lee-see-kha-ba-rey-ka-wam": "خ: kh, like ch in Scottish loch.",
        "e-za-na-po-he-gam": "ږ: in Kabul close to g in go.",
        "e-wro-wro-kha-ba-rey-wa-kray": "خ: kh, like ch in Scottish loch. ړ: tongue tip curled back and flicked forward, like a quick r.",
        "e-za-chaay-na-ghwaa-ram": "غ: gh, a voiced kh, close to French r. ړ: tongue tip curled back and flicked forward, like a quick r.",
        "e-za-kah-wa-ghwaa-ram": "غ: gh, a voiced kh, close to French r. ړ: tongue tip curled back and flicked forward, like a quick r.",
        "e-za-sa-baa-baa-zaar-ta-dzam": "ځ: dz as in kids.",
        "e-letter-ddal": "ډ: d with the tongue tip curled back.",
        "e-letter-rre": "ړ: tongue tip curled back and flicked forward, like a quick r.",
        "e-do-day": "ډ: d with the tongue tip curled back.",
        "e-gho-kha": "غ: gh, a voiced kh, close to French r. ښ: in Kabul close to kh, like ch in Scottish loch.",
        "e-ma-na": "ڼ: n with the tongue tip curled back.",
        "e-ghwaa-ram": "غ: gh, a voiced kh, close to French r. ړ: tongue tip curled back and flicked forward, like a quick r.",
        "e-tsa-ghwaa-rey": "څ: ts as in cats. غ: gh, a voiced kh, close to French r. ړ: tongue tip curled back and flicked forward, like a quick r.",
        "e-za-o-ba-ghwaa-ram": "غ: gh, a voiced kh, close to French r. ړ: tongue tip curled back and flicked forward, like a quick r.",
        "e-za-chaay-ghwaa-ram": "غ: gh, a voiced kh, close to French r. ړ: tongue tip curled back and flicked forward, like a quick r.",
        "e-daa-ma-na-da": "ڼ: n with the tongue tip curled back.",
        "e-daa-do-day-da": "ډ: d with the tongue tip curled back.",
        "e-assalamu-alaykum": "ع is not pronounced as a separate sound in Pashto.",
        "e-stare-ma-she": "ړ: tongue tip curled back and flicked forward, like a quick r.",
        "e-dera-manana": "ډ: d with the tongue tip curled back.",
        "e-dera-xa": "ډ: d with the tongue tip curled back. ښ: in Kabul close to kh, like ch in Scottish loch.",
        "e-baxana-ghwaram": "ښ: in Kabul close to kh, like ch in Scottish loch. غ: gh, a voiced kh, close to French r. ړ: tongue tip curled back and flicked forward, like a quick r.",
        "e-mehrabani-wakray": "ړ: tongue tip curled back and flicked forward, like a quick r.",
        "e-letter-tte": "ټ: t with the tongue tip curled back.",
        "e-tsa-lor": "څ: ts as in cats.",
        "e-pin-dza": "ځ: dz as in kids.",
        "e-shpag": "ږ: in Kabul close to g in go.",
        "e-o-mar": "ع is not pronounced as a separate sound in Pashto.",
        "e-tswaar-las": "څ: ts as in cats.",
        "e-pin-dza-las": "ځ: dz as in kids.",
        "e-shpaa-ras": "ړ: tongue tip curled back and flicked forward, like a quick r.",
        "e-o-mar-dey-tso-day": "څ: ts as in cats. ع is not pronounced as a separate sound in Pashto.",
        "e-maa-khaam": "ښ: in Kabul close to kh, like ch in Scottish loch.",
        "e-ju-ma": "ع is not pronounced as a separate sound in Pashto.",
        "e-nan-ju-ma-da": "ع is not pronounced as a separate sound in Pashto.",
        "e-tso-ba-je-dee": "څ: ts as in cats.",
        "e-sa-haar-mo-pa-khayr": "خ: kh, like ch in Scottish loch.",
        "e-shpa-mo-pa-khayr": "خ: kh, like ch in Scottish loch.",
        "e-khaar": "ښ: in Kabul close to kh, like ch in Scottish loch.",
        "e-rogh-toon": "غ: gh, a voiced kh, close to French r.",
        "e-tak-see": "ټ: t with the tongue tip curled back.",
        "e-sa-rak": "ړ: tongue tip curled back and flicked forward, like a quick r.",
        "e-khee": "ښ: in Kabul close to kh, like ch in Scottish loch.",
        "e-rogh-toon-cher-ta-day": "غ: gh, a voiced kh, close to French r.",
        "e-rogh-toon-hal-ta-day": "غ: gh, a voiced kh, close to French r.",
        "e-za-baa-zaar-ta-dzam": "ځ: dz as in kids.",
        "e-za-kor-ta-dzam": "ځ: dz as in kids.",
        "e-ha-waa-yee-da-gar": "ډ: d with the tongue tip curled back.",
        "e-ho-tal": "ټ: t with the tongue tip curled back.",
        "e-ti-kat": "ټ: t with the tongue tip curled back.",
        "e-ho-tal-cher-ta-day": "ټ: t with the tongue tip curled back.",
        "e-za-ha-waa-yee-da-gar-ta-dzam": "ځ: dz as in kids. ډ: d with the tongue tip curled back.",
        "e-dal-ta-wu-dre-ga": "ږ: in Kabul close to g in go.",
        "e-za-ti-kat-ghwaa-ram": "غ: gh, a voiced kh, close to French r. ړ: tongue tip curled back and flicked forward, like a quick r. ټ: t with the tongue tip curled back.",
        "e-der-graan-day": "ډ: d with the tongue tip curled back.",
        "e-mras-ta-wu-kray": "ړ: tongue tip curled back and flicked forward, like a quick r.",
    ]

    private let clearedNotes: [String] = [
        "e-nan", "e-sa-baa", "e-kaar", "e-za-kaar-ka-wam",
        "e-za-nan-kaar-ka-wam", "e-za-sa-baa-kaar-ka-wam", "e-ang-lee-see", "e-byaa-wa-waa-yaast",
        "e-wro-wro", "e-o-ba", "e-wri-jey", "e-chaay",
        "e-kah-wa", "e-shee-dey", "e-shta", "e-na-shta",
        "e-chaay-shta", "e-ho-chaay-shta", "e-na-chaay-na-shta", "e-yaw",
        "e-dwa", "e-drey", "e-o-wa", "e-a-ta",
        "e-na-ha", "e-las", "e-yaw-wo-las", "e-dwo-las",
        "e-dyaar-las", "e-o-wa-las", "e-a-ta-las", "e-no-las",
        "e-shal", "e-ka-lan", "e-ka-la-na", "e-za-shal-ka-lan-yam",
        "e-za-shal-ka-la-na-yam", "e-sa-haar", "e-pa-roon", "e-shan-ba",
        "e-yak-shan-ba", "e-do-shan-ba", "e-se-shan-ba", "e-cha-haar-shan-ba",
        "e-panj-shan-ba", "e-sa-baa-shan-ba-da", "e-za-sa-haar-kaar-ka-wam", "e-baa-zaar",
        "e-doo-kaan", "e-cher-ta", "e-bas", "e-chap",
        "e-dal-ta", "e-hal-ta", "e-baa-zaar-cher-ta-day", "e-baa-zaar-dal-ta-day",
        "e-tash-naab", "e-pay-se", "e-ar-zaan", "e-mras-ta",
        "e-tash-naab-cher-ta-day",
    ]

    private var hyphen: String { String(PronunciationDisplay.nonBreakingHyphen) }

    private func expect(_ stored: String, text: [String], stressed: [Bool]) {
        let runs = PronunciationDisplay.runs(in: stored)
        #expect(runs.map(\.text) == text)
        #expect(runs.map(\.stressed) == stressed)
        #expect(runs.map { $0.weight(boldText: false) } == stressed.map { $0 ? 700 : 400 })
        #expect(runs.map { $0.weight(boldText: true) } == stressed.map { $0 ? 800 : 600 })
        #expect(runs.map { $0.underlined(boldText: false) } == stressed.map { _ in false })
        #expect(runs.map { $0.underlined(boldText: true) } == stressed)
        #expect(PronunciationDisplay.spoken(stored) == stored)
        #expect(PronunciationDisplay.displayText(stored: stored) == text.joined())
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relative), encoding: .utf8)
    }

    private func section(_ start: String, until end: String?, in source: String) throws -> String {
        let lower = try #require(source.range(of: start))
        let upper: String.Index
        if let end, let found = source.range(of: end, range: lower.upperBound..<source.endIndex) {
            upper = found.lowerBound
        } else {
            upper = source.endIndex
        }
        return String(source[lower.lowerBound..<upper])
    }

    private func swiftFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

    private func loadCourse() throws -> BundledCourse {
        let root = repositoryRoot()
        let content = try Data(contentsOf: root.appendingPathComponent("content/content.json"))
        let release = try Data(contentsOf: root.appendingPathComponent("content/release-units.json"))
        guard case .ready(let course) = BundledCourseLoader.load(content: content, releaseUnits: release) else {
            throw PronunciationDisplayTestError.missing
        }
        return course
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func itemID(_ raw: String) -> ItemID {
        ItemID(rawValue: raw)!
    }

    private func lessonID(_ raw: String) -> LessonID {
        LessonID(rawValue: raw)!
    }

    private func unitID(_ raw: String) -> UnitID {
        UnitID(rawValue: raw)!
    }
}

private enum PronunciationDisplayTestError: Error {
    case missing
}
