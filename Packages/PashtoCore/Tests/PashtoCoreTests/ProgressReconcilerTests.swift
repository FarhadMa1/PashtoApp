import Foundation
import Testing
import PashtoCore
import PashtoCoreTesting

struct ProgressReconcilerTests {
    private let today = LocalDay(year: 2026, month: 11, day: 2)

    @Test func contentMigrationRoundTripMatchesTheGoldenFiles() throws {
        let before: ProgressSnapshot = try fixture("reconcile/snapshot-a.json")
        let contentA: ContentBundle = try fixture("reconcile/content-a.json")
        let contentB: ContentBundle = try fixture("reconcile/content-b.json")
        let expectedB: ProgressSnapshot = try fixture("reconcile/snapshot-after-b.json")
        let expectedBack: ProgressSnapshot = try fixture("reconcile/snapshot-back-to-a.json")

        let keptBefore = try card("e-kept", in: contentA)
        let keptAfter = try card("e-kept", in: contentB)
        #expect(keptBefore.translit != keptAfter.translit)
        #expect(keptBefore.pashto == keptAfter.pashto)

        let sameContent = ProgressReconciler.reconcile(before, with: contentA, on: today)
        #expect(sameContent.cardChanges.isEmpty)
        #expect(sameContent.snapshot.cards == before.cards)
        #expect(sameContent.snapshot.lessonProgress == before.lessonProgress)
        #expect(sameContent.snapshot.lastReconciledContentVersion == "2026.11.0-a")

        let migrated = ProgressReconciler.reconcile(before, with: contentB, on: today)
        #expect(migrated.snapshot == expectedB)
        #expect(card("e-kept", in: migrated.snapshot) == card("e-kept", in: before))
        #expect(card("e-retired", in: migrated.snapshot).state == .paused)
        #expect(card("e-retired", in: migrated.snapshot).dueDay == card("e-retired", in: before).dueDay)
        #expect(card("e-missing", in: migrated.snapshot).state == .paused)
        #expect(card("e-old", in: migrated.snapshot).state == .paused)
        #expect(migrated.snapshot.cards.map(\.itemID.rawValue).contains("e-new"))
        #expect(!migrated.snapshot.cards.map(\.itemID.rawValue).contains("e-future"))
        #expect(!migrated.snapshot.cards.map(\.itemID.rawValue).contains("e-extra"))
        #expect(!migrated.snapshot.cards.map(\.itemID.rawValue).contains("e-sound"))
        #expect(migrated.snapshot.lessonProgress.map(\.lessonID.rawValue) == ["l-done", "l-old"])
        #expect(migrated.snapshot.streak == before.streak)
        #expect(migrated.snapshot.completedSessions == before.completedSessions)
        #expect(migrated.snapshot.latestObservedDay == before.latestObservedDay)
        #expect(migrated.snapshot.contentVersion == before.contentVersion)

        let again = ProgressReconciler.reconcile(migrated.snapshot, with: contentB, on: today)
        #expect(again.snapshot == migrated.snapshot)
        #expect(again.cardChanges.isEmpty)

        let restored = ProgressReconciler.reconcile(migrated.snapshot, with: contentA, on: today)
        #expect(restored.snapshot == expectedBack)
        #expect(card("e-retired", in: restored.snapshot) == card("e-retired", in: before))
        #expect(card("e-missing", in: restored.snapshot) == card("e-missing", in: before))
        #expect(card("e-old", in: restored.snapshot) == card("e-old", in: before))
        #expect(card("e-kept", in: restored.snapshot) == card("e-kept", in: before))
        #expect(card("e-new", in: restored.snapshot).state == .paused)
        #expect(card("e-new", in: restored.snapshot).dueDay == today)
        #expect(restored.snapshot.cards.count == migrated.snapshot.cards.count)

        let restoredAgain = ProgressReconciler.reconcile(restored.snapshot, with: contentA, on: today)
        #expect(restoredAgain.snapshot == restored.snapshot)
        #expect(restoredAgain.cardChanges.isEmpty)
    }

