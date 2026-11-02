import Foundation
import PashtoCore

/// A failed check in `ProgressStoreContract`. The message names the scenario.
public struct ProgressStoreContractFailure: Error, Equatable, CustomStringConvertible {
    public let scenario: String
    public let message: String

    public var description: String { "\(scenario): \(message)" }
}

/// The error a store throws when a write cannot be saved.
public struct ProgressStoreContractError: Error, Equatable, CustomStringConvertible {
    public static let writeFailed = ProgressStoreContractError(message: "write failed")

    public let message: String

    public var description: String { message }
}

/// The scenarios a `ProgressStore` has to pass.
///
/// `run` builds a fresh store for each scenario. `PashtoCore` runs it against
/// `InMemoryProgressStore`. A SwiftData store can run the same function.
/// `runWriteFailure` needs a store whose `commit` throws and leaves the
/// active session in place. `InMemoryProgressStore` does not fail a write;
/// `CommitRejectingProgressStore` does.
public enum ProgressStoreContract {
    public static func run(makeStore: @Sendable () async throws -> any ProgressStore) async throws {
        try await fresh(makeStore, "empty store", emptyStore)
        try await fresh(makeStore, "active session", activeSessionCreatesNoCards)
        try await fresh(makeStore, "commit", commitWritesTheFinishedLesson)
        try await fresh(makeStore, "commit leaves another session", commitLeavesADifferentActiveSession)
        try await fresh(makeStore, "second commit", secondCommitIsIgnored)
        try await fresh(makeStore, "one card per item", oneCardPerItemID)
        try await fresh(makeStore, "reconciliation", reconciliationUpsertsCards)
        try await fresh(makeStore, "settings", settingsRoundTrip)
        try await fresh(makeStore, "new words", newWordsShownToday)
        try await fresh(makeStore, "load clamps", loadClampsOutOfRangeValues)
        try await fresh(makeStore, "mismatched id", mismatchedSessionIDDoesNotWrite)
        try await fresh(makeStore, "review commit", reviewCommitWritesNoLessonRow)
        try await fresh(makeStore, "placement", placementWritesLessonsCardsAndDay)
        try await fresh(makeStore, "reset", resetClearsLearnerProgress)
    }

    public static func runWriteFailure(_ store: any ProgressStore) async throws {
        try await commitThatThrowsKeepsTheActiveSession(store)
    }

    public static func oneCardPerItemID(_ store: any ProgressStore) async throws {
        try await oneCardPerItem(store)
    }

    public static func resetClearsLearnerProgress(_ store: any ProgressStore) async throws {
        try await resetAll(store)
    }

    private static func fresh(
        _ makeStore: @Sendable () async throws -> any ProgressStore,
        _ scenario: String,
        _ body: (any ProgressStore) async throws -> Void
    ) async throws {
        do {
            try await body(try await makeStore())
        } catch let failure as ProgressStoreContractFailure {
            throw failure
        } catch {
            throw ProgressStoreContractFailure(scenario: scenario, message: String(describing: error))
        }
    }
}

/// A store whose `commit` always throws and does not drop the active session.
public actor CommitRejectingProgressStore: ProgressStore {
    private var active: ActiveSessionSnapshot?
    private let contentVersion: String

    public init(contentVersion: String = "2026.11.0") {
        self.contentVersion = contentVersion
    }

    public func load() async throws -> ProgressSnapshot {
        ProgressSnapshot(
            contentVersion: contentVersion,
            cards: [],
            lessonProgress: [],
            streak: .initial,
            settings: .initial,
            activeSession: active,
            completedSessions: [],
            lastReconciledContentVersion: nil,
            latestObservedDay: nil
        )
    }

    public func saveActiveSession(_ session: ActiveSessionSnapshot) async throws {
        active = session
    }

    public func discardActiveSession() async throws {
        active = nil
    }

    public func commit(_ commit: SessionCommit) async throws {
        throw ProgressStoreContractError.writeFailed
    }

    public func applyReconciliation(
        _ changes: [ReviewCard],
        reconciledContentVersion: String?
    ) async throws {}

    public func applyPlacement(_ commit: PlacementCommit) async throws {
        throw ProgressStoreContractError.writeFailed
    }

    public func updateSettings(_ settings: UserSettings) async throws {}

    public func resetAll() async throws {
        active = nil
    }
}

