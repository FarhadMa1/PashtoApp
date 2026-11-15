import Foundation
import Testing
@testable import PashtoCore

struct TheBasicsTests {
    private let day = LocalDay(year: 2026, month: 11, day: 9)
    private let youAre = "Use ta ye with friends and family, and TAA-so yaast to be polite or to talk to more than one person."
    private let hagha = "Hagha means he, she and they. Only the verb shows which: day (he), da (she), dee (they)."
    private let itLine = "Pashto has no word for \"it\". Say daa (this) with day or da, depending on the word."
    private let notLine = "Put na right before the verb: za na yam."
    private let wordOrder = "In Pashto, the verb comes last."
    private let earlierPractice = [
        "l-greetings-1",
        "l-introductions-1", "l-introductions-2",
        "l-family-1", "l-family-2", "l-family-3",
    ]

    @Test func theBasicsIsFirstAmongReleasedUnitsAndUsesTheApprovedText() throws {
        let course = try loadCourse()
        let bundle = course.bundle
        #expect(bundle.units.map(\.id.rawValue).prefix(2) == ["u-sounds", "u-basics"])
        #expect(course.releasedUnitIDs.map(\.rawValue) == [
            "u-basics", "u-greetings", "u-introductions", "u-family", "u-travel", "u-time",
            "u-numbers", "u-food", "u-town", "u-conversation",
        ])

        let unit = try #require(bundle.units.first { $0.id.rawValue == "u-basics" })
        #expect(unit.title == "The basics")
        #expect(Array(unit.lessons.prefix(6).map(\.id.rawValue)) == [
            "l-basics-learn-1", "l-basics-learn-polite", "l-basics-phrases",
            "l-basics-1", "l-basics-verbs", "l-basics-polite",
        ])
        #expect(Array(unit.lessons.prefix(6).map(\.title)) == [
            "I am, you are, we are",
            "Yes, no and polite words",
            "About me and others",
            "Practice: The basics",
            "Practice: Am, are and is",
            "Practice: Yes, no and polite words",
        ])
        #expect(unit.lessons[0].kind == .learn)
        #expect(unit.lessons[1].kind == .learn)
        #expect(unit.lessons[2].kind == .phrases)
        #expect(unit.lessons[3].kind == .practice)
        #expect(unit.lessons[3].countsForProgress)
        #expect(!unit.lessons[0].countsForProgress)
        #expect(unit.lessons.filter { $0.kind != .practice }.allSatisfy { $0.letters.isEmpty && $0.dialogs.isEmpty })
        #expect(unit.lessons[3].letters.isEmpty && unit.lessons[3].dialogs.isEmpty)
        #expect(unit.lessons[4].letters.isEmpty && unit.lessons[4].dialogs.isEmpty)
        #expect(unit.lessons[5].letters.isEmpty && unit.lessons[5].dialogs.isEmpty)

        let items = Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id.rawValue, $0) })
        let expected: [(String, String, String, String)] = [
            ("e-za-yam", "زه یم", "za yam", "I am"),
            ("e-ta-ye", "ته یې", "ta ye", "You are (informal)"),
            ("e-taso-yast", "تاسو یاست", "TAA-so yaast", "You are (polite)"),
            ("e-hagha-day", "هغه دی", "ha-GHA day", "He is"),
            ("e-hagha-da", "هغه ده", "ha-GHA da", "She is"),
            ("e-mung-yu", "موږ یو", "mung yoo", "We are"),
            ("e-hagha-dee", "هغه \u{062f}\u{064a}", "ha-GHA dee", "They are"),
            ("e-za-na-yam", "زه نه یم", "za na yam", "I am not"),
            ("e-za-afghan-na-yam", "زه افغان نه یم", "za af-GHAAN na yam", "I'm not Afghan."),
            ("e-taso-xa-yast", "تاسو ښه یاست", "TAA-so kha yaast", "You are fine (polite)"),
            ("e-daa-khaar-day", "دا ښار دی", "daa khaar day", "It is a city"),
        ]
        for row in expected {
            let item = try #require(items[row.0])
            #expect(item.kind == .phrase)
            #expect(item.pashto == row.1)
            #expect(item.pronunciation == row.2)
            #expect(item.en == row.3)
            #expect(item.verification.status == .verified)
        }
        #expect(items["e-za-yam"]?.usage == wordOrder)
        #expect(items["e-ta-ye"]?.usage == youAre)
        #expect(items["e-taso-yast"]?.usage == youAre)
        #expect(items["e-hagha-day"]?.usage == hagha + "\n" + itLine)
        #expect(items["e-hagha-da"]?.usage == hagha + "\n" + itLine)
        #expect(items["e-za-na-yam"]?.usage == notLine)
        let mungNote = "ږ: in Kabul close to g in go; موږ is said mung. یو here means \u{2018}are\u{2019}, not \u{2018}one\u{2019}."
        let haghaNote = "غ: gh, a voiced kh, close to French r."
        #expect(items["e-mung-yu"]?.pronunciationNote == mungNote)
        #expect(items["e-mung-yu"]?.translit == "muǧ yu")
        #expect(items["e-hagha-dee"]?.pronunciationNote == haghaNote)
        #expect(items["e-hagha-dee"]?.translit == "haɣá di")
        #expect(items["e-hagha-dee"]?.pashto.unicodeScalars.last?.value == 0x064A)
        #expect(items["e-yaw"]?.pashto == "یو")
        #expect(items["e-yaw"]?.id != items["e-mung-yu"]?.id)
        let norwegian = ["uformelt", "høflig", "flertall", "til én"]
        let newIDs = [
            "e-za-yam", "e-ta-ye", "e-taso-yast", "e-hagha-day", "e-hagha-da",
            "e-mung-yu", "e-hagha-dee", "e-za-na-yam", "e-za-afghan-na-yam",
            "e-taso-xa-yast", "e-daa-khaar-day",
        ]
        for id in newIDs {
            let en = try #require(items[id]?.en)
            #expect(norwegian.allSatisfy { !en.localizedStandardContains($0) })
        }
        #expect(items["e-za-afghan-yam"]?.en == "I'm Afghan. (m)")
        #expect(items["e-za-afghana-yam"]?.en == "I'm Afghan. (f)")
        #expect(items["e-daa-do-day-da"]?.en == "This is bread.")
        #expect(unit.lessons[2].items.contains { $0.item.rawValue == "e-daa-do-day-da" } == false)

        let learn1 = unit.lessons[0].items.map(\.item.rawValue)
        let polite = unit.lessons[1].items.map(\.item.rawValue)
        let phrases = unit.lessons[2].items.map(\.item.rawValue)
        let practice = unit.lessons[3].items.map(\.item.rawValue)
        #expect(learn1 == [
            "e-za-yam", "e-ta-ye", "e-taso-yast", "e-hagha-day", "e-hagha-da",
            "e-mung-yu", "e-hagha-dee", "e-za-na-yam",
        ])
        #expect(polite == ["e-ho", "e-na", "e-xa", "e-mehrabani-wakray", "e-manana", "e-baxana-ghwaram"])
        #expect(phrases == [
            "e-za-xa-yam", "e-za-afghan-yam", "e-za-afghana-yam", "e-za-afghan-na-yam",
            "e-taso-xa-yast", "e-hagha-xa-day", "e-hagha-xa-da", "e-daa-zma-wror-day",
            "e-daa-khaar-day",
        ])
        #expect(practice == [
            "e-za-yam", "e-ta-ye", "e-taso-yast", "e-hagha-day", "e-hagha-da",
            "e-mung-yu", "e-hagha-dee", "e-za-na-yam",
            "e-za-afghan-na-yam", "e-taso-xa-yast", "e-daa-khaar-day",
        ])
        #expect(unit.lessons[4].items.map(\.item.rawValue) == ["e-yam", "e-ye", "e-day", "e-da", "e-yast"])
        #expect(unit.lessons[5].items.map(\.item.rawValue) == polite)
        #expect(unit.lessons[0].items.allSatisfy { $0.role == .present })
        #expect(unit.lessons[2].items.allSatisfy { $0.role == .present })
        #expect(unit.lessons[3].items.allSatisfy { $0.role == .introduce })

        #expect(items["e-mung-yu"]?.pronunciation == "mung yoo")
        #expect(items["e-hagha-dee"]?.pronunciation == "ha-GHA dee")

        let deck = try #require(StudyCourse.deck(for: lessonID("l-basics-learn-1"), in: bundle))
        #expect(deck.cards.map(\.explanation) == [
            wordOrder, youAre, youAre, hagha + "\n" + itLine, hagha + "\n" + itLine,
            nil, nil, notLine,
        ])
        #expect(deck.cards.map(\.itemID.rawValue).suffix(3) == ["e-mung-yu", "e-hagha-dee", "e-za-na-yam"])
        #expect(deck.cards.map(\.pronunciation).suffix(3) == ["mung yoo", "ha-GHA dee", "za na yam"])
        #expect(deck.cards.map(\.pronunciationNote).suffix(3) == [mungNote, haghaNote, nil])

        let rows = RootLessonSession.lessons(in: bundle, releasedUnitIDs: course.releasedUnitIDs)
        #expect(rows.first { $0.id.rawValue == "l-basics-learn-1" }?.title == "I am, you are, we are")
        #expect(rows.first { $0.id.rawValue == "l-basics-learn-polite" }?.title == "Yes, no and polite words")
        #expect(rows.first { $0.id.rawValue == "l-basics-phrases" }?.title == "About me and others")
        #expect(rows.first { $0.id.rawValue == "l-greetings-phrases-how" }?.title == "How are you? and goodbye")
    }

    @Test func practiceAsksTheNewItemsAndPlacementCanSkipTheUnit() throws {
        let course = try loadCourse()
        let bundle = course.bundle
        var rng = SplitMix64(seed: 9)
        let session = LessonSessionBuilder.build(
            for: lessonID("l-basics-1"),
            in: bundle,
            seenLessonIDs: [lessonID("l-basics-1")],
            releasedUnitIDs: course.releasedUnitIDs,
            using: &rng
        )
        #expect(!session.tasks.isEmpty)
        #expect(session.tasks.allSatisfy { !PlayableCourse.retiredQuizKinds.contains($0.kind) })
        let introduced: Set<String> = [
            "e-za-yam", "e-ta-ye", "e-taso-yast", "e-hagha-day", "e-hagha-da",
            "e-mung-yu", "e-hagha-dee",
            "e-za-na-yam", "e-za-afghan-na-yam", "e-taso-xa-yast", "e-daa-khaar-day",
        ]
        #expect(session.tasks.allSatisfy { introduced.isSuperset(of: referencedIDs($0)) })
        let targets = Set(session.tasks.compactMap(targetID))
        #expect(targets.isSubset(of: introduced))
        #expect(targets.count >= 5)

        var placementRNG = SplitMix64(seed: 4)
        let placement = PlacementTestBuilder.build(
            in: bundle,
            releasedUnitIDs: course.releasedUnitIDs,
            using: &placementRNG
        )
        #expect(placement.unitIDs.map(\.rawValue) == ["u-basics", "u-greetings", "u-introductions", "u-family"])
        #expect(placement.units.allSatisfy { $0.tasks.count == 5 })

        let earlier = earlierPractice.map(lessonID)
        let kept = earlier.map {
            LessonProgress(lessonID: $0, source: .completed, firstCompletedDay: day.adding(days: -3), bestScorePercent: 90)
        }
        let commit = placementCommit(
            scores: [PlacementUnitScore(unitID: unitID("u-basics"), correct: 4, questions: 5, skipped: true)],
            in: bundle,
            takenOn: day,
            existingLessons: kept
        )
        #expect(commit.lessonProgress.map(\.lessonID.rawValue) == [
            "l-basics-1", "l-basics-verbs", "l-basics-polite",
            "l-c2-quiz-1", "l-c2-quiz-2", "l-c2-quiz-3", "l-c2-quiz-4",
            "l-c4-quiz-1", "l-c4-quiz-2", "l-c4-quiz-3",
            "l-c10-quiz-1", "l-c10-quiz-2", "l-c10-quiz-3", "l-c10-quiz-4", "l-c10-quiz-5",
        ])
        #expect(commit.lessonProgress.allSatisfy { $0.source == .placement })
        #expect(Set(commit.lessonProgress.map(\.lessonID)).isDisjoint(with: Set(earlier)))

        let skippedWindow = placementCommit(
            scores: ["u-basics", "u-greetings", "u-introductions", "u-family"].map {
                PlacementUnitScore(unitID: unitID($0), correct: 4, questions: 5, skipped: true)
            },
            in: bundle,
            takenOn: day,
            existingLessons: kept
        )
        #expect(skippedWindow.lessonProgress.map(\.lessonID.rawValue) == [
            "l-basics-1", "l-basics-verbs", "l-basics-polite",
            "l-c2-quiz-1", "l-c2-quiz-2", "l-c2-quiz-3", "l-c2-quiz-4",
            "l-c4-quiz-1", "l-c4-quiz-2", "l-c4-quiz-3",
            "l-c10-quiz-1", "l-c10-quiz-2", "l-c10-quiz-3", "l-c10-quiz-4", "l-c10-quiz-5",
            "l-greetings-how", "l-c1-quiz-1", "l-c1-quiz-2", "l-c1-quiz-3",
            "l-c3-quiz-1", "l-c3-quiz-2", "l-c3-quiz-3",
            "l-c5-quiz-1", "l-c5-quiz-2", "l-c5-quiz-3", "l-c5-quiz-4",
        ])
        #expect(Set(skippedWindow.lessonProgress.map(\.lessonID)).isDisjoint(with: Set(earlier)))
    }

    @Test func theTwoYouAreLinesAreNeverOptionsInOneQuestion() throws {
        let bundle = try loadCourse().bundle
        let pair: Set<String> = ["e-ta-ye", "e-taso-yast"]
        for seed in UInt64(1)...8 {
            var seen: [LessonID] = []
            var rng = SplitMix64(seed: seed)
            for lesson in bundle.units.flatMap(\.lessons) {
                seen.append(lesson.id)
                let session = LessonSessionBuilder.build(
                    for: lesson.id,
                    in: bundle,
                    seenLessonIDs: seen,
                    maxQuestions: nil,
                    releasedUnitIDs: nil,
                    using: &rng
                )
                for task in session.tasks {
                    #expect(pair.isSubset(of: referencedIDs(task)) == false)
                }
            }
        }
    }

    @Test func survivingPracticeLessonsKeepTheItemsTheyIntroduced() throws {
        let current = try loadCourse().bundle
        let previous = try loadSnapshot("content-c0fb227.json")
        for id in earlierPractice {
            let now = try #require(current.units.flatMap(\.lessons).first { $0.id.rawValue == id })
            let then = try #require(previous.units.flatMap(\.lessons).first { $0.id.rawValue == id })
            #expect(now.items.map(\.item) == then.items.map(\.item))
            #expect(now.letters == then.letters)
            let built = session(id, in: current, seed: 1)
            #expect(!built.tasks.isEmpty)
        }
    }

    @Test @MainActor func aLearnerWhoFinishedUnitsOneThroughThreeIsNotLockedOrReset() throws {
        let course = try loadCourse()
        let bundle = course.bundle
        let practiceIDs = earlierPractice.map(lessonID)
        var cards: [ReviewCard] = []
        var seen = Set<ItemID>()
        for id in practiceIDs {
            let lesson = try #require(bundle.units.flatMap(\.lessons).first { $0.id == id })
            for card in reviewCards(introducedIn: lesson, on: day.adding(days: -3)) where seen.insert(card.itemID).inserted {
                cards.append(card)
            }
        }
        let rows = practiceIDs.map {
            LessonProgress(lessonID: $0, source: .completed, firstCompletedDay: day.adding(days: -3), bestScorePercent: 80)
        }
        let streak = StreakState.initial
        let stored = ProgressSnapshot(
            contentVersion: bundle.contentVersion,
            cards: cards,
            lessonProgress: rows,
            streak: streak,
            settings: .initial,
            activeSession: nil,
            completedSessions: [],
            lastReconciledContentVersion: nil,
            latestObservedDay: day
        )
        let reconciled = ProgressReconciler.reconcile(stored, with: bundle, on: day)
        #expect(Set(reconciled.snapshot.lessonProgress.map(\.lessonID)) == Set(practiceIDs))
        #expect(!reconciled.snapshot.lessonProgress.contains {
            $0.lessonID.rawValue.contains("learn") || $0.lessonID.rawValue.contains("phrases")
        })
        #expect(Set(reconciled.snapshot.cards.map(\.itemID)) == Set(cards.map(\.itemID)))
        #expect(reconciled.snapshot.streak == streak)

        let finished = Set(practiceIDs)
        let rowsOnPath = RootLessonSession.lessons(in: bundle, releasedUnitIDs: course.releasedUnitIDs)
        let order = rowsOnPath.map(\.id)
        let skipping = Set(rowsOnPath.filter { $0.kind != .practice }.map(\.id))
        for id in practiceIDs {
            #expect(CoursePathCopy.mark(id: id, order: order, finished: finished, locked: [], skipping: skipping) == .plain)
        }
        #expect(CoursePathCopy.mark(id: lessonID("l-basics-1"), order: order, finished: finished, locked: [], skipping: skipping) == .now)
        #expect(CoursePathCopy.mark(id: lessonID("l-greetings-phrases-hello"), order: order, finished: finished, locked: [], skipping: skipping) == .plain)

        let released = ReleasedCourse.limiting(bundle, to: course.releasedUnitIDs)
        let quiet = PathProgress(cards: [], finishedLessonIDs: finished, newItemsShownToday: 0)
        #expect(pathState(progress: quiet, content: released, goal: .regular, today: day) == .lesson(lessonID("l-basics-1")))

        let opener = OpenLesson()
        var rng = SplitMix64(seed: 3)
        opener.startLesson(
            lessonID: lessonID("l-greetings-1"),
            in: bundle,
            progress: stored,
            releasedUnitIDs: course.releasedUnitIDs,
            showsPronunciation: true,
            voiceOver: false,
            on: day,
            using: &rng
        )
        #expect(opener.session?.tasks.isEmpty == false)
    }
}