    @Test func newCardsInFinishedLessonsAreSpreadFromToday() throws {
        let finished = LocalDay(year: 2026, month: 10, day: 1)
        let ids = ["e-zulu"] + (1...9).map { String(format: "e-a%02d", $0) } + ["e-mid"]
        let items = ids.map { word($0) }
        let lesson = Lesson(
            id: lesson("l-done"),
            title: "Done",
            items: ids.map { LessonItemRef(item: item($0), role: .introduce) }
        )
        let content = bundle(version: "2026.11.0", items: items, lessons: [lesson])
        let snapshot = ProgressSnapshot(
            contentVersion: "2026.10.0",
            cards: [],
            lessonProgress: [
                LessonProgress(
                    lessonID: lesson.id,
                    source: .completed,
                    firstCompletedDay: finished,
                    bestScorePercent: 100
                ),
            ],
            streak: .initial,
            settings: .initial,
            activeSession: nil,
            completedSessions: [],
            lastReconciledContentVersion: nil,
            latestObservedDay: nil
        )

        let reconciled = ProgressReconciler.reconcile(snapshot, with: content, on: today)
        #expect(reconciled.snapshot.cards.count == ids.count)
        #expect(card("e-zulu", in: reconciled.snapshot).dueDay == today)
        #expect(card("e-mid", in: reconciled.snapshot).dueDay == today.adding(days: 1))
        #expect(card("e-a01", in: reconciled.snapshot).dueDay == today)
        #expect(reconciled.snapshot.cards.allSatisfy { $0.createdDay == finished })
        #expect(reconciled.snapshot.cards.allSatisfy { $0.source == .lesson })
        #expect(newItemsShown(on: today, in: reconciled.snapshot.cards) == 0)

        let second = ProgressReconciler.reconcile(reconciled.snapshot, with: content, on: today.adding(days: 5))
        #expect(second.snapshot.cards == reconciled.snapshot.cards)
        #expect(second.cardChanges.isEmpty)
        #expect(card("e-mid", in: second.snapshot).dueDay == today.adding(days: 1))
    }

    @Test func aPlacementSkippedLessonGetsCatchUpCards() throws {
        let finished = today.adding(days: -3)
        let content = bundle(
            version: "2026.11.0",
            items: [word("e-added")],
            lessons: [
                Lesson(
                    id: lesson("l-skip"),
                    title: "Skipped",
                    items: [LessonItemRef(item: item("e-added"), role: .introduce)],
                    letters: [item("e-alif")]
                ),
            ]
        )
        let withLetter = ContentBundle(
            contentVersion: content.contentVersion,
            variant: content.variant,
            romanization: content.romanization,
            items: content.items + [word("e-alif")],
            units: content.units,
            nonDistractorGroups: []
        )
        let snapshot = ProgressSnapshot(
            contentVersion: "2026.10.0",
            cards: [],
            lessonProgress: [
                LessonProgress(
                    lessonID: lesson("l-skip"),
                    source: .placement,
                    firstCompletedDay: finished,
                    bestScorePercent: 80
                ),
            ],
            streak: .initial,
            settings: .initial,
            activeSession: nil,
            completedSessions: [],
            lastReconciledContentVersion: nil,
            latestObservedDay: nil
        )
        let reconciled = ProgressReconciler.reconcile(snapshot, with: withLetter, on: today)
        #expect(card("e-added", in: reconciled.snapshot).source == .lesson)
        #expect(card("e-added", in: reconciled.snapshot).createdDay == finished)
        #expect(card("e-added", in: reconciled.snapshot).dueDay == today)
        #expect(card("e-alif", in: reconciled.snapshot).dueDay == today)
        #expect(reconciled.snapshot.lessonProgress.count == 1)
    }