private let scenarioCard = "one card per item"
private let scenarioReset = "reset"

private func oneCardPerItem(_ store: any ProgressStore) async throws {
    let first = Sample.session("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA1")
    try await store.commit(Sample.commit(
        id: first,
        cards: [Sample.card("e-one", ease: 2.5), Sample.card("e-one", ease: 2.1), Sample.card("e-two")]
    ))
    var loaded = try await store.load()
    try expect(loaded.cards.count == 2, scenarioCard, "a repeated id in one commit is one card")
    try expect(try card("e-one", in: loaded).easeFactor == 2.1, scenarioCard, "the later card is kept")
    try expect(try card("e-two", in: loaded).itemID.rawValue == "e-two", scenarioCard, "the other card is kept")

    let second = Sample.session("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA2")
    try await store.commit(Sample.commit(id: second, cards: [Sample.card("e-one", ease: 1.8)]))
    loaded = try await store.load()
    try expect(loaded.cards.count == 2, scenarioCard, "a later commit replaces the card")
    try expect(try card("e-one", in: loaded).easeFactor == 1.8, scenarioCard, "the replacement ease is stored")
}

private func resetAll(_ store: any ProgressStore) async throws {
    let version = try await store.load().contentVersion
    let kept = Sample.session("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA3")
    let settings = UserSettings(
        dailyGoal: .light,
        showTransliteration: false,
        placementTakenDay: Sample.day
    )
    let keptSettings = UserSettings(
        dailyGoal: .light,
        showTransliteration: false,
        placementTakenDay: nil
    )
    try await store.saveActiveSession(Sample.active(id: kept, answers: 1))
    try await store.updateSettings(settings)
    try await store.commit(Sample.commit(
        id: Sample.session("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA4"),
        cards: [Sample.card("e-one")],
        lesson: Sample.progress("l-greetings-1"),
        streak: Sample.streak(on: Sample.day)
    ))
    try await store.applyReconciliation([], reconciledContentVersion: "2026.12.0")
    try await store.resetAll()
    let cleared = try await store.load()
    let expected = ProgressSnapshot(
        contentVersion: version,
        cards: [],
        lessonProgress: [],
        streak: .initial,
        settings: keptSettings,
        activeSession: nil,
        completedSessions: [],
        lastReconciledContentVersion: nil,
        latestObservedDay: nil
    )
    try expect(
        cleared == expected,
        scenarioReset,
        "reset clears progress and placementTakenDay, and keeps the goal, transliteration, and content version"
    )
    try expect(cleared.settings.placementTakenDay == nil, scenarioReset, "placementTakenDay is cleared")
    try expect(cleared.settings.dailyGoal == .light, scenarioReset, "the daily goal stays")
    try expect(cleared.settings.showTransliteration == false, scenarioReset, "transliteration stays")
}

private func emptyStore(_ store: any ProgressStore) async throws {
    let loaded = try await store.load()
    try expect(loaded.snapshotVersion == ProgressSnapshot.currentVersion, "empty store", "version is current")
    try expect(loaded.cards.isEmpty, "empty store", "no cards")
    try expect(loaded.lessonProgress.isEmpty, "empty store", "no lessons")
    try expect(loaded.streak == .initial, "empty store", "no streak")
    try expect(loaded.settings == .initial, "empty store", "standard settings")
    try expect(loaded.activeSession == nil, "empty store", "no active session")
    try expect(loaded.completedSessions.isEmpty, "empty store", "no completed sessions")
}

private func activeSessionCreatesNoCards(_ store: any ProgressStore) async throws {
    let name = "active session"
    let id = Sample.session("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBB1")
    try await store.saveActiveSession(Sample.active(id: id, answers: 1))
    var loaded = try await store.load()
    try expect(loaded.cards.isEmpty, name, "an answer does not create a card")
    try expect(loaded.lessonProgress.isEmpty, name, "an answer does not finish the lesson")
    try expect(loaded.streak == .initial, name, "an answer does not count a streak day")
    try expect(loaded.activeSession?.lesson?.answers.count == 1, name, "the answer is stored")

    try await store.saveActiveSession(Sample.active(id: id, answers: 2))
    loaded = try await store.load()
    try expect(loaded.activeSession?.sessionID == id, name, "there is still one session")
    try expect(loaded.activeSession?.lesson?.answers.count == 2, name, "the later save replaces it")

    try await store.discardActiveSession()
    loaded = try await store.load()
    try expect(loaded.activeSession == nil, name, "discard removes the session")
    try expect(loaded.cards.isEmpty, name, "discard creates no cards")
}

