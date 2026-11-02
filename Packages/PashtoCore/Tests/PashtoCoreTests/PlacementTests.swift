import Foundation
import Testing

@testable import PashtoCore

struct PlacementTests {
    private let day = LocalDay(year: 2026, month: 11, day: 2)

    @Test func fourOfFiveSkipsAndThreeOfFiveStops() {
        let units = [unitID("u-greetings"), unitID("u-introductions"), unitID("u-family")]
        var skip = PlacementEvaluator(unitIDs: units)
        #expect(feed(&skip, correct: 4, of: 5) == .skipped(units[0], next: units[1]))
        #expect(skip.skippedUnitIDs == [units[0]])
        #expect(!skip.isFinished)

        var stop = PlacementEvaluator(unitIDs: units)
        #expect(feed(&stop, correct: 3, of: 5) == .stopped(units[0]))
        #expect(stop.skippedUnitIDs.isEmpty)
        #expect(stop.isFinished)
        #expect(stop.record(correct: true) == .stopped(units[0]))
    }

    @Test func stoppingInUnitOneLeavesTheLaterUnits() {
        let units = [unitID("u-greetings"), unitID("u-introductions"), unitID("u-family")]
        var evaluator = PlacementEvaluator(unitIDs: units)
        #expect(feed(&evaluator, correct: 3, of: 5) == .stopped(units[0]))
        #expect(evaluator.results.map(\.unitID) == [units[0]])
        #expect(evaluator.results[0].skipped == false)
        #expect(evaluator.skippedUnitIDs.isEmpty)
    }

    @Test func everyUnitCanBeSkipped() {
        let units = [unitID("u-greetings"), unitID("u-introductions"), unitID("u-family")]
        var evaluator = PlacementEvaluator(unitIDs: units)
        #expect(feed(&evaluator, correct: 4, of: 5) == .skipped(units[0], next: units[1]))
        #expect(feed(&evaluator, correct: 5, of: 5) == .skipped(units[1], next: units[2]))
        #expect(feed(&evaluator, correct: 4, of: 5) == .skipped(units[2], next: nil))
        #expect(evaluator.skippedUnitIDs == units)
        #expect(evaluator.isFinished)
        #expect(evaluator.record(correct: true) == .finished)
    }

    @Test func thePolicySuppliesTheSkipLine() {
        let unit = unitID("u-greetings")
        let policy = PlacementPolicy(questionsPerUnit: 3, correctToSkip: 2, unitCount: 1)
        var evaluator = PlacementEvaluator(unitIDs: [unit], policy: policy)
        #expect(feed(&evaluator, correct: 2, of: 3) == .skipped(unit, next: nil))
        var stop = PlacementEvaluator(unitIDs: [unit], policy: policy)
        #expect(feed(&stop, correct: 1, of: 3) == .stopped(unit))
    }

    @Test func theAlphabetIsNeverAPlacementUnit() {
        let bundle = fourUnitBundle()
        let released = [
            unitID("u-sounds"),
            unitID("u-greetings"),
            unitID("u-introductions"),
            unitID("u-family"),
        ]
        var rng = SplitMix64(seed: 11)
        let test = PlacementTestBuilder.build(in: bundle, releasedUnitIDs: released, using: &rng)
        #expect(!test.unitIDs.contains(unitID("u-sounds")))
        #expect(test.units.allSatisfy { $0.tasks.count == 5 })

        let scores = test.unitIDs.map {
            PlacementUnitScore(unitID: $0, correct: 5, questions: 5, skipped: true)
        } + [PlacementUnitScore(unitID: unitID("u-sounds"), correct: 5, questions: 5, skipped: true)]
        let commit = placementCommit(scores: scores, in: bundle, takenOn: day)
        #expect(!commit.lessonProgress.contains { $0.lessonID.rawValue == "l-sounds" })
        let introducedInSounds = Set(itemIDs(in: unitID("u-sounds"), bundle: bundle))
        #expect(commit.cards.allSatisfy { !introducedInSounds.contains($0.itemID) })
    }

