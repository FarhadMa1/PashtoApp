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

    @Test func capitalNotesStayInTheDataAndOffTheScreen() throws {
        let bundle = try loadCourse().bundle
        let items = Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id, $0) })
        let travel = try noteIDs(in: "content/units/u-travel.json", mentioningCapitals: true)
        let time = try noteIDs(in: "content/units/u-time.json", mentioningCapitals: true)
        let travelKept = try noteIDs(in: "content/units/u-travel.json", mentioningCapitals: false)
        let timeKept = try noteIDs(in: "content/units/u-time.json", mentioningCapitals: false)
        #expect(travel.count == 13)
        #expect(time.count == 16)
        #expect(!travelKept.isEmpty)
        #expect(!timeKept.isEmpty)

        let travelText = try source("content/units/u-travel.json")
        let timeText = try source("content/units/u-time.json")
        #expect(travelText.contains("Stress the syllable shown in capitals in the simple pronunciation."))
        #expect(timeText.contains("Stress the syllable shown in capitals in the simple pronunciation."))
        #expect(!travelText.contains("shown in bold"))
        #expect(!timeText.contains("shown in bold"))

        for id in travel + time {
            let item = try #require(items[itemID(id)])
            let stored = try #require(item.pronunciationNote)
            #expect(PronunciationNotes.mentionsCapitals(stored))
            #expect(stored.contains("capitals"))
        }

        var sawKeptTravel = false
        var sawKeptTime = false
        for unit in bundle.units where ["u-travel", "u-time"].contains(unit.id.rawValue) {
            for lesson in unit.lessons where lesson.kind == .learn || lesson.kind == .phrases {
                let deck = try #require(StudyCourse.deck(for: lesson.id, in: bundle))
                for card in deck.cards {
                    let stored = items[card.itemID]?.pronunciationNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if PronunciationNotes.mentionsCapitals(stored) {
                        #expect(card.pronunciationNote == nil)
                        #expect(!card.pronunciation.contains(stored))
                        #expect(!card.meaning.contains(stored))
                        #expect(!card.pashto.contains(stored))
                    } else if !stored.isEmpty {
                        #expect(card.pronunciationNote == stored)
                        if unit.id.rawValue == "u-travel" { sawKeptTravel = true }
                        if unit.id.rawValue == "u-time" { sawKeptTime = true }
                    }
                }
            }
        }
        #expect(sawKeptTravel)
        #expect(sawKeptTime)

        let family = try #require(StudyCourse.deck(for: lessonID("l-family-learn-members"), in: bundle))
        let sister = try #require(family.cards.first { $0.itemID.rawValue == "e-xor" })
        let sisterNote = try #require(items[sister.itemID]?.pronunciationNote)
        #expect(!PronunciationNotes.mentionsCapitals(sisterNote))
        #expect(sister.pronunciationNote == sisterNote)

        let hiddenUnits = ["u-numbers", "u-food", "u-town", "u-conversation"]
        var sawPlainHiddenNote = false
        for unit in bundle.units where hiddenUnits.contains(unit.id.rawValue) {
            for lesson in unit.lessons where lesson.kind == .learn || lesson.kind == .phrases {
                let deck = try #require(StudyCourse.deck(for: lesson.id, in: bundle))
                for card in deck.cards {
                    #expect(card.pronunciationNote == nil)
                    let stored = items[card.itemID]?.pronunciationNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !stored.isEmpty, !PronunciationNotes.mentionsCapitals(stored) {
                        sawPlainHiddenNote = true
                    }
                }
            }
        }
        #expect(sawPlainHiddenNote)

        for rawUnitID in ["u-family", "u-travel", "u-time"] {
            for shows in [true, false] {
                let rows = FamilyWordList.rows(for: unitID(rawUnitID), in: bundle, showsPronunciation: shows)
                for row in rows {
                    let stored = items[row.itemID]?.pronunciationNote ?? ""
                    if PronunciationNotes.mentionsCapitals(stored) {
                        #expect(!row.accessibilityLabel.contains(stored))
                    }
                    if let pronunciation = row.pronunciation {
                        #expect(pronunciation == items[row.itemID]?.pronunciation)
                        #expect(PronunciationDisplay.spoken(pronunciation) == pronunciation)
                    }
                }
            }
        }

        let screen = try source("PashtoApp/Quiz/StudyCardScreen.swift")
        #expect(screen.contains("if let note = card.pronunciationNote"))
        #expect(!screen.contains("item.pronunciationNote"))
        let quiz = try source("PashtoApp/Quiz/QuizScreen.swift")
        let home = try source("PashtoApp/ContentView.swift")
        #expect(!quiz.contains("pronunciationNote"))
        #expect(!home.contains("pronunciationNote"))
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
            for: lessonID("l-greetings-learn"),
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

    private func noteIDs(in relative: String, mentioningCapitals: Bool) throws -> [String] {
        let data = try Data(contentsOf: repositoryRoot().appendingPathComponent(relative))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = try #require(object?["items"] as? [[String: Any]])
        return items.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let note = (item["pronunciationNote"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !note.isEmpty else { return nil }
            guard PronunciationNotes.mentionsCapitals(note) == mentioningCapitals else { return nil }
            return id
        }
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