private func commitWritesTheFinishedLesson(_ store: any ProgressStore) async throws {
    let name = "commit"
    let id = Sample.session("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBB2")
    try await store.saveActiveSession(Sample.active(id: id, answers: 1))
    try await store.commit(Sample.commit(
        id: id,
        cards: [Sample.card("e-salam", created: Sample.day)],
        lesson: Sample.progress("l-greetings-1"),
        streak: Sample.streak(on: Sample.day)
    ))
    let loaded = try await store.load()
    try expect(loaded.activeSession == nil, name, "commit removes the session it finished")
    try expect(loaded.cards.count == 1, name, "the new card is stored")
    try expect(try card("e-salam", in: loaded).createdDay == Sample.day, name, "createdDay is kept")
    try expect(loaded.lessonProgress.count == 1, name, "the lesson row is stored")
    try expect(loaded.streak.lastActiveDay == Sample.day, name, "the streak day is kept")
    try expect(loaded.completedSessions.count == 1, name, "the completed session is stored")
    try expect(loaded.completedSessions.first?.completedDay == Sample.day, name, "completedDay is kept")
}

private func commitLeavesADifferentActiveSession(_ store: any ProgressStore) async throws {
    let name = "commit leaves another session"
    let activeID = Sample.session("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBB3")
    let commitID = Sample.session("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBB4")
    try await store.saveActiveSession(Sample.active(id: activeID, answers: 1))
    try await store.commit(Sample.commit(id: commitID, cards: [Sample.card("e-one")]))
    let loaded = try await store.load()
    try expect(loaded.activeSession?.sessionID == activeID, name, "a different session stays")
    try expect(loaded.cards.count == 1, name, "the commit's card is stored")
}

private func secondCommitIsIgnored(_ store: any ProgressStore) async throws {
    let name = "second commit"
    let id = Sample.session("CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCC1")
    try await store.commit(Sample.commit(
        id: id,
        cards: [Sample.card("e-one", ease: 2.5)],
        day: Sample.day,
        questions: 4,
        correct: 3
    ))
    try await store.commit(Sample.commit(
        id: id,
        cards: [Sample.card("e-one", ease: 1.5), Sample.card("e-two")],
        streak: Sample.streak(on: Sample.next, current: 9),
        day: Sample.next,
        questions: 9,
        correct: 1
    ))
    let loaded = try await store.load()
    try expect(loaded.completedSessions.count == 1, name, "the session is stored once")
    try expect(loaded.completedSessions.first?.completedDay == Sample.day, name, "completedDay stays")
    try expect(loaded.completedSessions.first?.questionCount == 4, name, "the first totals stay")
    try expect(loaded.cards.count == 1, name, "the second commit adds no card")
    try expect(try card("e-one", in: loaded).easeFactor == 2.5, name, "the first card stays")
    try expect(loaded.streak == .initial, name, "the first streak stays")
}