    @Test func aFilteredItemIsPausedAndComesBackWithTheSameDueDay() throws {
        let due = LocalDay(year: 2026, month: 12, day: 1)
        let visible = word("e-shown", status: .verified)
        let hidden = word("e-draft", status: .draft)
        let lesson = Lesson(
            id: lesson("l-done"),
            title: "Done",
            items: [
                LessonItemRef(item: visible.id, role: .introduce),
                LessonItemRef(item: hidden.id, role: .introduce),
            ]
        )
        let full = bundle(version: "2026.11.0", items: [visible, hidden], lessons: [lesson])
        let storedCard = ReviewCard(
            itemID: hidden.id,
            easeFactor: 2.2,
            intervalDays: 6,
            repetitions: 2,
            lapses: 1,
            dueDay: due,
            lastReviewedDay: today,
            createdDay: today.adding(days: -4),
            state: .active,
            source: .lesson
        )
        let snapshot = ProgressSnapshot(
            contentVersion: "2026.11.0",
            cards: [storedCard, ReviewCard.introduced(itemID: visible.id, on: today.adding(days: -4))],
            lessonProgress: [
                LessonProgress(
                    lessonID: lesson.id,
                    source: .completed,
                    firstCompletedDay: today.adding(days: -4),
                    bestScorePercent: 90
                ),
            ],
            streak: .initial,
            settings: .initial,
            activeSession: nil,
            completedSessions: [],
            lastReconciledContentVersion: nil,
            latestObservedDay: nil
        )

        let filtered = ProgressReconciler.reconcile(snapshot, with: ContentFilter.devBuild(full), on: today)
        let paused = card("e-draft", in: filtered.snapshot)
        #expect(paused.state == .paused)
        #expect(paused.dueDay == due)
        #expect(paused.easeFactor == 2.2)
        #expect(paused.lapses == 1)
        #expect(card("e-shown", in: filtered.snapshot).state == .active)

        let restored = ProgressReconciler.reconcile(filtered.snapshot, with: full, on: today)
        #expect(card("e-draft", in: restored.snapshot) == storedCard)
    }

    @Test func aCrashJustBeforeMidnightCountsOnTheEarlierDay() async throws {
        let dayN = today
        let dayAfter = today.adding(days: 1)
        let active = finishedSession(started: dayN, lastAnswer: dayN, version: "2026.11.0")
        let content = greetingsBundle(version: "2026.11.0")
        let store = InMemoryProgressStore(contentVersion: "2026.11.0")
        try await store.saveActiveSession(active)

        let action = ProgressReconciler.sessionAction(
            for: active,
            in: try await store.load(),
            content: content,
            on: dayAfter
        )
        guard case .commit(let commit) = action else {
            Issue.record("a finished lesson is committed")
            return
        }
        #expect(commit.completed.completedDay == dayN)
        #expect(commit.streak.lastActiveDay == dayN)
        #expect(commit.lessonProgress?.firstCompletedDay == dayN)
        #expect(commit.cards.first?.createdDay == dayN)
        #expect(commit.cards.first?.dueDay == dayN.adding(days: 1))
        #expect(commit.cards.first?.lastReviewedDay == dayN)

        let loaded = try await ProgressReconciler.run(store: store, content: content, on: dayAfter)
        #expect(loaded.activeSession == nil)
        #expect(loaded.completedSessions.map(\.completedDay) == [dayN])
        #expect(loaded.streak.lastActiveDay == dayN)
        #expect(loaded.streak.current == 1)
        #expect(loaded.lessonProgress.first?.firstCompletedDay == dayN)
        #expect(loaded.cards.first?.createdDay == dayN)
        #expect(loaded.cards.first?.dueDay == dayN.adding(days: 1))
        #expect(loaded.lastReconciledContentVersion == "2026.11.0")

        let again = try await ProgressReconciler.run(store: store, content: content, on: dayAfter)
        #expect(again == loaded)
        #expect(again.completedSessions.count == 1)
        #expect(again.streak.current == 1)
    }

    @Test func aFinishedSessionCommitsAfterTheResumeWindowAndAContentChange() async throws {
        let answered = today.adding(days: -5)
        let active = finishedSession(started: answered, lastAnswer: answered, version: "1999.1.0")
        let content = greetingsBundle(version: "2026.11.0")
        let store = InMemoryProgressStore(contentVersion: "2026.11.0")
        try await store.saveActiveSession(active)

        let loaded = try await ProgressReconciler.run(store: store, content: content, on: today)
        #expect(loaded.activeSession == nil)
        #expect(loaded.completedSessions.map(\.completedDay) == [answered])
        #expect(loaded.streak.lastActiveDay == answered)
        #expect(loaded.cards.first?.createdDay == answered)
        #expect(loaded.cards.first?.dueDay == answered.adding(days: 1))
        #expect(loaded.lessonProgress.first?.firstCompletedDay == answered)
    }

