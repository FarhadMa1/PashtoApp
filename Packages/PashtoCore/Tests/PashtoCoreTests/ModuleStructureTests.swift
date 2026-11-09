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

    @Test func releasedUnitsPutCardsBeforeTheSamePracticeLessons() throws {
        let bundle = try loadCourse().bundle
        let expected: [(unit: String, practice: [String])] = [
            ("u-greetings", ["l-greetings-1", "l-greetings-2", "l-greetings-3"]),
            ("u-introductions", ["l-introductions-1", "l-introductions-2", "l-introductions-3"]),
            ("u-family", ["l-family-1", "l-family-2", "l-family-3"]),
        ]
        for row in expected {
            let unit = try #require(bundle.units.first { $0.id.rawValue == row.unit })
            let ids = unit.lessons.map(\.id.rawValue)
            #expect(ids == ["l-\(row.unit.dropFirst(2))-learn", "l-\(row.unit.dropFirst(2))-phrases"] + row.practice)
            let learn = unit.lessons[0]
            let phrases = unit.lessons[1]
            #expect(learn.kind == .learn)
            #expect(phrases.kind == .phrases)
            #expect(learn.title == unit.title)
            #expect(phrases.title == unit.title)
            #expect(learn.letters.isEmpty)
            #expect(phrases.letters.isEmpty)
            #expect(learn.dialogs.isEmpty)
            #expect(phrases.dialogs.isEmpty)
            #expect(learn.items.allSatisfy { $0.role == .present })
            #expect(phrases.items.allSatisfy { $0.role == .present })
            #expect(unit.lessons.dropFirst(2).allSatisfy { $0.kind == .practice && $0.countsForProgress })
            let items = Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id, $0) })
            #expect(learn.items.allSatisfy { items[$0.item]?.kind == .word })
            #expect(phrases.items.allSatisfy { items[$0.item]?.kind == .phrase })
            #expect(PendingCopy.phraseCategoryHeading(for: unit.id) == nil)
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
                           "l-family-1", "l-family-2", "l-family-3"].map(lessonID)
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
        #expect(Set(skipped.lessonProgress.map(\.lessonID)) == Set(practiceIDs))
        #expect(!skipped.lessonProgress.contains { $0.lessonID.rawValue.contains("learn") || $0.lessonID.rawValue.contains("phrases") })

        let released = ReleasedCourse.limiting(bundle, to: course.releasedUnitIDs)
        let progress = PathProgress(cards: [], finishedLessonIDs: [], newItemsShownToday: 0)
        #expect(pathState(progress: progress, content: released, goal: .regular, today: day) == .lesson(lessonID("l-greetings-1")))

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

        var phrases = try #require(StudyCourse.deck(for: lessonID("l-greetings-phrases"), in: bundle))
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
        #expect(StudyCourse.nextLesson(after: lessonID("l-greetings-learn"), in: bundle) == lessonID("l-greetings-phrases"))
        #expect(StudyCourse.nextLesson(after: lessonID("l-greetings-phrases"), in: bundle) == lessonID("l-greetings-1"))
        #expect(last.startPractice(opening: practice) == .open(lessonID("l-greetings-1")))
        #expect(last.startPractice(opening: practice) == .ignored)
        last.settle()
        #expect(last.skipToPractice(practice) == .open(lessonID("l-greetings-1")))
        #expect(last.skipToPractice(practice) == .ignored)

        var fresh = try #require(StudyCourse.deck(for: lessonID("l-family-phrases"), in: bundle))
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
        #expect(PendingCopy.phraseCategories.map(\.key).sorted() == [
            PendingCopy.phraseCategoryFamily,
            PendingCopy.phraseCategoryGreetings,
            PendingCopy.phraseCategoryIntroductions,
        ])
        #expect(PendingCopy.phraseCategories.values.allSatisfy { $0 == nil })
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