private func loadCourse() throws -> BundledCourse {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let content = try Data(contentsOf: root.appendingPathComponent("content/content.json"))
    let release = try Data(contentsOf: root.appendingPathComponent("content/release-units.json"))
    guard case .ready(let course) = BundledCourseLoader.load(content: content, releaseUnits: release) else {
        Issue.record("The bundled course did not decode")
        throw TheBasicsTestError.missing
    }
    return course
}

private enum TheBasicsTestError: Error {
    case missing
}

private func loadSnapshot(_ name: String) throws -> ContentBundle {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(name)
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(ContentBundle.self, from: data)
}

private func session(_ id: String, in bundle: ContentBundle, seed: UInt64) -> LessonSession {
    var seen: [LessonID] = []
    var rng = SplitMix64(seed: seed)
    for lesson in bundle.units.flatMap(\.lessons) {
        seen.append(lesson.id)
        if lesson.id.rawValue == id {
            return LessonSessionBuilder.build(
                for: lesson.id,
                in: bundle,
                seenLessonIDs: seen,
                maxQuestions: nil,
                releasedUnitIDs: nil,
                using: &rng
            )
        }
    }
    return LessonSession(lessonID: lessonID(id), tasks: [])
}

private func targetID(_ task: SessionTask) -> String? {
    switch task.payload {
    case .choice(let quiz):
        return quiz.targetID.rawValue
    case .orderWords(let order):
        return order.targetID.rawValue
    case .matchPairs:
        return nil
    }
}

private func referencedIDs(_ task: SessionTask) -> Set<String> {
    switch task.payload {
    case .choice(let quiz):
        return Set([quiz.targetID.rawValue] + quiz.options.map(\.itemID.rawValue))
    case .orderWords(let order):
        return [order.targetID.rawValue]
    case .matchPairs(let match):
        return Set(match.pairs.flatMap { [$0.left.itemID.rawValue, $0.right.itemID.rawValue] })
    }
}