    @Test func anUnreleasedUnitIsLeftOut() {
        let bundle = fourUnitBundle()
        let released = [unitID("u-sounds"), unitID("u-greetings"), unitID("u-introductions")]
        var rng = SplitMix64(seed: 5)
        let test = PlacementTestBuilder.build(in: bundle, releasedUnitIDs: released, using: &rng)
        #expect(test.unitIDs.map(\.rawValue) == ["u-greetings", "u-introductions"])
        let familyItems = Set(itemIDs(in: unitID("u-family"), bundle: bundle))
        #expect(Set(referencedItemIDs(in: test)).isDisjoint(with: familyItems))

        var passed = PlacementEvaluator(unitIDs: test.unitIDs)
        #expect(feed(&passed, correct: 4, of: 5) == .skipped(unitID("u-greetings"), next: unitID("u-introductions")))
        #expect(feed(&passed, correct: 4, of: 5) == .skipped(unitID("u-introductions"), next: nil))
        let commit = placementCommit(scores: passed.results, in: bundle, takenOn: day)
        #expect(commit.placementTakenDay == day)
        #expect(commit.lessonProgress.map(\.lessonID.rawValue) == ["l-greetings-1", "l-introductions-1"])
        #expect(commit.lessonProgress.allSatisfy { $0.bestScorePercent == 80 && $0.source == .placement })
        #expect(commit.cards.allSatisfy { !familyItems.contains($0.itemID) && $0.source == .placement })
    }

    @Test func anUnreleasedUnitStopsTheTestBeforeALaterReleasedUnit() {
        let bundle = fourUnitBundle()
        let released = [unitID("u-greetings"), unitID("u-family")]
        var rng = SplitMix64(seed: 6)
        let test = PlacementTestBuilder.build(in: bundle, releasedUnitIDs: released, using: &rng)
        #expect(test.unitIDs.map(\.rawValue) == ["u-greetings"])

        var evaluator = PlacementEvaluator(unitIDs: test.unitIDs)
        #expect(feed(&evaluator, correct: 4, of: 5) == .skipped(unitID("u-greetings"), next: nil))
        let commit = placementCommit(scores: evaluator.results, in: bundle, takenOn: day)
        #expect(commit.lessonProgress.map(\.lessonID.rawValue) == ["l-greetings-1"])
        #expect(commit.lessonProgress.allSatisfy { $0.bestScorePercent == 80 })
        let later = Set(itemIDs(in: unitID("u-introductions"), bundle: bundle))
            .union(itemIDs(in: unitID("u-family"), bundle: bundle))
        #expect(commit.cards.allSatisfy { !later.contains($0.itemID) })
        #expect(commit.cards.allSatisfy { $0.dueDay >= day.adding(days: 1) })
    }

    @Test func unitsOneThroughThreeAreAskedOnceTheyAreReleased() {
        let bundle = fourUnitBundle()
        let released = [
            unitID("u-sounds"),
            unitID("u-greetings"),
            unitID("u-introductions"),
            unitID("u-family"),
        ]
        var rng = SplitMix64(seed: 8)
        let test = PlacementTestBuilder.build(in: bundle, releasedUnitIDs: released, using: &rng)
        #expect(test.unitIDs.map(\.rawValue) == ["u-greetings", "u-introductions", "u-family"])
        #expect(test.units.allSatisfy { $0.tasks.count == 5 })
    }

