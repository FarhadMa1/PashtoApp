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
        "l-greetings-1", "l-greetings-2", "l-greetings-3",
        "l-introductions-1", "l-introductions-2", "l-introductions-3",
        "l-family-1", "l-family-2", "l-family-3",
    ]

    @Test func theBasicsIsFirstAmongReleasedUnitsAndUsesTheApprovedText() throws {
        let course = try loadCourse()
        let bundle = course.bundle
        #expect(bundle.units.map(\.id.rawValue).prefix(2) == ["u-sounds", "u-basics"])
        #expect(course.releasedUnitIDs.map(\.rawValue) == ["u-basics", "u-greetings", "u-introductions", "u-family"])

        let unit = try #require(bundle.units.first { $0.id.rawValue == "u-basics" })
        #expect(unit.title == "The basics")
        #expect(unit.lessons.map(\.id.rawValue) == [
            "l-basics-learn-1", "l-basics-learn-2", "l-basics-phrases", "l-basics-1",
        ])
        #expect(unit.lessons.map(\.title) == [
            "I am, you are, he/she is",
            "We are, they are, I am not",
            "About me and others",
            "Practice: The basics",
        ])
        #expect(unit.lessons[0].kind == .learn)
        #expect(unit.lessons[1].kind == .learn)
        #expect(unit.lessons[2].kind == .phrases)
        #expect(unit.lessons[3].kind == .practice)
        #expect(unit.lessons[3].countsForProgress)
        #expect(!unit.lessons[0].countsForProgress)
        #expect(unit.lessons.allSatisfy { $0.letters.isEmpty && $0.dialogs.isEmpty })

        let items = Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id.rawValue, $0) })
        let expected: [(String, String, String, String)] = [
            ("e-za-yam", "زه یم", "za yam", "I am"),
            ("e-ta-ye", "ته یې", "ta ye", "you are (informal, to one person)"),
            ("e-taso-yast", "تاسو یاست", "TAA-so yaast", "you are (polite/plural)"),
            ("e-hagha-day", "هغه دی", "ha-GHA day", "he is"),
            ("e-hagha-da", "هغه ده", "ha-GHA da", "she is"),
            ("e-mung-yu", "موږ یو", "mung yoo", "we are"),
            ("e-hagha-dee", "هغه \u{062f}\u{064a}", "ha-GHA dee", "they are"),
            ("e-za-na-yam", "زه نه یم", "za na yam", "I am not"),
            ("e-za-afghan-na-yam", "زه افغان نه یم", "za af-GHAAN na yam", "I'm not Afghan"),
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
        let mungNote = "ږ is pronounced g in the selected Kabul pronunciation; موږ is said mung. یو here means \u{2018}are\u{2019}, not \u{2018}one\u{2019}."
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
        #expect(items["e-za-afghan-yam"]?.en == "I'm Afghan")
        #expect(items["e-za-afghana-yam"]?.en == "I'm Afghan")
        #expect(items["e-daa-do-day-da"]?.en == "this is bread")
        #expect(unit.lessons[2].items.contains { $0.item.rawValue == "e-daa-do-day-da" } == false)

        let learn1 = unit.lessons[0].items.map(\.item.rawValue)
        let learn2 = unit.lessons[1].items.map(\.item.rawValue)
        let phrases = unit.lessons[2].items.map(\.item.rawValue)
        let practice = unit.lessons[3].items.map(\.item.rawValue)
        #expect(learn1 == ["e-za-yam", "e-ta-ye", "e-taso-yast", "e-hagha-day", "e-hagha-da"])
        #expect(learn2 == ["e-mung-yu", "e-hagha-dee", "e-za-na-yam"])
        #expect(phrases == [
            "e-za-xa-yam", "e-za-afghan-yam", "e-za-afghana-yam", "e-za-afghan-na-yam",
            "e-taso-xa-yast", "e-hagha-xa-day", "e-hagha-xa-da", "e-daa-zma-wror-day",
            "e-daa-khaar-day",
        ])
        #expect(practice == learn1 + ["e-mung-yu", "e-hagha-dee", "e-za-na-yam", "e-za-afghan-na-yam", "e-taso-xa-yast", "e-daa-khaar-day"])
        #expect(unit.lessons[0].items.allSatisfy { $0.role == .present })
        #expect(unit.lessons[2].items.allSatisfy { $0.role == .present })
        #expect(unit.lessons[3].items.allSatisfy { $0.role == .introduce })

        #expect(items["e-mung-yu"]?.pronunciation == "mung yoo")
        #expect(items["e-hagha-dee"]?.pronunciation == "ha-GHA dee")

        let deck = try #require(StudyCourse.deck(for: lessonID("l-basics-learn-1"), in: bundle))
        #expect(deck.cards.map(\.explanation) == [wordOrder, youAre, youAre, hagha + "\n" + itLine, hagha + "\n" + itLine])
        let second = try #require(StudyCourse.deck(for: lessonID("l-basics-learn-2"), in: bundle))
        #expect(second.cards.map(\.itemID.rawValue) == ["e-mung-yu", "e-hagha-dee", "e-za-na-yam"])
        #expect(second.cards.map(\.pronunciation) == ["mung yoo", "ha-GHA dee", "za na yam"])
        #expect(second.cards.map(\.explanation) == [nil, nil, notLine])
        #expect(second.cards.map(\.pronunciationNote) == [mungNote, haghaNote, nil])

        let rows = RootLessonSession.lessons(in: bundle, releasedUnitIDs: course.releasedUnitIDs)
        #expect(rows.first { $0.id.rawValue == "l-basics-learn-1" }?.title == "I am, you are, he/she is")
        #expect(rows.first { $0.id.rawValue == "l-basics-learn-2" }?.title == "We are, they are, I am not")
        #expect(rows.first { $0.id.rawValue == "l-basics-phrases" }?.title == "About me and others")
        #expect(rows.first { $0.id.rawValue == "l-greetings-learn" }?.title == "Key words")
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
        #expect(commit.lessonProgress.map(\.lessonID.rawValue) == ["l-basics-1"])
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
        #expect(skippedWindow.lessonProgress.map(\.lessonID.rawValue) == ["l-basics-1"])
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

    @Test func existingPracticeLessonsKeepTheQuestionSetsFromBeforeTheBasics() throws {
        let current = try loadCourse().bundle
        let previous = try loadSnapshot("content-c0fb227.json")
        let ids = earlierPractice
        for id in ids {
            for seed in [UInt64(1), 2, 7] {
                let now = session(id, in: current, seed: seed)
                let then = session(id, in: previous, seed: seed)
                #expect(now.tasks == then.tasks)
            }
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
        #expect(CoursePathCopy.mark(id: lessonID("l-greetings-learn"), order: order, finished: finished, locked: [], skipping: skipping) == .plain)

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

    @Test func basicsListMatchesLearnCardsInOrderAndDoesNotChangeProgress() throws {
        let course = try loadCourse()
        let bundle = course.bundle
        let unit = try #require(bundle.units.first { $0.id.rawValue == BasicsCatalog.unitRawValue })
        let cards = BasicsCatalog.learnCards(in: bundle, releasedUnitIDs: course.releasedUnitIDs)
        let learnLessons = unit.lessons.filter { $0.kind == .learn }
        let expectedIDs = learnLessons.flatMap { lesson in
            lesson.items.filter { $0.role == .present }.map(\.item.rawValue)
        }
        #expect(learnLessons.map(\.id.rawValue) == ["l-basics-learn-1", "l-basics-learn-2"])
        #expect(!cards.isEmpty)
        #expect(cards.map(\.itemID.rawValue) == expectedIDs)
        #expect(BasicsCatalog.learnCards(in: bundle, releasedUnitIDs: course.releasedUnitIDs) == cards)

        let items = Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id, $0) })
        for card in cards {
            let item = try #require(items[card.itemID])
            let meaning = item.en?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            #expect(card.pronunciation == item.pronunciation)
            #expect(card.pashto == item.pashto)
            #expect(card.meaning == meaning)
        }
        let released = ReleasedCourse.limiting(bundle, to: course.releasedUnitIDs)
        var fromLessons: [StudyCard] = []
        for lesson in learnLessons {
            fromLessons.append(contentsOf: try #require(StudyCourse.deck(for: lesson.id, in: released)).cards)
        }
        #expect(cards == fromLessons)

        let phraseOnly = Set(unit.lessons.filter { $0.kind == .phrases }.flatMap { $0.items.map(\.item.rawValue) })
            .subtracting(expectedIDs)
        #expect(!phraseOnly.isEmpty)
        #expect(Set(cards.map(\.itemID.rawValue)).isDisjoint(with: phraseOnly))
        #expect(cards.contains { $0.itemID.rawValue == "e-xa" } == false)
        #expect(BasicsCatalog.learnCards(in: bundle, releasedUnitIDs: [unitID("u-greetings")]).isEmpty)
        #expect(BasicsCatalog.learnCards(in: bundle, releasedUnitIDs: []).isEmpty)

        let task = SessionTask(payload: .choice(QuizTask(
            kind: .meaningPashtoToEnglish,
            targetID: itemID("e-za-yam"),
            prompt: "زه یم",
            usage: nil,
            options: [QuizOption(itemID: itemID("e-za-yam"), text: "I am")]
        )))
        let progress = ProgressSnapshot(
            contentVersion: bundle.contentVersion,
            cards: [
                ReviewCard(
                    itemID: itemID("e-za-yam"),
                    easeFactor: 2.7,
                    intervalDays: 6,
                    repetitions: 2,
                    lapses: 0,
                    dueDay: day,
                    lastReviewedDay: day.adding(days: -1),
                    createdDay: day.adding(days: -3),
                    state: .active,
                    source: .lesson
                ),
            ],
            lessonProgress: [
                LessonProgress(
                    lessonID: lessonID("l-basics-1"),
                    source: .placement,
                    firstCompletedDay: day.adding(days: -1),
                    bestScorePercent: 80
                ),
            ],
            streak: StreakState(
                current: 4,
                longest: 9,
                lastActiveDay: day,
                freezes: 1,
                daysTowardNextFreeze: 3,
                freezeUsedDays: [day.adding(days: -2)]
            ),
            settings: UserSettings(
                dailyGoal: .serious,
                showTransliteration: false,
                placementTakenDay: day
            ),
            activeSession: ActiveSessionSnapshot(
                sessionID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                kind: .lesson,
                lessonID: lessonID("l-basics-1"),
                startedDay: day,
                lastAnswerDay: day,
                contentVersion: bundle.contentVersion,
                lesson: LessonSession(lessonID: lessonID("l-basics-1"), tasks: [task])
            ),
            completedSessions: [
                CompletedSession(
                    sessionID: UUID(uuidString: "BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    kind: .lesson,
                    lessonID: lessonID("l-greetings-1"),
                    completedDay: day.adding(days: -1),
                    questionCount: 11,
                    firstTryCorrect: 9
                ),
            ],
            lastReconciledContentVersion: bundle.contentVersion,
            latestObservedDay: day
        )
        var browser = BasicsBrowser(progress: progress, cards: cards)
        let before = browser.progress
        browser.open()
        #expect(browser.isOpen)
        for card in cards {
            browser.view(card.itemID)
            #expect(browser.visibleCard == card)
            #expect(browser.progress == before)
        }
        browser.view(itemID("e-salam"))
        #expect(browser.visibleCard?.itemID == cards.last?.itemID)
        browser.closeCard()
        #expect(browser.visibleCard == nil)
        browser.close()
        #expect(browser.isOpen == false)
        #expect(browser.visibleItemID == nil)
        #expect(browser.cards == cards)
        #expect(browser.progress == before)
        #expect(browser.progress.lessonProgress == before.lessonProgress)
        #expect(browser.progress.cards == before.cards)
        #expect(browser.progress.streak == before.streak)
        #expect(browser.progress.settings == before.settings)
        #expect(browser.progress.activeSession == before.activeSession)
        #expect(browser.progress.completedSessions == before.completedSessions)
        #expect(browser.progress.settings.placementTakenDay == day)
        #expect(browser.progress.settings.dailyGoal == .serious)
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