private func reconciliationUpsertsCards(_ store: any ProgressStore) async throws {
    let name = "reconciliation"
    let id = Sample.session("CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCC2")
    try await store.saveActiveSession(Sample.active(id: id, answers: 1))
    try await store.commit(Sample.commit(id: Sample.session("CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCC3"), cards: [Sample.card("e-one")]))
    try await store.applyReconciliation([Sample.card("e-one", state: .paused)])
    var loaded = try await store.load()
    try expect(loaded.cards.count == 1, name, "pause does not add a card")
    try expect(try card("e-one", in: loaded).state == .paused, name, "the card is paused")
    try expect(loaded.activeSession?.sessionID == id, name, "the active session stays")

    try await store.applyReconciliation([Sample.card("e-two")])
    loaded = try await store.load()
    try expect(loaded.cards.count == 2, name, "a new id is added")
    try await store.applyReconciliation([])
    loaded = try await store.load()
    try expect(loaded.cards.count == 2, name, "an empty reconciliation changes nothing")
    try expect(loaded.lastReconciledContentVersion == nil, name, "an empty reconciliation leaves the marker")

    try await store.applyReconciliation([], reconciledContentVersion: "2026.12.0")
    loaded = try await store.load()
    try expect(loaded.cards.count == 2, name, "the marker adds no card")
    try expect(loaded.lastReconciledContentVersion == "2026.12.0", name, "the marker is stored")
    try expect(loaded.activeSession?.sessionID == id, name, "the marker leaves the active session")
    try await store.applyReconciliation([Sample.card("e-one", state: .active)], reconciledContentVersion: "2026.12.0")
    loaded = try await store.load()
    try expect(try card("e-one", in: loaded).state == .active, name, "a card can be restored")
    try expect(loaded.lastReconciledContentVersion == "2026.12.0", name, "the same marker stays")
}

private func settingsRoundTrip(_ store: any ProgressStore) async throws {
    let placement = Sample.day
    let settings = UserSettings(dailyGoal: .serious, showTransliteration: false, placementTakenDay: placement)
    try await store.updateSettings(settings)
    let loaded = try await store.load()
    try expect(loaded.settings == settings, "settings", "settings are stored")
    try expect(loaded.cards.isEmpty, "settings", "settings do not create cards")
}

private func newWordsShownToday(_ store: any ProgressStore) async throws {
    let name = "new words"
    try await store.commit(Sample.commit(
        id: Sample.session("DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDD1"),
        cards: [
            Sample.card("e-today", created: Sample.next),
            Sample.card("e-old", created: Sample.day),
            Sample.card("e-place", created: Sample.next, source: .placement),
            Sample.card("e-paused", created: Sample.next, state: .paused),
        ]
    ))
    let loaded = try await store.load()
    let progress = pathProgress(loaded, on: Sample.next)
    try expect(progress.newItemsShownToday == 2, name, "today's lesson cards count, placement cards do not")
    try expect(newItemsShown(on: Sample.next, in: loaded.cards) == 2, name, "the same count comes from the cards")
    try expect(try card("e-place", in: loaded).source == .placement, name, "the placement card is still stored")
}

private func loadClampsOutOfRangeValues(_ store: any ProgressStore) async throws {
    let name = "load clamps"
    try await store.commit(Sample.commit(
        id: Sample.session("DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDD2"),
        cards: [
            Sample.card("e-nan", ease: .nan),
            Sample.card("e-neg", ease: -2),
            Sample.card("e-low", ease: 1),
            Sample.card("e-inf", ease: .infinity),
            Sample.card("e-gap", ease: 2.5, interval: -3),
            Sample.card("e-ok", ease: 2.5, interval: 6),
        ],
        streak: Sample.streak(on: Sample.day, current: 3, freezes: 5)
    ))
    let loaded = try await store.load()
    try expect(try card("e-nan", in: loaded).easeFactor == ReviewCard.initialEaseFactor, name, "NaN ease resets")
    try expect(try card("e-neg", in: loaded).easeFactor == ReviewCard.initialEaseFactor, name, "negative ease resets")
    try expect(try card("e-low", in: loaded).easeFactor == ReviewCard.minimumEaseFactor, name, "ease below 1.3 clamps")
    try expect(try card("e-inf", in: loaded).easeFactor == ReviewCard.initialEaseFactor, name, "infinite ease resets")
    try expect(try card("e-gap", in: loaded).intervalDays == 0, name, "a negative interval resets")
    try expect(try card("e-ok", in: loaded).easeFactor == 2.5, name, "a valid ease stays")
    try expect(try card("e-ok", in: loaded).intervalDays == 6, name, "a valid interval stays")
    try expect(loaded.streak.freezes == 2, name, "freezes above 2 clamp")
    try expect(loaded.streak.current == 3, name, "the streak count stays")
    try expect(try card("e-low", in: loaded).createdDay == Sample.day, name, "clamping keeps createdDay")
}