    @Test func aRemovedLessonStillCommitsTheDayWithoutCards() async throws {
        let answered = today.adding(days: -2)
        let active = finishedSession(started: answered, lastAnswer: answered, version: "2026.11.0")
        let content = bundle(version: "2026.12.0", items: [word("e-other")], lessons: [
            Lesson(id: lesson("l-other"), title: "Other", items: [LessonItemRef(item: item("e-other"), role: .introduce)]),
        ])
        let store = InMemoryProgressStore(contentVersion: "2026.12.0")
        try await store.saveActiveSession(active)
        let loaded = try await ProgressReconciler.run(store: store, content: content, on: today)
        #expect(loaded.activeSession == nil)
        #expect(loaded.cards.isEmpty)
        #expect(loaded.lessonProgress.map(\.lessonID) == [lesson("l-greetings-1")])
        #expect(loaded.lessonProgress.first?.firstCompletedDay == answered)
        #expect(loaded.streak.lastActiveDay == answered)
        #expect(loaded.completedSessions.first?.completedDay == answered)
    }

    @Test func anUnfinishedLessonKeepsTheResumeWindow() async throws {
        let content = greetingsBundle(version: "2026.11.0")
        let sameDay = try await runUnfinished(started: today, content: content, on: today)
        #expect(sameDay.activeSession != nil)
        #expect(sameDay.cards.isEmpty)
        #expect(sameDay.streak == .initial)

        let nextDay = try await runUnfinished(started: today.adding(days: -1), content: content, on: today)
        #expect(nextDay.activeSession != nil)
        #expect(nextDay.cards.isEmpty)

        let tooOld = try await runUnfinished(started: today.adding(days: -2), content: content, on: today)
        #expect(tooOld.activeSession == nil)
        #expect(tooOld.cards.isEmpty)
        #expect(tooOld.completedSessions.isEmpty)
        #expect(tooOld.streak == .initial)

        let otherVersion = greetingsBundle(version: "2026.12.0")
        let stale = try await runUnfinished(started: today, content: otherVersion, on: today)
        #expect(stale.activeSession == nil)
        #expect(stale.cards.isEmpty)

        let clockBackOneDay = try await runUnfinished(started: today.adding(days: 1), content: content, on: today)
        #expect(clockBackOneDay.activeSession != nil)
        #expect(clockBackOneDay.cards.isEmpty)
        #expect(clockBackOneDay.completedSessions.isEmpty)
        #expect(clockBackOneDay.streak == .initial)

        let clockBackTwoDays = try await runUnfinished(started: today.adding(days: 2), content: content, on: today)
        #expect(clockBackTwoDays.activeSession == nil)
        #expect(clockBackTwoDays.cards.isEmpty)
        #expect(clockBackTwoDays.completedSessions.isEmpty)
        #expect(clockBackTwoDays.streak == .initial)
    }

    @Test func anUnfinishedReviewStartsOver() async throws {
        let review = ActiveSessionSnapshot(
            sessionID: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            kind: .review,
            lessonID: nil,
            startedDay: today,
            lastAnswerDay: today,
            contentVersion: "2026.11.0",
            lesson: nil
        )
        let store = InMemoryProgressStore(contentVersion: "2026.11.0")
        try await store.saveActiveSession(review)
        let loaded = try await ProgressReconciler.run(
            store: store,
            content: greetingsBundle(version: "2026.11.0"),
            on: today
        )
        #expect(loaded.activeSession == nil)
        #expect(loaded.cards.isEmpty)
        #expect(loaded.streak == .initial)
    }

