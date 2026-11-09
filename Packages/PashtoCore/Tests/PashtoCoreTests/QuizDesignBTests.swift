import Foundation
import Testing
@testable import PashtoCore

struct QuizDesignBTests {
    @Test func titlesStayOnTheThreeApprovedLines() {
        #expect(QuizPromptTitle.title(for: .meaningPashtoToEnglish) == "Choose the meaning")
        #expect(QuizPromptTitle.title(for: .meaningEnglishToPashto) == "Choose the meaning")
        #expect(QuizPromptTitle.title(for: .orderWords) == "Put the words in order")
        #expect(QuizPromptTitle.title(for: .matchPairs) == "Match the pairs")
        #expect(QuizPromptTitle.title(for: .dialogResponse) == nil)
        #expect(QuizPromptTitle.title(for: .findLetter) == nil)
        #expect(QuizPromptTitle.title(for: .letterContrast) == nil)
        #expect(QuizPromptTitle.title(for: .firstLetter) == nil)
        #expect(QuizPromptTitle.title(for: .transliterationChoice) == nil)
    }

    @Test func approvedTitlesAreNotAddedToTheCatalog() throws {
        let url = repoRoot().appendingPathComponent("PashtoApp/Localizable.xcstrings")
        let text = try String(contentsOf: url, encoding: .utf8)
        let before = try JSONDecoder().decode(CatalogShape.self, from: Data(text.utf8))
        #expect(!text.contains(QuizPromptTitle.chooseTheMeaning))
        #expect(!text.contains(QuizPromptTitle.putTheWordsInOrder))
        #expect(!text.contains(QuizPromptTitle.matchThePairs))
        #expect(before.strings["quiz.feedback.correct"] != nil)
        #expect(before.strings["quiz.continue.button"] != nil)
        #expect(before.strings[QuizPromptTitle.chooseTheMeaning] == nil)
        #expect(before.strings[QuizPromptTitle.putTheWordsInOrder] == nil)
        #expect(before.strings[QuizPromptTitle.matchThePairs] == nil)
    }

    @Test func everyPashtoOptionExposesTheStoredPronunciation() throws {
        let hello = makeItem("e-salam", pashto: "سلام", translit: "salam-scholar", pronunciation: "sa-LAAM", en: "hello")
        let thanks = makeItem("e-manana", pashto: "مننه", translit: "manana-scholar", pronunciation: "ma-NA-na", en: "thank you")
        let yes = makeItem("e-ho", pashto: "هو", translit: "ho-scholar", pronunciation: "ho", en: "yes")
        let items = [hello, thanks, yes]

        let meaning = QuizTask(
            kind: .meaningEnglishToPashto,
            targetID: hello.id,
            prompt: "hello",
            usage: nil,
            options: items.map { QuizOption(itemID: $0.id, text: $0.pashto) }
        )
        let dialog = QuizTask(
            kind: .dialogResponse,
            targetID: thanks.id,
            prompt: hello.pashto,
            usage: nil,
            options: [thanks, yes].map { QuizOption(itemID: $0.id, text: $0.pashto) },
            promptItemID: hello.id
        )
        for task in [meaning, dialog] {
            for answered in [false, true] {
                let face = QuizPresentation.face(
                    for: task,
                    items: items,
                    showsPronunciation: false,
                    voiceOver: false,
                    answered: answered
                )
                try expectPashtoOptions(face.options, items: items)
            }
        }

        let english = QuizTask(
            kind: .meaningPashtoToEnglish,
            targetID: hello.id,
            prompt: hello.pashto,
            usage: nil,
            options: try items.map { QuizOption(itemID: $0.id, text: try #require($0.en)) }
        )
        let englishFace = QuizPresentation.face(
            for: english,
            items: items,
            showsPronunciation: true,
            voiceOver: true,
            answered: false
        )
        #expect(englishFace.prompt.pronunciation == "sa-LAAM")
        #expect(englishFace.prompt.pronunciation != hello.translit)
        #expect(englishFace.options.allSatisfy { $0.pronunciation == nil })

        let tiles = [
            WordTile(index: 0, text: "تاسو", pronunciation: "TAA-so"),
            WordTile(index: 1, text: "څنګه", pronunciation: "TSAN-ga"),
            WordTile(index: 2, text: "یاست", pronunciation: "yaast"),
        ]
        for tile in tiles {
            #expect(QuizPresentation.containsArabicScript(tile.text))
            #expect(QuizPresentation.tilePronunciation(tile.pronunciation, showsPronunciation: false) == tile.pronunciation)
            #expect(QuizPresentation.tilePronunciation(tile.pronunciation, showsPronunciation: true) == tile.pronunciation)
        }
        #expect(QuizPresentation.tilePronunciation(nil, showsPronunciation: true) == nil)
        #expect(QuizPresentation.tilePronunciation("  ", showsPronunciation: true) == nil)

        #expect(
            QuizPresentation.matchAccessibilityLabel(
                text: hello.pashto,
                pronunciation: hello.pronunciation,
                linkedText: "thank you"
            ) == "sa-LAAM, سلام, thank you"
        )
        #expect(
            QuizPresentation.spokenPronunciation(text: thanks.pashto, item: thanks, showsPronunciation: false) == "ma-NA-na"
        )
    }