private func mismatchedSessionIDDoesNotWrite(_ store: any ProgressStore) async throws {
    let name = "mismatched id"
    let commit = SessionCommit(
        sessionID: Sample.session("EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEE1"),
        cards: [Sample.card("e-one")],
        lessonProgress: nil,
        streak: Sample.streak(on: Sample.day),
        completed: CompletedSession(
            sessionID: Sample.session("EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEE2"),
            kind: .lesson,
            lessonID: nil,
            completedDay: Sample.day,
            questionCount: 1,
            firstTryCorrect: 1
        )
    )
    var threw = false
    do {
        try await store.commit(commit)
    } catch let error as ProgressStoreError {
        threw = error == .mismatchedSessionID
    }
    try expect(threw, name, "a commit with two ids throws")
    let loaded = try await store.load()
    try expect(loaded.cards.isEmpty, name, "the failed commit writes no card")
    try expect(loaded.completedSessions.isEmpty, name, "the failed commit writes no session")
}

private func reviewCommitWritesNoLessonRow(_ store: any ProgressStore) async throws {
    let name = "review commit"
    try await store.commit(Sample.commit(
        id: Sample.session("EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEE3"),
        cards: [Sample.card("e-one", ease: 2.2, interval: 6)],
        streak: Sample.streak(on: Sample.day),
        kind: .review
    ))
    let loaded = try await store.load()
    try expect(loaded.lessonProgress.isEmpty, name, "a review commit adds no lesson row")
    try expect(loaded.cards.count == 1, name, "the reviewed card is stored")
    try expect(loaded.completedSessions.first?.kind == .review, name, "the completed row is a review")
    try expect(loaded.streak.lastActiveDay == Sample.day, name, "the streak is stored")
}

private func placementWritesLessonsCardsAndDay(_ store: any ProgressStore) async throws {
    let name = "placement"
    let kept = Sample.session("FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFF1")
    let active = Sample.active(id: Sample.session("FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFF2"), answers: 1)
    try await store.updateSettings(UserSettings(
        dailyGoal: .light,
        showTransliteration: false,
        placementTakenDay: nil
    ))
    try await store.saveActiveSession(active)
    try await store.commit(Sample.commit(
        id: kept,
        cards: [Sample.card("e-keep")],
        lesson: Sample.progress("l-old"),
        streak: Sample.streak(on: Sample.day)
    ))
    let day = Sample.next
    try await store.applyPlacement(PlacementCommit(
        lessonProgress: [
            LessonProgress(
                lessonID: Sample.lesson("l-greetings-1"),
                source: .placement,
                firstCompletedDay: day,
                bestScorePercent: 80
            ),
        ],
        cards: [Sample.card("e-place", created: day, source: .placement)],
        placementTakenDay: day
    ))
    let loaded = try await store.load()
    try expect(loaded.lessonProgress.count == 2, name, "the placement lesson is stored with the old one")
    try expect(
        loaded.lessonProgress.contains { $0.lessonID.rawValue == "l-greetings-1" && $0.source == .placement },
        name,
        "the new lesson is a placement row"
    )
    try expect(loaded.cards.count == 2, name, "the placement card is stored with the old one")
    try expect(try card("e-place", in: loaded).source == .placement, name, "the new card is a placement card")
    try expect(loaded.settings.placementTakenDay == day, name, "placementTakenDay is stored")
    try expect(loaded.settings.dailyGoal == .light, name, "the daily goal stays")
    try expect(loaded.settings.showTransliteration == false, name, "transliteration stays")
    try expect(loaded.streak.lastActiveDay == Sample.day, name, "the streak stays")
    try expect(loaded.activeSession == active, name, "the active session stays")
}

private func commitThatThrowsKeepsTheActiveSession(_ store: any ProgressStore) async throws {
    let name = "commit throws"
    let id = Sample.session("EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEE4")
    let session = Sample.active(id: id, answers: 1)
    try await store.saveActiveSession(session)
    var threw = false
    do {
        try await store.commit(Sample.commit(id: id, cards: [Sample.card("e-one")]))
    } catch {
        threw = true
    }
    try expect(threw, name, "commit throws")
    let loaded = try await store.load()
    try expect(loaded.activeSession == session, name, "the active session is still there")
    try expect(loaded.cards.isEmpty, name, "a failed commit creates no card")
}