    @Test func aUnitThatCannotFillFiveQuestionsStopsTheTestAndIsNotSkipped() {
        let sounds = placedUnit("u-sounds", lessons: [placedLesson("l-sounds", items: [], examples: [placedWord(90)])])
        let greetings = placedUnit("u-greetings", lessons: [placedLesson("l-greetings-1", items: words(1...6))])
        let introductions = placedUnit("u-introductions", lessons: [placedLesson("l-introductions-1", items: [placedWord(11)])])
        let family = placedUnit("u-family", lessons: [placedLesson("l-family-1", items: words(21...26))])
        let bundle = makeBundle(
            items: [placedWord(90), placedWord(11)] + words(1...6) + words(21...26),
            units: [sounds, greetings, introductions, family]
        )
        let released = [unitID("u-sounds"), unitID("u-greetings"), unitID("u-introductions"), unitID("u-family")]
        var rng = SplitMix64(seed: 9)
        let test = PlacementTestBuilder.build(in: bundle, releasedUnitIDs: released, using: &rng)
        #expect(test.unitIDs.map(\.rawValue) == ["u-greetings"])

        var evaluator = PlacementEvaluator(unitIDs: test.unitIDs)
        #expect(feed(&evaluator, correct: 4, of: 5) == .skipped(unitID("u-greetings"), next: nil))
        #expect(evaluator.skippedUnitIDs == [unitID("u-greetings")])
        let commit = placementCommit(scores: evaluator.results, in: bundle, takenOn: day)
        #expect(commit.lessonProgress.map(\.lessonID.rawValue) == ["l-greetings-1"])
        #expect(commit.lessonProgress[0].bestScorePercent == 80)
        let blocked = Set(itemIDs(in: unitID("u-introductions"), bundle: bundle))
            .union(itemIDs(in: unitID("u-family"), bundle: bundle))
        #expect(commit.cards.allSatisfy { !blocked.contains($0.itemID) })

        var finished = Set(commit.lessonProgress.map(\.lessonID))
        finished.insert(lessonID("l-sounds"))
        let progress = PathProgress(cards: commit.cards, finishedLessonIDs: finished, newItemsShownToday: 0)
        #expect(pathState(progress: progress, content: bundle, goal: .regular, today: day) == .lesson(lessonID("l-introductions-1")))
        #expect(!finished.contains(lessonID("l-introductions-1")))
        #expect(!finished.contains(lessonID("l-family-1")))
    }