    @Test func letterOptionsStillHidePronunciationUntilTheAnswer() {
        let letter = makeItem(
            "e-dal",
            kind: .letter,
            pashto: "د",
            translit: "dal-scholar",
            pronunciation: "da",
            en: "the letter d"
        )
        #expect(
            QuizPresentation.optionPronunciation(
                kind: .findLetter,
                text: letter.pashto,
                item: letter,
                showsPronunciation: true,
                answered: false
            ) == nil
        )
        #expect(
            QuizPresentation.optionPronunciation(
                kind: .firstLetter,
                text: letter.pashto,
                item: letter,
                showsPronunciation: true,
                answered: false
            ) == nil
        )
        #expect(
            QuizPresentation.optionPronunciation(
                kind: .findLetter,
                text: letter.pashto,
                item: letter,
                showsPronunciation: true,
                answered: true
            ) == "da"
        )
        #expect(
            QuizPresentation.optionPronunciation(
                kind: .dialogResponse,
                text: "سلام",
                item: makeItem(pronunciation: "sa-LAAM"),
                showsPronunciation: false,
                answered: false
            ) == "sa-LAAM"
        )
    }

    @Test func designBTextClearsContrastAndSaffronIsNotText() {
        for pair in QuizDesignPalette.textPairs {
            #expect(pair.foreground != QuizDesignPalette.saffronAccent)
            #expect(pair.foreground != QuizDesignPalette.barFill)
            #expect(pair.foreground != QuizResultPalette.correctMarkLight)
            #expect(pair.minimumRatio == 4.5)
            let ratio = QuizResultPalette.contrastRatio(foreground: pair.foreground, background: pair.background)
            #expect(ratio >= pair.minimumRatio)
        }
        for pair in QuizDesignPalette.markPairs {
            #expect(pair.minimumRatio == 3)
            let ratio = QuizResultPalette.contrastRatio(foreground: pair.foreground, background: pair.background)
            #expect(ratio >= pair.minimumRatio)
        }
        let saffronOnCream = QuizResultPalette.contrastRatio(
            foreground: QuizDesignPalette.saffronAccent,
            background: QuizDesignPalette.cream
        )
        #expect(saffronOnCream < 4.5)
        #expect(QuizResultPalette.correctTextLight != QuizResultPalette.correctMarkLight)
        #expect(QuizResultPalette.correctMarkLight == 0x16A34A)
        #expect(QuizResultPalette.correctFillDark == 0x0B2A1A)
        #expect(QuizMotion.resultSheet == 0.25)
        #expect(QuizMotion.reduceMotionFade == 0.2)
    }

    @Test func theQuizScreenUsesTheDesignBChrome() throws {
        let root = repoRoot()
        let quiz = try String(contentsOf: root.appendingPathComponent("PashtoApp/Quiz/QuizScreen.swift"), encoding: .utf8)
        let board = try String(contentsOf: root.appendingPathComponent("PashtoApp/Quiz/MatchingBoard.swift"), encoding: .utf8)
        let home = try String(contentsOf: root.appendingPathComponent("PashtoApp/ContentView.swift"), encoding: .utf8)
        #expect(quiz.contains("QuizPromptTitle.title"))
        #expect(quiz.contains("QuizMotion.resultSheet"))
        #expect(quiz.contains("QuizChrome.cream"))
        #expect(!quiz.contains("SaffronButtonStyle"))
        #expect(quiz.contains("if session.isComplete {\n            onFinish(session)"))
        #expect(quiz.contains("onAnswer(session)"))
        #expect(board.contains("QuizChrome.primary"))
        #expect(board.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(home.contains("onFinish: { celebration = $0; finishSession($0) }"))
        #expect(home.contains("streakCount: streakCount"))
        let study = try String(contentsOf: root.appendingPathComponent("PashtoApp/Quiz/StudyCardScreen.swift"), encoding: .utf8)
        #expect(study.contains("StudyPrimaryButtonStyle()"))
        #expect(!study.contains("QuizContinueButtonStyle"))
    }

    private func expectPashtoOptions(_ options: [QuizOptionFace], items: [ContentItem]) throws {
        #expect(!options.isEmpty)
        for option in options {
            #expect(QuizPresentation.containsArabicScript(option.text))
            let item = try #require(items.first { $0.id == option.itemID })
            #expect(option.pronunciation == item.pronunciation)
            #expect(option.pronunciation != item.translit)
            #expect(option.pronunciation?.isEmpty == false)
        }
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct CatalogShape: Decodable {
    var strings: [String: CatalogEntry]
}

private struct CatalogEntry: Decodable {}