private func expect(_ condition: Bool, _ scenario: String, _ message: String) throws {
    if !condition {
        throw ProgressStoreContractFailure(scenario: scenario, message: message)
    }
}

private func card(_ raw: String, in snapshot: ProgressSnapshot) throws -> ReviewCard {
    guard let found = snapshot.cards.first(where: { $0.itemID.rawValue == raw }) else {
        throw ProgressStoreContractFailure(scenario: "card", message: "missing \(raw)")
    }
    return found
}

private enum Sample {
    static let day = LocalDay(year: 2026, month: 11, day: 1)
    static let next = LocalDay(year: 2026, month: 11, day: 2)

    static func session(_ raw: String) -> UUID {
        guard let id = UUID(uuidString: raw) else {
            preconditionFailure("UUID \(raw) is not valid")
        }
        return id
    }

    static func item(_ raw: String) -> ItemID {
        guard let id = ItemID(rawValue: raw) else {
            preconditionFailure("Item id \(raw) is not valid")
        }
        return id
    }

    static func lesson(_ raw: String) -> LessonID {
        guard let id = LessonID(rawValue: raw) else {
            preconditionFailure("Lesson id \(raw) is not valid")
        }
        return id
    }

    static func card(
        _ raw: String,
        ease: Double = ReviewCard.initialEaseFactor,
        interval: Int = 0,
        created: LocalDay? = nil,
        source: ReviewCardSource = .lesson,
        state: ReviewCardState = .active
    ) -> ReviewCard {
        let createdDay = created ?? day
        return ReviewCard(
            itemID: item(raw),
            easeFactor: ease,
            intervalDays: interval,
            repetitions: 0,
            lapses: 0,
            dueDay: createdDay,
            lastReviewedDay: nil,
            createdDay: createdDay,
            state: state,
            source: source
        )
    }

    static func progress(_ raw: String) -> LessonProgress {
        LessonProgress(
            lessonID: lesson(raw),
            source: .completed,
            firstCompletedDay: day,
            bestScorePercent: 80
        )
    }

    static func streak(on day: LocalDay, current: Int = 1, freezes: Int = 0) -> StreakState {
        StreakState(
            current: current,
            longest: current,
            lastActiveDay: day,
            freezes: freezes,
            daysTowardNextFreeze: 1,
            freezeUsedDays: []
        )
    }

    static func commit(
        id: UUID,
        cards: [ReviewCard],
        lesson: LessonProgress? = nil,
        streak: StreakState = .initial,
        day completedDay: LocalDay? = nil,
        kind: SessionKind = .lesson,
        questions: Int = 1,
        correct: Int = 1
    ) -> SessionCommit {
        let completed = completedDay ?? day
        return SessionCommit(
            sessionID: id,
            cards: cards,
            lessonProgress: lesson,
            streak: streak,
            completed: CompletedSession(
                sessionID: id,
                kind: kind,
                lessonID: lesson?.lessonID,
                completedDay: completed,
                questionCount: questions,
                firstTryCorrect: correct
            )
        )
    }

    static func active(id: UUID, answers: Int) -> ActiveSessionSnapshot {
        ActiveSessionSnapshot(
            sessionID: id,
            kind: .lesson,
            lessonID: lesson("l-greetings-1"),
            startedDay: day,
            lastAnswerDay: answers > 0 ? day : nil,
            contentVersion: "2026.11.0",
            lesson: lessonSession(answers: answers)
        )
    }

    static func lessonSession(answers: Int) -> LessonSession {
        let target = item("e-salam")
        let task = SessionTask(
            payload: .choice(QuizTask(
                kind: .meaningPashtoToEnglish,
                targetID: target,
                prompt: "hello",
                usage: nil,
                options: [QuizOption(itemID: target, text: "hello")]
            )),
            isRepeat: false
        )
        let answer = SessionAnswer(task: task, answer: .choice(target), result: .correct)
        return LessonSession(
            lessonID: lesson("l-greetings-1"),
            tasks: [],
            answers: Array(repeating: answer, count: answers)
        )
    }
}