    @Test func distractorsStayInTheTestedUnitAndKeepTheSameType() {
        let sounds = placedUnit("u-sounds", lessons: [placedLesson("l-sounds", items: [], examples: [placedWord(90)])])
        let earlyItems = words(1...6)
        let hereWords = words(11...13)
        let hereLetters = (1...3).map(placedLetter)
        let laterItems = words(21...26)
        let early = placedUnit("u-early", lessons: [placedLesson("l-early", items: earlyItems)])
        let here = placedUnit("u-here", lessons: [placedLesson("l-here", items: hereWords + hereLetters)])
        let later = placedUnit("u-later", lessons: [placedLesson("l-later", items: laterItems)])
        let bundle = makeBundle(
            items: [placedWord(90)] + earlyItems + hereWords + hereLetters + laterItems,
            units: [sounds, early, here, later]
        )
        let released = [unitID("u-sounds"), unitID("u-early"), unitID("u-here"), unitID("u-later")]
        var rng = SplitMix64(seed: 12)
        let test = PlacementTestBuilder.build(in: bundle, releasedUnitIDs: released, using: &rng)
        #expect(test.unitIDs.map(\.rawValue) == ["u-early", "u-here", "u-later"])
        let kindByID = Dictionary(bundle.items.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
        for questions in test.units {
            let own = itemIDs(in: questions.unitID, bundle: bundle)
            let ownSet = Set(own)
            for task in questions.tasks {
                let ids = itemIDs(in: task)
                #expect(ids.allSatisfy { ownSet.contains($0) })
                switch task.payload {
                case .choice(let quiz):
                    let kind = kindByID[quiz.targetID]
                    #expect(quiz.options.allSatisfy { kindByID[$0.itemID] == kind })
                    let pool = own.filter { kindByID[$0] == kind }
                    #expect(quiz.options.count <= pool.count)
                case .matchPairs(let match):
                    let kinds = Set(match.pairs.flatMap { [kindByID[$0.left.itemID], kindByID[$0.right.itemID]] }.compactMap { $0 })
                    #expect(kinds.count == 1)
                case .orderWords:
                    break
                }
            }
        }
    }

    @Test func aMissingUnitEndsTheTestWithoutAnEmptySession() {
        let sounds = placedUnit("u-sounds", lessons: [placedLesson("l-sounds", items: [], examples: [placedWord(90)])])
        let greetings = placedUnit("u-greetings", lessons: [placedLesson("l-greetings-1", items: words(1...6))])
        let introductions = placedUnit("u-introductions", lessons: [placedLesson("l-introductions-1", items: words(11...16))])
        let bundle = makeBundle(
            items: [placedWord(90)] + words(1...6) + words(11...16),
            units: [sounds, greetings, introductions]
        )
        let released = [unitID("u-greetings"), unitID("u-introductions"), unitID("u-family")]
        var rng = SplitMix64(seed: 4)
        let test = PlacementTestBuilder.build(in: bundle, releasedUnitIDs: released, using: &rng)
        #expect(test.unitIDs.map(\.rawValue) == ["u-greetings", "u-introductions"])
        #expect(test.units.allSatisfy { $0.tasks.count == 5 })
    }

    @Test func theSameSeedBuildsTheSameTest() {
        let bundle = fourUnitBundle()
        let released = [unitID("u-greetings"), unitID("u-introductions")]
        var first = SplitMix64(seed: 42)
        var second = SplitMix64(seed: 42)
        let left = PlacementTestBuilder.build(in: bundle, releasedUnitIDs: released, using: &first)
        let right = PlacementTestBuilder.build(in: bundle, releasedUnitIDs: released, using: &second)
        #expect(left == right)
        #expect(left.units.allSatisfy { $0.tasks.count == 5 })
    }

    @Test func fortyFiveCardsSpreadAcrossFiveDaysAndEightyContinuePastTheFirstWeek() {
        let start = day
        let fortyFive = PlacementScheduler.cards(for: itemIDs(45), takenOn: start)
        let firstDue = start.adding(days: 1)
        #expect(fortyFive.first?.dueDay == firstDue)
        #expect(dueCounts(fortyFive, from: firstDue) == [10, 10, 10, 10, 5])
        #expect(fortyFive.map(\.itemID.rawValue) == itemIDs(45).map(\.rawValue))
        #expect(fortyFive.allSatisfy { $0.source == .placement && $0.createdDay == start && $0.state == .active })

        let eighty = PlacementScheduler.cards(for: itemIDs(80), takenOn: start)
        let counts = dueCounts(eighty, from: firstDue)
        #expect(counts == Array(repeating: 10, count: 8))
        #expect(counts[7] == 10)
        #expect(eighty[70].dueDay == start.adding(days: 8))
        #expect(eighty[79].dueDay == start.adding(days: 8))
    }

    @Test func skippedLessonsAreUnlockedAndTheAlphabetComesFirst() async throws {
        let bundle = spreadBundle()
        let score = PlacementUnitScore(unitID: unitID("u-greetings"), correct: 4, questions: 5, skipped: true)
        let commit = placementCommit(scores: [score], in: bundle, takenOn: day)
        #expect(commit.lessonProgress.map(\.lessonID.rawValue) == ["l-greetings-1"])
        #expect(commit.lessonProgress[0].source == .placement)
        #expect(commit.lessonProgress[0].bestScorePercent == 80)
        #expect(commit.lessonProgress[0].firstCompletedDay == day)
        #expect(commit.cards.map(\.itemID.rawValue) == (1...12).map { "e-\($0)" })
        #expect(commit.cards.first?.dueDay == day.adding(days: 1))
        #expect(dueCounts(commit.cards, from: day.adding(days: 1)) == [10, 2])
        #expect(!commit.cards.contains { $0.itemID.rawValue == "e-sound" })

        let store = InMemoryProgressStore(contentVersion: "test")
        _ = try await ProgressReconciler.run(store: store, content: bundle, on: day)
        try await store.applyPlacement(commit)
        let stored = try await store.load()
        let again = try await ProgressReconciler.run(store: store, content: bundle, on: day)
        #expect(again == stored)

        let progress = pathProgress(stored, on: day)
        #expect(progress.finishedLessonIDs == [lessonID("l-greetings-1")])
        #expect(progress.newItemsShownToday == 0)
        #expect(pathState(progress: progress, content: bundle, goal: .regular, today: day) == .lesson(lessonID("l-sounds")))
        let nextDay = day.adding(days: 1)
        let due = pathProgress(stored, on: nextDay)
        #expect(pathState(progress: due, content: bundle, goal: .regular, today: nextDay) == .review(dueCount: 10))
    }

    @Test func placementLeavesTheStreakUnchanged() async throws {
        let store = InMemoryProgressStore(contentVersion: "test")
        let streak = StreakState(
            current: 4,
            longest: 9,
            lastActiveDay: day.adding(days: -3),
            freezes: 1,
            daysTowardNextFreeze: 2,
            freezeUsedDays: []
        )
        let session = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA9")!
        try await store.commit(SessionCommit(
            sessionID: session,
            cards: [],
            lessonProgress: nil,
            streak: streak,
            completed: CompletedSession(
                sessionID: session,
                kind: .review,
                lessonID: nil,
                completedDay: day.adding(days: -3),
                questionCount: 1,
                firstTryCorrect: 1
            )
        ))
        try await store.applyPlacement(PlacementCommit(lessonProgress: [], cards: [], placementTakenDay: day))
        let loaded = try await store.load()
        #expect(loaded.streak == streak)
        #expect(loaded.settings.placementTakenDay == day)
    }

    @Test func applyPlacementKeepsAnExistingCardAndDoesNotLowerAScore() async throws {
        let store = InMemoryProgressStore(contentVersion: "test")
        let kept = ReviewCard(
            itemID: itemID("e-1"),
            easeFactor: 1.7,
            intervalDays: 6,
            repetitions: 3,
            lapses: 1,
            dueDay: day.adding(days: -4),
            lastReviewedDay: day.adding(days: -10),
            createdDay: day.adding(days: -30),
            state: .active,
            source: .lesson
        )
        let finished = LessonProgress(
            lessonID: lessonID("l-greetings-1"),
            source: .completed,
            firstCompletedDay: day.adding(days: -30),
            bestScorePercent: 100
        )
        let session = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBB1")!
        try await store.commit(SessionCommit(
            sessionID: session,
            cards: [kept],
            lessonProgress: finished,
            streak: .initial,
            completed: CompletedSession(
                sessionID: session,
                kind: .lesson,
                lessonID: finished.lessonID,
                completedDay: finished.firstCompletedDay,
                questionCount: 5,
                firstTryCorrect: 5
            )
        ))
        try await store.applyPlacement(PlacementCommit(
            lessonProgress: [
                LessonProgress(
                    lessonID: finished.lessonID,
                    source: .placement,
                    firstCompletedDay: day,
                    bestScorePercent: 80
                ),
            ],
            cards: [
                ReviewCard.introduced(itemID: kept.itemID, on: day.adding(days: 1), source: .placement),
                ReviewCard.introduced(itemID: itemID("e-new"), on: day.adding(days: 1), source: .placement),
            ],
            placementTakenDay: day
        ))
        let loaded = try await store.load()
        #expect(loaded.cards.first { $0.itemID == kept.itemID } == kept)
        #expect(loaded.lessonProgress == [finished])
        #expect(loaded.cards.contains { $0.itemID.rawValue == "e-new" && $0.source == .placement })
    }

    @Test func stoppingStillStoresTheDay() async throws {
        let store = InMemoryProgressStore(contentVersion: "test")
        try await store.updateSettings(UserSettings(dailyGoal: .serious, showTransliteration: false, placementTakenDay: nil))
        try await store.applyPlacement(PlacementCommit(lessonProgress: [], cards: [], placementTakenDay: day))
        let loaded = try await store.load()
        #expect(loaded.settings.placementTakenDay == day)
        #expect(loaded.settings.dailyGoal == .serious)
        #expect(loaded.settings.showTransliteration == false)
        #expect(loaded.lessonProgress.isEmpty)
        #expect(loaded.cards.isEmpty)
    }

    @Test func anExistingLessonAndCardStay() {
        let bundle = spreadBundle()
        let existingLesson = LessonProgress(
            lessonID: lessonID("l-greetings-1"),
            source: .completed,
            firstCompletedDay: day.adding(days: -2),
            bestScorePercent: 100
        )
        let existingCard = ReviewCard.introduced(itemID: itemID("e-1"), on: day.adding(days: -2))
        let score = PlacementUnitScore(unitID: unitID("u-greetings"), correct: 4, questions: 5, skipped: true)
        let commit = placementCommit(
            scores: [score],
            in: bundle,
            takenOn: day,
            existingCards: [existingCard],
            existingLessons: [existingLesson]
        )
        #expect(commit.lessonProgress.isEmpty)
        #expect(!commit.cards.contains { $0.itemID == itemID("e-1") })
        #expect(commit.cards.map(\.itemID.rawValue) == (2...12).map { "e-\($0)" })
    }
}

@discardableResult
private func feed(_ evaluator: inout PlacementEvaluator, correct hits: Int, of total: Int) -> PlacementStep {
    var step = PlacementStep.ongoing
    for index in 0..<total {
        step = evaluator.record(correct: index < hits)
    }
    return step
}

private func dueCounts(_ cards: [ReviewCard], from day: LocalDay) -> [Int] {
    var counts: [Int] = []
    var index = 0
    var cursor = day
    while index < cards.count {
        var count = 0
        while index < cards.count, cards[index].dueDay == cursor {
            count += 1
            index += 1
        }
        if count == 0 {
            break
        }
        counts.append(count)
        cursor = cursor.adding(days: 1)
    }
    return counts
}

private func itemIDs(_ count: Int) -> [ItemID] {
    (1...count).map { itemID("e-\($0)") }
}

private func words(_ range: ClosedRange<Int>) -> [ContentItem] {
    range.map(placedWord)
}

private func fourUnitBundle() -> ContentBundle {
    let sounds = placedUnit("u-sounds", lessons: [placedLesson("l-sounds", items: [], examples: [placedWord(90)])])
    let greetings = placedUnit("u-greetings", lessons: [placedLesson("l-greetings-1", items: words(1...6))])
    let introductions = placedUnit("u-introductions", lessons: [placedLesson("l-introductions-1", items: words(11...16))])
    let family = placedUnit("u-family", lessons: [placedLesson("l-family-1", items: words(21...26))])
    return makeBundle(
        items: [placedWord(90)] + words(1...6) + words(11...16) + words(21...26),
        units: [sounds, greetings, introductions, family]
    )
}

private func placedLetter(_ number: Int) -> ContentItem {
    let glyphs = ["ا", "ب", "پ", "ت", "ث", "ج"]
    let glyph = glyphs[number - 1]
    return makeItem(
        "e-letter-\(number)",
        kind: .letter,
        pashto: glyph,
        translit: "letter\(number)",
        pronunciation: "letter\(number)",
        en: "letter \(number)",
        name: "letter \(number)"
    )
}

private func placedWord(_ number: Int) -> ContentItem {
    makeItem(
        "e-\(number)",
        pashto: "w\(number)",
        translit: "w\(number)",
        pronunciation: "p\(number)",
        en: "word \(number)"
    )
}

private func placedLesson(_ id: String, items: [ContentItem], examples: [ContentItem] = []) -> Lesson {
    let introduced = items.map { LessonItemRef(item: $0.id, role: .introduce) }
    let shown = examples.map { LessonItemRef(item: $0.id, role: .soundExample, sound: "a") }
    return Lesson(id: lessonID(id), title: id, items: introduced + shown)
}

private func placedUnit(_ id: String, lessons: [Lesson]) -> CourseUnit {
    CourseUnit(id: unitID(id), track: "main", title: id, lessons: lessons)
}

/// Twelve introduced words, one sound example that is not introduced, and the alphabet lesson.
private func spreadBundle() -> ContentBundle {
    let introduced = words(1...12)
    let sound = placedWord(99)
    let rewritten = makeItem(
        "e-sound",
        pashto: "sound",
        translit: "sound",
        pronunciation: "sound",
        en: "sound"
    )
    let sounds = placedUnit("u-sounds", lessons: [placedLesson("l-sounds", items: [], examples: [rewritten])])
    let greetings = placedUnit(
        "u-greetings",
        lessons: [placedLesson("l-greetings-1", items: introduced, examples: [rewritten])]
    )
    return makeBundle(items: introduced + [rewritten, sound], units: [sounds, greetings])
}

private func itemIDs(in unit: UnitID, bundle: ContentBundle) -> [ItemID] {
    guard let index = bundle.units.firstIndex(where: { $0.id == unit }) else { return [] }
    return CourseOrder(bundle).introductions.filter { $0.unitIndex == index }.map(\.itemID)
}

private func referencedItemIDs(in test: PlacementTest) -> [ItemID] {
    test.units.flatMap(\.tasks).flatMap(itemIDs(in:))
}

private func itemIDs(in task: SessionTask) -> [ItemID] {
    switch task.payload {
    case .choice(let quiz):
        return [quiz.targetID] + quiz.options.map(\.itemID)
    case .orderWords(let order):
        return [order.targetID]
    case .matchPairs(let match):
        return match.pairs.flatMap { [$0.left.itemID, $0.right.itemID] }
    }
}