    @Test func aNewerPayloadIsLeftStored() async throws {
        let finished = ActiveSessionSnapshot(
            sessionID: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            kind: .lesson,
            lessonID: lesson("l-greetings-1"),
            startedDay: today.adding(days: -8),
            lastAnswerDay: today.adding(days: -8),
            contentVersion: "2099.1.0",
            payloadVersion: ActiveSessionSnapshot.currentPayloadVersion + 1,
            lesson: LessonSession(lessonID: lesson("l-greetings-1"), tasks: [], answers: [])
        )
        let review = ActiveSessionSnapshot(
            sessionID: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            kind: .review,
            lessonID: nil,
            startedDay: today,
            lastAnswerDay: nil,
            contentVersion: "2026.11.0",
            payloadVersion: ActiveSessionSnapshot.currentPayloadVersion + 1,
            lesson: nil
        )
        let content = greetingsBundle(version: "2026.11.0")
        for session in [finished, review] {
            let store = InMemoryProgressStore(contentVersion: "2026.11.0")
            try await store.saveActiveSession(session)
            let loaded = try await ProgressReconciler.run(store: store, content: content, on: today)
            #expect(loaded.activeSession == session)
            #expect(loaded.cards.isEmpty)
            #expect(loaded.completedSessions.isEmpty)
            #expect(loaded.streak == .initial)
        }
    }

