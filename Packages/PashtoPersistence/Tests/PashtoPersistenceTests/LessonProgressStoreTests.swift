import Foundation
import PashtoCore
import SwiftData
import Testing

@testable import PashtoPersistence

/// The lesson flow against `SwiftDataProgressStore`, which the macOS job runs.
@MainActor
struct LessonProgressStoreTests {
    private let day = LocalDay(year: 2026, month: 11, day: 2)
    private let version = "2026.11.0"
    private let salamSession = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA1")!
    private let bookSession = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBB1")!

    @Test func savedAnswersResumeFromTheFileAndAFinishSurvivesReopening() async throws {
        let url = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let bundle = course(version: version)

        try await withStore(at: url, version: version) { store in
            try await storeFinishedBook(to: store, in: bundle)
            let attempt = LessonAttempt(
                sessionID: salamSession,
                lessonID: mustLesson("l-salam"),
                startedDay: day,
                contentVersion: version
            )
            try await attempt.saveActive(openSalam(), answeredOn: nil, to: store)
        }

        let opened = try await readStore(at: url, contentVersion: "ignored")
        #expect(opened.lessonProgress.map(\.lessonID) == [mustLesson("l-book")])
        #expect(opened.cards.map(\.itemID) == [mustItem("e-book")])
        #expect(opened.activeSession?.sessionID == salamSession)
        #expect(opened.activeSession?.lesson?.answers.isEmpty == true)
        #expect(opened.streak.current == 1)

        try await withStore(at: url, version: version) { store in
            let reconciled = try await ProgressReconciler.run(store: store, content: bundle, on: day)
            #expect(reconciled.activeSession?.sessionID == salamSession)
            let lesson = OpenLesson()
            var rng = SeededGenerator(seed: 1)
            lesson.startLesson(
                lessonID: mustLesson("l-salam"),
                in: bundle,
                progress: reconciled,
                releasedUnitIDs: [mustUnit("u-home")],
                showsPronunciation: true,
                voiceOver: false,
                on: day,
                using: &rng
            )
            var session = try #require(lesson.session)
            #expect(lesson.attempt?.sessionID == salamSession)
            #expect(session.answers.isEmpty)
            try submit(&session, correct: true)
            lesson.saveAnswer(session, on: day, to: store)
            await lesson.waitUntilSavesFinish()
        }

        let halfway = try await readStore(at: url, contentVersion: version)
        #expect(halfway.lessonProgress.map(\.lessonID) == [mustLesson("l-book")])
        #expect(halfway.cards.map(\.itemID) == [mustItem("e-book")])
        #expect(halfway.activeSession?.lesson?.answers.count == 1)
        #expect(halfway.activeSession?.lastAnswerDay == day)
        #expect(halfway.streak.current == 1)

        try await withStore(at: url, version: version) { store in
            let progress = try await store.load()
            let lesson = OpenLesson()
            var rng = SeededGenerator(seed: 2)
            lesson.startLesson(
                lessonID: mustLesson("l-salam"),
                in: bundle,
                progress: progress,
                releasedUnitIDs: [mustUnit("u-home")],
                showsPronunciation: true,
                voiceOver: false,
                on: day.adding(days: 1),
                using: &rng
            )
            var session = try #require(lesson.session)
            #expect(lesson.attempt?.sessionID == salamSession)
            #expect(lesson.attempt?.startedDay == day)
            #expect(session.answers.count == 1)
            try submit(&session, correct: true)
            let attempt = try #require(lesson.attempt)
            _ = try await lesson.saveFinished(
                attempt: attempt,
                session: session,
                on: day.adding(days: 1),
                in: bundle,
                to: store
            )
        }

        let finished = try await readStore(at: url, contentVersion: version)
        #expect(finished.activeSession == nil)
        #expect(finished.lessonProgress.map(\.lessonID).sorted { $0.rawValue < $1.rawValue } == [
            mustLesson("l-book"),
            mustLesson("l-salam"),
        ])
        #expect(finished.lessonProgress.first { $0.lessonID == mustLesson("l-book") }?.firstCompletedDay == day)
        #expect(finished.lessonProgress.first { $0.lessonID == mustLesson("l-salam") }?.firstCompletedDay == day.adding(days: 1))
        #expect(finished.cards.map(\.itemID).sorted { $0.rawValue < $1.rawValue } == [
            mustItem("e-book"),
            mustItem("e-salam"),
        ])
        #expect(finished.streak.lastActiveDay == day.adding(days: 1))
        #expect(finished.streak.current == 2)
        #expect(finished.completedSessions.count == 2)
    }

    @Test func aFailedSaveLeavesTheFinishedLessonAndTheLastGoodAnswer() async throws {
        let container = try ProgressContainer.make(name: UUID().uuidString, inMemory: true)
        let store = SwiftDataProgressStore(modelContainer: container, contentVersion: version)
        let bundle = course(version: version)
        try await storeFinishedBook(to: store, in: bundle)
        let attempt = LessonAttempt(
            sessionID: salamSession,
            lessonID: mustLesson("l-salam"),
            startedDay: day,
            contentVersion: version
        )
        try await attempt.saveActive(openSalam(), answeredOn: nil, to: store)

        let lesson = OpenLesson()
        var rng = SeededGenerator(seed: 3)
        lesson.startLesson(
            lessonID: mustLesson("l-salam"),
            in: bundle,
            progress: try await store.load(),
            releasedUnitIDs: [mustUnit("u-home")],
            showsPronunciation: true,
            voiceOver: false,
            on: day,
            using: &rng
        )
        var session = try #require(lesson.session)
        try submit(&session, correct: true)
        lesson.saveAnswer(session, on: day, to: store)
        await lesson.waitUntilSavesFinish()
        let kept = try await store.load()
        #expect(kept.lessonProgress.map(\.lessonID) == [mustLesson("l-book")])
        #expect(kept.cards.map(\.itemID) == [mustItem("e-book")])
        #expect(kept.activeSession?.lesson?.answers.count == 1)

        try submit(&session, correct: false)
        await store.prepareFailedSave()
        lesson.saveAnswer(session, on: day, to: store)
        await lesson.waitUntilSavesFinish()
        #expect(lesson.hasUnsavedAnswers)
        let loaded = try await store.load()
        #expect(loaded.lessonProgress == kept.lessonProgress)
        #expect(loaded.cards == kept.cards)
        #expect(loaded.streak == kept.streak)
        #expect(loaded.completedSessions == kept.completedSessions)
        #expect(loaded.activeSession == kept.activeSession)
        #expect(lesson.session?.answers.count == 2)
    }

    private func storeFinishedBook(to store: SwiftDataProgressStore, in bundle: ContentBundle) async throws {
        let attempt = LessonAttempt(
            sessionID: bookSession,
            lessonID: mustLesson("l-book"),
            startedDay: day,
            contentVersion: version
        )
        let answer = SessionAnswer(task: choice("e-book"), answer: .choice(mustItem("e-book")), result: .correct)
        let finished = LessonSession(lessonID: mustLesson("l-book"), tasks: [], answers: [answer])
        _ = try await attempt.save(finished, answeredOn: day, in: bundle, to: store)
    }

    private func openSalam() -> LessonSession {
        LessonSession(
            lessonID: mustLesson("l-salam"),
            tasks: [choice("e-salam"), choice("e-manana")]
        )
    }

    private func withStore(
        at url: URL,
        version: String,
        _ body: (SwiftDataProgressStore) async throws -> Void
    ) async throws {
        let container = try ProgressContainer.make(at: url)
        let store = SwiftDataProgressStore(modelContainer: container, contentVersion: version)
        try await body(store)
    }

    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pashto-lesson-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Progress.store")
    }

    private func course(version: String) -> ContentBundle {
        let salam = word("e-salam", "سلام", "hello")
        let thanks = word("e-manana", "مننه", "thanks")
        let book = word("e-book", "کتاب", "book")
        return ContentBundle(
            contentVersion: version,
            variant: ContentBundle.kabulVariant,
            romanization: Romanization(
                table: [
                    Romanization.Entry(
                        letter: "a",
                        translit: "a",
                        ascii: "a",
                        pronunciation: "a",
                        description: "Test coverage."
                    ),
                ],
                difficultCharacters: [],
                unstressedWords: ["a"]
            ),
            items: [salam, thanks, book],
            units: [
                CourseUnit(
                    id: mustUnit("u-home"),
                    track: "main",
                    title: "Home",
                    lessons: [
                        Lesson(
                            id: mustLesson("l-salam"),
                            title: "Hello",
                            items: [LessonItemRef(item: salam.id, role: .introduce)]
                        ),
                        Lesson(
                            id: mustLesson("l-book"),
                            title: "Book",
                            items: [LessonItemRef(item: book.id, role: .introduce)]
                        ),
                    ]
                ),
            ],
            nonDistractorGroups: []
        )
    }

    private func word(_ id: String, _ pashto: String, _ en: String) -> ContentItem {
        ContentItem(
            id: mustItem(id),
            kind: .word,
            pashto: pashto,
            translit: en,
            pronunciation: en,
            en: en,
            verification: Verification(status: .draft)
        )
    }

    private func choice(_ id: String) -> SessionTask {
        let target = mustItem(id)
        return SessionTask(
            payload: .choice(QuizTask(
                kind: .meaningPashtoToEnglish,
                targetID: target,
                prompt: id,
                usage: nil,
                options: [
                    QuizOption(itemID: target, text: id),
                    QuizOption(itemID: mustItem("e-other"), text: "other"),
                ]
            ))
        )
    }

    private func submit(_ session: inout LessonSession, correct: Bool) throws {
        let task = try #require(session.current)
        guard case .choice(let quiz) = task.payload else {
            Issue.record("Expected a choice")
            return
        }
        let answer: QuizAnswer = correct
            ? .choice(quiz.targetID)
            : .choice(quiz.options.first { $0.itemID != quiz.targetID }?.itemID ?? mustItem("e-nope"))
        var rng = SeededGenerator(seed: 9)
        _ = session.submit(answer, using: &rng)
    }

    private func mustLesson(_ raw: String) -> LessonID {
        guard let id = LessonID(rawValue: raw) else { preconditionFailure(raw) }
        return id
    }

    private func mustUnit(_ raw: String) -> UnitID {
        guard let id = UnitID(rawValue: raw) else { preconditionFailure(raw) }
        return id
    }

    private func mustItem(_ raw: String) -> ItemID {
        guard let id = ItemID(rawValue: raw) else { preconditionFailure(raw) }
        return id
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
        return mixed ^ (mixed >> 31)
    }
}
