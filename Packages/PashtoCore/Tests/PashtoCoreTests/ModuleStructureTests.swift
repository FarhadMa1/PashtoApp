import Foundation
import Testing
@testable import PashtoCore

struct ModuleStructureTests {
    private let day = LocalDay(year: 2026, month: 11, day: 8)

    @Test func missingKindDecodesAsPracticeAndIsNotWrittenBack() throws {
        let json = """
        {"id":"l-greetings-1","title":"Saying hello","items":[{"item":"e-salam","role":"introduce"}]}
        """
        let lesson = try JSONDecoder().decode(Lesson.self, from: Data(json.utf8))
        #expect(lesson.kind == .practice)
        #expect(lesson.countsForProgress)
        let encoded = try JSONEncoder().encode(lesson)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["kind"] == nil)
    }

    @Test func releasedUnitsGroupCardsAndKeepThePracticeLessons() throws {
        let bundle = try loadCourse().bundle
        let items = Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id, $0) })
        let groups: [(unit: String, cards: [(id: String, title: String, kind: LessonKind, pronunciations: [String])], practice: [String])] = [
            ("u-greetings", [
                ("l-greetings-learn", "Key words", .learn, ["kha", "ma-NA-na", "ho", "na"]),
                ("l-greetings-phrases-hello", "Saying hello", .phrases, ["sa-LAAM", "as-sa-LAAM a-lay-KOOM", "wa-a-lay-KOOM as-sa-LAAM", "STA-ray ma shey", "khwaar ma shey", "kha raagh-LAAST"]),
                ("l-greetings-phrases-how", "How are you?", .phrases, ["TSAN-ga ye?", "TAA-so TSAN-ga yaast?", "za kha yam", "DE-ra ma-NA-na"]),
                ("l-greetings-phrases-goodbye", "Polite words and goodbye", .phrases, ["DE-ra kha", "ba-KHA-na ghwaa-RAM", "meh-ra-baa-NEE WA-kray", "kho-DAAY paa-MAAN", "pa MA-kha dey kha"]),
            ], ["l-greetings-1", "l-greetings-2", "l-greetings-3"]),
            ("u-introductions", [
                ("l-introductions-learn-names", "I, you and names", .learn, ["za", "ta", "TAA-so", "ha-GHA", "noom"]),
                ("l-introductions-learn-be", "To be", .learn, ["yam", "ye", "day", "da", "yaast"]),
                ("l-introductions-phrases-name", "What's your name?", .phrases, ["zmaa noom AH-mad day", "staa noom tsa day?", "STAA-so noom tsa day?"]),
                ("l-introductions-phrases-from", "Where are you from?", .phrases, ["ta da koom dzaay ye?", "za la naar-WEY TSA-kha yam", "za af-GHAAN yam", "za af-GHAA-na yam", "za kho-WOON-kay yam", "za pakh-TO zda ka-WAM", "STAA-so pa lee-DO kho-SHAA-la shwam"]),
            ], ["l-introductions-1", "l-introductions-2", "l-introductions-3"]),
            ("u-family", [
                ("l-family-learn-members", "Family members", .learn, ["mor", "plaar", "wror", "khor", "zoy", "loor", "ko-ra-NAY"]),
                ("l-family-learn-this", "This, my and your", .learn, ["daa", "zmaa", "staa"]),
                ("l-family-phrases-this", "This is my \u{2026}", .phrases, ["daa tsok day?", "daa tsok da?", "daa zmaa plaar day", "daa zmaa mor da", "daa zmaa wror day", "daa zmaa khor da"]),
                ("l-family-phrases-yours", "Is this your \u{2026}?", .phrases, ["daa staa wror day?", "ho, zmaa wror day", "na, zmaa zoy day"]),
                ("l-family-phrases-how", "How is your family?", .phrases, ["mor dey TSAN-ga da?", "ha-GHA kha da", "plaar dey TSAN-ga day?", "ha-GHA kha day"]),
            ], ["l-family-1", "l-family-2", "l-family-3"]),
        ]
        let practiceContent: [String: (title: String, items: [String], letters: [String], dialogs: [String])] = [
            "l-greetings-1": ("Practice: Saying hello", ["e-salam", "e-assalamu-alaykum", "e-walaykum-salam", "e-stare-ma-she", "e-xwar-ma-she", "e-xa-raghlast"], ["e-letter-alif", "e-letter-be"], ["d-greetings-1", "d-greetings-2"]),
            "l-greetings-2": ("Practice: How are you?", ["e-tsanga-ye", "e-taso-tsanga-yast", "e-za-xa-yam", "e-xa", "e-manana", "e-dera-manana"], ["e-letter-pe", "e-letter-te"], ["d-greetings-3"]),
            "l-greetings-3": ("Practice: Polite words and goodbye", ["e-dera-xa", "e-ho", "e-na", "e-baxana-ghwaram", "e-mehrabani-wakray", "e-xoday-paman", "e-pa-maxa-de-xa"], ["e-letter-tte", "e-letter-se"], []),
            "l-introductions-1": ("Practice: I, you and names", ["e-za", "e-ta", "e-taso", "e-hagha", "e-num", "e-zma-num-ahmad-day", "e-sta-num-tsa-day", "e-staso-num-tsa-day"], ["e-letter-jim", "e-letter-che"], ["d-introductions-1"]),
            "l-introductions-2": ("Practice: Where are you from?", ["e-ta-da-kum-dzay-ye", "e-za-la-narwe-tsaxa-yam", "e-za-afghan-yam", "e-za-afghana-yam", "e-za-xowunkay-yam", "e-za-pashto-zda-kawam", "e-staso-pa-lido-xoshala-shwam"], ["e-letter-he", "e-letter-xe"], ["d-introductions-2"]),
            "l-introductions-3": ("Practice: To be", ["e-yam", "e-ye", "e-day", "e-da", "e-yast"], ["e-letter-tse", "e-letter-dze"], []),
            "l-family-1": ("Practice: Family members", ["e-mor", "e-plar", "e-wror", "e-xor", "e-zoy", "e-lur", "e-daa-tsok-day", "e-daa-tsok-da", "e-daa-zma-plar-day", "e-daa-zma-mor-da"], ["e-letter-dal", "e-letter-ddal", "e-letter-zal"], ["d-family-1", "d-family-2"]),
            "l-family-2": ("Practice: This is my \u{2026}", ["e-koraney", "e-daa", "e-zma", "e-daa-zma-wror-day", "e-daa-zma-xor-da"], ["e-letter-re", "e-letter-rre", "e-letter-ze"], []),
            "l-family-3": ("Practice: Is this your \u{2026}?", ["e-sta", "e-daa-sta-wror-day", "e-ho-zma-wror-day", "e-na-zma-zoy-day", "e-mor-de-tsanga-da", "e-hagha-xa-da", "e-plar-de-tsanga-day", "e-hagha-xa-day"], ["e-letter-zhe", "e-letter-gye"], ["d-family-3", "d-family-4", "d-family-5"]),
        ]
        for row in groups {
            let unit = try #require(bundle.units.first { $0.id.rawValue == row.unit })
            let cardLessons = Array(unit.lessons.prefix(row.cards.count))
            let practiceLessons = Array(unit.lessons.suffix(row.practice.count))
            #expect(unit.lessons.map(\.id.rawValue) == row.cards.map(\.id) + row.practice)
            for (lesson, expected) in zip(cardLessons, row.cards) {
                #expect(lesson.kind == expected.kind)
                #expect(lesson.title == expected.title)
                #expect(lesson.letters.isEmpty)
                #expect(lesson.dialogs.isEmpty)
                #expect(lesson.items.allSatisfy { $0.role == .present })
                let resolved = expected.pronunciations.map { pronunciation in
                    let matches = items.values.filter { $0.pronunciation == pronunciation }
                    let words = matches.filter { $0.kind != .letter }
                    return (words.isEmpty ? matches : words).map(\.id.rawValue).sorted()
                }
                #expect(lesson.items.allSatisfy { items[$0.item] != nil })
                #expect(resolved.allSatisfy { $0.count == 1 })
                #expect(lesson.items.map(\.item.rawValue) == resolved.map { $0[0] })
            }
            #expect(practiceLessons.map(\.id.rawValue) == row.practice)
            for lesson in practiceLessons {
                let expected = try #require(practiceContent[lesson.id.rawValue])
                #expect(lesson.kind == .practice)
                #expect(lesson.countsForProgress)
                #expect(lesson.title == expected.title)
                #expect(lesson.items.map(\.item.rawValue) == expected.items)
                #expect(lesson.items.allSatisfy { $0.role == .introduce })
                #expect(lesson.letters.map(\.rawValue) == expected.letters)
                #expect(lesson.dialogs.map(\.id.rawValue) == expected.dialogs)
            }
        }
    }

    @Test func unitsFourThroughEightStayPracticeWithTheSameLessons() throws {
        let bundle = try loadCourse().bundle
        let expected = [
            "u-numbers": ["l-numbers-1", "l-numbers-2"],
            "u-food": ["l-food-1", "l-food-2", "l-food-3", "l-food-4"],
            "u-daily-life": ["l-daily-life-1", "l-daily-life-2", "l-daily-life-3", "l-daily-life-4"],
            "u-town": ["l-town-1", "l-town-2", "l-town-3", "l-town-4"],
            "u-conversation": ["l-conversation-1", "l-conversation-2", "l-conversation-3"],
        ]
        for (unitID, lessonIDs) in expected {
            let unit = try #require(bundle.units.first { $0.id.rawValue == unitID })
            #expect(unit.lessons.map(\.id.rawValue) == lessonIDs)
            #expect(unit.lessons.allSatisfy { $0.kind == .practice })
        }
    }

    @Test @MainActor func onlyPracticeCountsAndAnOpenQuizSurvivesLearnCards() throws {
        let course = try loadCourse()
        let bundle = course.bundle
        let practiceIDs = ["l-greetings-1", "l-greetings-2", "l-greetings-3",
                           "l-introductions-1", "l-introductions-2", "l-introductions-3",
                           "l-family-1", "l-family-2", "l-family-3",
                           "l-travel-1", "l-travel-2", "l-time-1", "l-time-2"].map(lessonID)
        var cards: [ReviewCard] = []
        var seen = Set<ItemID>()
        for id in practiceIDs {
            for card in reviewCards(introducedIn: try practiceLesson(id, in: bundle), on: day.adding(days: -3))
            where seen.insert(card.itemID).inserted {
                cards.append(card)
            }
        }
        let task = SessionTask(payload: .choice(QuizTask(
            kind: .meaningPashtoToEnglish,
            targetID: itemID("e-salam"),
            prompt: "سلام",
            usage: nil,
            options: [QuizOption(itemID: itemID("e-salam"), text: "hello")]
        )))
        let active = ActiveSessionSnapshot(
            sessionID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            kind: .lesson,
            lessonID: lessonID("l-greetings-1"),
            startedDay: day,
            lastAnswerDay: day,
            contentVersion: bundle.contentVersion,
            lesson: LessonSession(lessonID: lessonID("l-greetings-1"), tasks: [task])
        )
        let streak = StreakState.initial
        let stored = ProgressSnapshot(
            contentVersion: bundle.contentVersion,
            cards: cards,
            lessonProgress: practiceIDs.map {
                LessonProgress(lessonID: $0, source: .completed, firstCompletedDay: day.adding(days: -3), bestScorePercent: 80)
            },
            streak: streak,
            settings: .initial,
            activeSession: active,
            completedSessions: [],
            lastReconciledContentVersion: nil,
            latestObservedDay: day
        )
        let reconciled = ProgressReconciler.reconcile(stored, with: bundle, on: day)
        #expect(reconciled.cardChanges.isEmpty)
        #expect(Set(reconciled.snapshot.lessonProgress.map(\.lessonID)) == Set(practiceIDs))
        #expect(Set(reconciled.snapshot.cards.map(\.itemID)) == Set(cards.map(\.itemID)))
        #expect(reconciled.snapshot.streak == streak)
        #expect(reconciled.snapshot.activeSession == active)
        #expect(newItemsShown(on: day, in: reconciled.snapshot.cards) == 0)
        #expect(ProgressReconciler.sessionAction(for: active, in: stored, content: bundle, on: day) == .resume)

        let learn = try practiceLesson(lessonID("l-greetings-learn"), in: bundle)
        #expect(reviewCards(introducedIn: learn, on: day).isEmpty)
        #expect(sessionCommit(
            for: active,
            lesson: learn,
            cards: cards,
            lessonProgress: nil,
            streak: streak
        ) == nil)
        let learnSession = ActiveSessionSnapshot(
            sessionID: UUID(uuidString: "BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            kind: .lesson,
            lessonID: learn.id,
            startedDay: day,
            lastAnswerDay: day,
            contentVersion: bundle.contentVersion,
            lesson: LessonSession(lessonID: learn.id, tasks: [])
        )
        let withLearn = ProgressSnapshot(
            contentVersion: bundle.contentVersion,
            cards: cards,
            lessonProgress: stored.lessonProgress,
            streak: streak,
            settings: .initial,
            activeSession: learnSession,
            completedSessions: [],
            lastReconciledContentVersion: nil,
            latestObservedDay: day
        )
        #expect(sessionCommit(
            for: learnSession,
            lesson: learn,
            cards: cards,
            lessonProgress: nil,
            streak: streak
        ) == nil)
        #expect(ProgressReconciler.sessionAction(for: learnSession, in: withLearn, content: bundle, on: day) == .discard)

        let skipped = placementCommit(
            scores: course.releasedUnitIDs.map {
                PlacementUnitScore(unitID: $0, correct: 5, questions: 5, skipped: true)
            },
            in: bundle,
            takenOn: day
        )
        #expect(Set(skipped.lessonProgress.map(\.lessonID)) == Set(practiceIDs + [lessonID("l-basics-1")]))
        #expect(!skipped.lessonProgress.contains { $0.lessonID.rawValue.contains("learn") || $0.lessonID.rawValue.contains("phrases") })

        let released = ReleasedCourse.limiting(bundle, to: course.releasedUnitIDs)
        let progress = PathProgress(cards: [], finishedLessonIDs: [], newItemsShownToday: 0)
        #expect(pathState(progress: progress, content: released, goal: .regular, today: day) == .lesson(lessonID("l-basics-1")))

        let opener = OpenLesson()
        var rng = SplitMix64(seed: 3)
        opener.startLesson(
            lessonID: lessonID("l-greetings-1"),
            in: bundle,
            progress: .empty(contentVersion: bundle.contentVersion),
            releasedUnitIDs: course.releasedUnitIDs,
            showsPronunciation: true,
            voiceOver: false,
            on: day,
            using: &rng
        )
        let quiz = try #require(opener.session)
        #expect(!quiz.tasks.isEmpty)
        opener.startLesson(
            lessonID: lessonID("l-greetings-learn"),
            in: bundle,
            progress: stored,
            releasedUnitIDs: course.releasedUnitIDs,
            showsPronunciation: true,
            voiceOver: false,
            on: day,
            using: &rng
        )
        #expect(opener.session == quiz)
    }

    @Test func cardButtonsMoveOneStepAndASecondTapDoesNothing() throws {
        let bundle = try loadCourse().bundle
        let learn = try #require(StudyCourse.deck(for: lessonID("l-greetings-learn"), in: bundle))
        #expect(learn.kind == .learn)
        #expect(learn.meaningVisible)
        #expect(learn.cards.map(\.itemID.rawValue) == ["e-xa", "e-manana", "e-ho", "e-na"])
        var deck = learn
        #expect(deck.next() == .advanced)
        #expect(deck.index == 1)
        #expect(deck.next() == .ignored)
        #expect(deck.index == 1)
        deck.settle()
        #expect(deck.showMeaning() == .ignored)
        var learnLast = learn
        while !learnLast.isLast {
            learnLast.settle()
            #expect(learnLast.next() == .advanced)
        }
        learnLast.settle()
        let phrasesID = StudyCourse.nextLesson(after: learnLast.lessonID, in: bundle)
        #expect(phrasesID == lessonID("l-greetings-phrases-hello"))
        #expect(learnLast.offersStartPractice == false)
        #expect(learnLast.startPractice(opening: lessonID("l-greetings-1")) == .ignored)
        #expect(learnLast.index == learnLast.count - 1)
        #expect(learnLast.openNextLesson(phrasesID) == .open(lessonID("l-greetings-phrases-hello")))
        #expect(learnLast.openNextLesson(phrasesID) == .ignored)

        var phrases = try #require(StudyCourse.deck(for: lessonID("l-greetings-phrases-hello"), in: bundle))
        #expect(phrases.meaningVisible == false)
        #expect(phrases.showMeaning() == .revealedMeaning)
        #expect(phrases.meaningVisible)
        #expect(phrases.showMeaning() == .ignored)
        phrases.settle()
        #expect(phrases.showMeaning() == .ignored)
        #expect(phrases.index == 0)
        let first = phrases.card?.itemID
        #expect(phrases.next() == .advanced)
        #expect(phrases.next() == .ignored)
        #expect(phrases.card?.itemID != first)
        #expect(phrases.meaningVisible == false)

        var last = phrases
        while !last.isLast {
            last.settle()
            #expect(last.next() == .advanced)
        }
        last.settle()
        let practice = StudyCourse.firstPracticeLesson(for: last.lessonID, in: bundle)
        #expect(practice == lessonID("l-greetings-1"))
        #expect(last.offersStartPractice == false)
        #expect(last.startPractice(opening: practice) == .ignored)
        let how = StudyCourse.nextLesson(after: last.lessonID, in: bundle)
        #expect(how == lessonID("l-greetings-phrases-how"))
        #expect(last.openNextLesson(how) == .open(lessonID("l-greetings-phrases-how")))
        #expect(last.openNextLesson(how) == .ignored)

        var goodbye = try #require(StudyCourse.deck(for: lessonID("l-greetings-phrases-goodbye"), in: bundle))
        while !goodbye.isLast {
            goodbye.settle()
            #expect(goodbye.next() == .advanced)
        }
        goodbye.settle()
        #expect(goodbye.offersStartPractice)
        #expect(goodbye.openNextLesson(lessonID("l-greetings-1")) == .ignored)
        #expect(goodbye.startPractice(opening: practice) == .open(lessonID("l-greetings-1")))
        #expect(goodbye.startPractice(opening: practice) == .ignored)
        goodbye.settle()
        #expect(goodbye.skipToPractice(practice) == .open(lessonID("l-greetings-1")))
        #expect(goodbye.skipToPractice(practice) == .ignored)

        var fresh = try #require(StudyCourse.deck(for: lessonID("l-family-phrases-this"), in: bundle))
        #expect(fresh.skipToPractice(StudyCourse.firstPracticeLesson(for: fresh.lessonID, in: bundle)) == .open(lessonID("l-family-1")))
        #expect(fresh.skipToPractice(lessonID("l-family-1")) == .ignored)
        #expect(fresh.index == 0)
    }

    @Test func approvedSectionNamesAndPendingCategories() throws {
        #expect(ModuleCopy.learn == "Learn")
        #expect(ModuleCopy.phrases == "Phrases")
        #expect(ModuleCopy.practice == "Practice")
        #expect(ModuleCopy.newWords == "New words")
        #expect(ModuleCopy.next == "Next")
        #expect(ModuleCopy.startPractice == "Start practice")
        #expect(ModuleCopy.skipToPractice == "Skip to practice")
        #expect(DailyWordCopy.showMeaning == "Show meaning")
        let catalog = try String(contentsOf: repositoryRoot().appendingPathComponent("PashtoApp/Localizable.xcstrings"), encoding: .utf8)
        for word in [ModuleCopy.learn, ModuleCopy.phrases, ModuleCopy.practice, ModuleCopy.newWords, ModuleCopy.next, ModuleCopy.startPractice, ModuleCopy.skipToPractice, DailyWordCopy.showMeaning] {
            #expect(catalog.contains("\"value\" : \"\(word)\""))
        }
        #expect(!catalog.contains("The basics"))
    }

    private func practiceLesson(_ id: LessonID, in bundle: ContentBundle) throws -> Lesson {
        for unit in bundle.units {
            if let lesson = unit.lessons.first(where: { $0.id == id }) {
                return lesson
            }
        }
        Issue.record("Missing \(id)")
        throw ModuleStructureTestError.missing
    }
}

private func loadCourse() throws -> BundledCourse {
    let root = repositoryRoot()
    let content = try Data(contentsOf: root.appendingPathComponent("content/content.json"))
    let release = try Data(contentsOf: root.appendingPathComponent("content/release-units.json"))
    guard case .ready(let course) = BundledCourseLoader.load(content: content, releaseUnits: release) else {
        Issue.record("The bundled course did not decode")
        throw ModuleStructureTestError.missing
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

private enum ModuleStructureTestError: Error {
    case missing
}