    @Test func aFailedCommitLeavesTheFinishedSession() async throws {
        let store = CommitRejectingProgressStore()
        let active = finishedSession(started: today, lastAnswer: today, version: "2026.11.0")
        try await store.saveActiveSession(active)
        await #expect(throws: ProgressStoreContractError.self) {
            try await ProgressReconciler.run(
                store: store,
                content: greetingsBundle(version: "2026.11.0"),
                on: today.adding(days: 1)
            )
        }
        let loaded = try await store.load()
        #expect(loaded.activeSession == active)
        #expect(loaded.cards.isEmpty)
    }

    @Test func aSessionThatWasAlreadyCommittedIsNotCountedAgain() async throws {
        let dayN = today
        let later = today.adding(days: 2)
        let active = finishedSession(started: dayN, lastAnswer: dayN, version: "2026.11.0")
        let content = greetingsBundle(version: "2026.11.0")
        let store = InMemoryProgressStore(contentVersion: "2026.11.0")
        try await store.saveActiveSession(active)
        let first = try await ProgressReconciler.run(store: store, content: content, on: dayN)
        let leftover = finishedSession(started: dayN, lastAnswer: later, version: "2026.11.0")
        try await store.saveActiveSession(
            ActiveSessionSnapshot(
                sessionID: active.sessionID,
                kind: leftover.kind,
                lessonID: leftover.lessonID,
                startedDay: leftover.startedDay,
                lastAnswerDay: later,
                contentVersion: leftover.contentVersion,
                lesson: leftover.lesson
            )
        )
        let second = try await ProgressReconciler.run(store: store, content: content, on: later.adding(days: 1))
        #expect(second.activeSession == nil)
        #expect(second.completedSessions.count == 1)
        #expect(second.completedSessions.first?.completedDay == dayN)
        #expect(second.streak == first.streak)
        #expect(second.streak.lastActiveDay == dayN)
    }

    @Test func runningTwiceOnAnEmptyStoreStoresOnlyTheMarker() async throws {
        let store = InMemoryProgressStore(contentVersion: "stored")
        let content = greetingsBundle(version: "bundle")
        let first = try await ProgressReconciler.run(store: store, content: content, on: today)
        let second = try await ProgressReconciler.run(store: store, content: content, on: today)
        #expect(first == second)
        #expect(first.contentVersion == "stored")
        #expect(first.lastReconciledContentVersion == "bundle")
        #expect(first.cards.isEmpty)
        #expect(first.activeSession == nil)
    }

    private func runUnfinished(
        started: LocalDay,
        content: ContentBundle,
        on today: LocalDay
    ) async throws -> ProgressSnapshot {
        let session = ActiveSessionSnapshot(
            sessionID: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            kind: .lesson,
            lessonID: lesson("l-greetings-1"),
            startedDay: started,
            lastAnswerDay: started,
            contentVersion: "2026.11.0",
            lesson: LessonSession(
                lessonID: lesson("l-greetings-1"),
                tasks: [choice("e-salam")]
            )
        )
        let store = InMemoryProgressStore(contentVersion: content.contentVersion)
        try await store.saveActiveSession(session)
        return try await ProgressReconciler.run(store: store, content: content, on: today)
    }

    private func greetingsBundle(version: String) -> ContentBundle {
        bundle(
            version: version,
            items: [word("e-salam")],
            lessons: [
                Lesson(
                    id: lesson("l-greetings-1"),
                    title: "Hello",
                    items: [
                        LessonItemRef(item: item("e-salam"), role: .introduce),
                        LessonItemRef(item: item("e-sound"), role: .soundExample, sound: "s"),
                    ]
                ),
            ]
        )
    }

    private func finishedSession(
        started: LocalDay,
        lastAnswer: LocalDay?,
        version: String
    ) -> ActiveSessionSnapshot {
        ActiveSessionSnapshot(
            sessionID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            kind: .lesson,
            lessonID: lesson("l-greetings-1"),
            startedDay: started,
            lastAnswerDay: lastAnswer,
            contentVersion: version,
            lesson: LessonSession(
                lessonID: lesson("l-greetings-1"),
                tasks: [],
                answers: [correct("e-salam")]
            )
        )
    }

    private func bundle(version: String, items: [ContentItem], lessons: [Lesson]) -> ContentBundle {
        ContentBundle(
            contentVersion: version,
            variant: ContentBundle.kabulVariant,
            romanization: Romanization(
                table: [
                    Romanization.Entry(
                        letter: "a",
                        translit: "a",
                        ascii: "a",
                        pronunciation: "a",
                        description: "test"
                    ),
                ],
                difficultCharacters: [],
                unstressedWords: []
            ),
            items: items,
            units: [
                CourseUnit(id: unit("u-course"), track: "main", title: "Course", lessons: lessons),
            ],
            nonDistractorGroups: []
        )
    }

    private func word(_ raw: String, status: VerificationStatus = .verified) -> ContentItem {
        ContentItem(
            id: item(raw),
            kind: .word,
            pashto: raw,
            translit: raw,
            pronunciation: raw,
            en: raw,
            verification: Verification(
                status: status,
                checkedBy: status == .verified ? "test" : nil,
                checkedOn: status == .verified ? "2026-10-01" : nil
            )
        )
    }

    private func correct(_ raw: String) -> SessionAnswer {
        let target = item(raw)
        let task = SessionTask(
            payload: .choice(QuizTask(
                kind: .meaningPashtoToEnglish,
                targetID: target,
                prompt: "hello",
                usage: nil,
                options: [QuizOption(itemID: target, text: "hello")]
            ))
        )
        return SessionAnswer(task: task, answer: .choice(target), result: .correct)
    }

    private func choice(_ raw: String) -> SessionTask {
        let target = item(raw)
        return SessionTask(
            payload: .choice(QuizTask(
                kind: .meaningPashtoToEnglish,
                targetID: target,
                prompt: "hello",
                usage: nil,
                options: [QuizOption(itemID: target, text: "hello")]
            ))
        )
    }

    private func item(_ raw: String) -> ItemID {
        guard let id = ItemID(rawValue: raw) else {
            preconditionFailure("Item id \(raw) is not valid")
        }
        return id
    }

    private func lesson(_ raw: String) -> LessonID {
        guard let id = LessonID(rawValue: raw) else {
            preconditionFailure("Lesson id \(raw) is not valid")
        }
        return id
    }

    private func unit(_ raw: String) -> UnitID {
        guard let id = UnitID(rawValue: raw) else {
            preconditionFailure("Unit id \(raw) is not valid")
        }
        return id
    }
}

private func card(_ raw: String, in bundle: ContentBundle) throws -> ContentItem {
    let id = try #require(ItemID(rawValue: raw))
    return try #require(bundle.items.first { $0.id == id })
}

private func card(_ raw: String, in snapshot: ProgressSnapshot) -> ReviewCard {
    let id = ItemID(rawValue: raw)
    return snapshot.cards.first { $0.itemID == id }!
}

private func fixture<T: Decodable>(_ name: String) throws -> T {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(name)
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
}
