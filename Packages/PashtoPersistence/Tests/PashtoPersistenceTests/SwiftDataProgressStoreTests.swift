import CoreData
import Foundation
import PashtoCore
import PashtoCoreTesting
import SQLite3
import SwiftData
import Testing

@testable import PashtoPersistence

struct SwiftDataProgressStoreTests {
    @Test func swiftDataStoreMeetsTheContract() async throws {
        try await ProgressStoreContract.run {
            try memoryStore()
        }
    }

    @Test @MainActor func loadClampsWithoutRewritingTheStoredRow() async throws {
        let container = try ProgressContainer.make(name: UUID().uuidString, inMemory: true)
        let store = SwiftDataProgressStore(modelContainer: container, contentVersion: "2026.11.0")
        let day = LocalDay(year: 2026, month: 11, day: 1)
        try await store.commit(
            SessionCommit(
                sessionID: Fixture.id("DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDD1"),
                cards: [Fixture.card("e-low", ease: 1, day: day)],
                lessonProgress: nil,
                streak: Fixture.streak(on: day, freezes: 5),
                completed: Fixture.completed(Fixture.id("DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDD1"), day: day)
            )
        )
        let writer = container.mainContext
        writer.autosaveEnabled = false
        writer.insert(
            SettingsRecord(
                key: RecordKey.settings,
                dailyGoal: 7,
                showTransliteration: false,
                placementTakenDay: nil
            )
        )
        try writer.save()

        let loaded = try await store.load()
        #expect(loaded.cards.first?.easeFactor == ReviewCard.minimumEaseFactor)
        #expect(loaded.streak.freezes == 2)
        #expect(loaded.settings.dailyGoal == .regular)
        #expect(loaded.settings.showTransliteration == false)

        let cards = try writer.fetch(FetchDescriptor<ReviewCardRecord>())
        let streaks = try writer.fetch(FetchDescriptor<StreakRecord>())
        let settings = try writer.fetch(FetchDescriptor<SettingsRecord>())
        #expect(cards.first?.easeFactor == 1)
        #expect(streaks.first?.freezes == 5)
        #expect(settings.first?.dailyGoal == 7)
    }

    @Test @MainActor func newerSnapshotIsRefusedAndNotOverwritten() async throws {
        let container = try ProgressContainer.make(name: UUID().uuidString, inMemory: true)
        let writer = container.mainContext
        writer.autosaveEnabled = false
        let day = DayNumber.encode(LocalDay(year: 2026, month: 11, day: 1))
        writer.insert(
            ReviewCardRecord(
                itemID: "e-keep",
                easeFactor: 2.5,
                intervalDays: 1,
                repetitions: 0,
                lapses: 0,
                dueDay: day,
                lastReviewedDay: nil,
                createdDay: day,
                state: ReviewCardState.active.rawValue,
                source: ReviewCardSource.lesson.rawValue
            )
        )
        writer.insert(
            StoreMetaRecord(
                key: RecordKey.meta,
                contentVersion: "2026.11.0",
                snapshotVersion: ProgressSnapshot.currentVersion + 1,
                lastReconciledContentVersion: nil,
                latestObservedDay: nil
            )
        )
        try writer.save()

        let store = SwiftDataProgressStore(modelContainer: container, contentVersion: "2026.11.0")
        let newer = ProgressSnapshot.currentVersion + 1
        await expectStoreThrows(.newerSnapshot(newer)) {
            try await store.load()
        }
        await expectStoreThrows(.newerSnapshot(newer)) {
            try await store.resetAll()
        }
        await expectStoreThrows(.newerSnapshot(newer)) {
            try await store.commit(Fixture.simpleCommit())
        }

        let cards = try writer.fetch(FetchDescriptor<ReviewCardRecord>())
        let metas = try writer.fetch(FetchDescriptor<StoreMetaRecord>())
        #expect(cards.count == 1)
        #expect(cards.first?.itemID == "e-keep")
        #expect(cards.first?.easeFactor == 2.5)
        #expect(metas.first?.snapshotVersion == newer)
        #expect(metas.first?.contentVersion == "2026.11.0")
    }

    @Test @MainActor func loadDropsAnOlderActiveSession() async throws {
        let seeded = try seededActiveSession(
            payloadVersion: 0,
            payload: Data(#"{"payloadVersion":0}"#.utf8),
            sessionID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA1"
        )
        let loaded = try await seeded.store.load()
        #expect(loaded.activeSession == nil)
        try expectKeptCard(in: seeded.container, loaded: loaded)
    }

    @Test @MainActor func loadDropsACorruptActiveSession() async throws {
        let seeded = try seededActiveSession(
            payloadVersion: ActiveSessionSnapshot.currentPayloadVersion,
            payload: Data("not-json".utf8),
            sessionID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA2"
        )
        let loaded = try await seeded.store.load()
        #expect(loaded.activeSession == nil)
        try expectKeptCard(in: seeded.container, loaded: loaded)
    }

    @Test @MainActor func loadRefusesANewerActiveSession() async throws {
        let newer = ActiveSessionSnapshot.currentPayloadVersion + 1
        let seeded = try seededActiveSession(
            payloadVersion: newer,
            payload: Data("newer".utf8),
            sessionID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA3"
        )
        await expectStoreThrows(.newerPayload(newer)) {
            try await seeded.store.load()
        }
        let reader = ModelContext(seeded.container)
        let sessions = try reader.fetch(FetchDescriptor<ActiveSessionRecord>())
        let cards = try reader.fetch(FetchDescriptor<ReviewCardRecord>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.payloadVersion == newer)
        #expect(cards.count == 1)
        #expect(cards.first?.itemID == "e-keep")
        #expect(cards.first?.easeFactor == 2.5)
    }

    @Test @MainActor func localDayRoundTripsAsTheCoreDayNumber() async throws {
        let container = try ProgressContainer.make(name: UUID().uuidString, inMemory: true)
        let store = SwiftDataProgressStore(modelContainer: container, contentVersion: "2026.11.0")
        let day = LocalDay(year: 2026, month: 11, day: 1)
        let sessionID = Fixture.id("EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEE1")
        try await store.commit(
            SessionCommit(
                sessionID: sessionID,
                cards: [Fixture.card("e-day", ease: 2.5, day: day)],
                lessonProgress: nil,
                streak: Fixture.streak(on: day, freezes: 0),
                completed: Fixture.completed(sessionID, day: day)
            )
        )

        let loaded = try await store.load()
        let stored = day.days(from: LocalDay(year: 1970, month: 1, day: 1))
        #expect(loaded.cards.first?.createdDay == day)
        #expect(loaded.cards.first?.dueDay == day)
        #expect(loaded.completedSessions.first?.completedDay == day)
        #expect(loaded.streak.lastActiveDay == day)

        let cards = try container.mainContext.fetch(FetchDescriptor<ReviewCardRecord>())
        #expect(cards.first?.createdDay == stored)
        #expect(cards.first?.dueDay == stored)
    }

    @Test func newerSchemaFileIsLeftUntouched() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pashto-newer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Progress.store")
        try FutureStore.write(at: url, text: "keep-me")
        let before = try storedBytes(around: url)

        do {
            _ = try ProgressContainer.make(at: url)
            Issue.record("a newer schema should not open")
        } catch {
            #expect(error is ProgressPersistenceError)
        }

        #expect(try storedBytes(around: url) == before)
        #expect(try FutureStore.read(at: url) == "keep-me")
    }

    @Test func storeWithOneExtraEntityIsLeftUntouched() async throws {
        let url = try await makeV1File()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try StoreFileEdit.addModelHash(named: "ExtraRecord", at: url)
        try expectOpenThrows(
            .newerSchema("Stored entity ExtraRecord is not in schema \(SchemaV1.versionIdentifier)."),
            at: url
        )
    }

    @Test func newerStoreMetaVersionIsLeftUntouched() async throws {
        let url = try await makeV1File()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let newer = ProgressSnapshot.currentVersion + 1
        try StoreFileEdit.apply(to: url) { database in
            try StoreFileEdit.setSnapshotVersion(newer, in: database)
        }
        try StoreFileEdit.keepCurrentSchemaMarker(at: url)
        try expectOpenThrows(.newerSnapshot(newer), at: url)
    }

    @Test func v1FileStoreReopensThroughTheGuard() async throws {
        let url = try await makeV1File()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let loaded = try await readStore(at: url, contentVersion: "not-the-stored-version")
        #expect(loaded.contentVersion == "2026.11.0")
        #expect(loaded.settings == .initial)
    }

    @Test func fileStoreSurvivesReopenAndResetKeepsSettings() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pashto-progress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Progress.store")
        let version = "2026.11.0"
        let day = LocalDay(year: 2026, month: 11, day: 1)
        let reviewed = LocalDay(year: 2026, month: 10, day: 31)
        let settings = UserSettings(dailyGoal: .light, showTransliteration: false, placementTakenDay: day)
        let card = ReviewCard(
            itemID: Fixture.item("e-salam"),
            easeFactor: 2.2,
            intervalDays: 6,
            repetitions: 2,
            lapses: 1,
            dueDay: day,
            lastReviewedDay: reviewed,
            createdDay: day,
            state: .active,
            source: .placement
        )
        let lesson = LessonProgress(
            lessonID: Fixture.lesson("l-greetings-1"),
            source: .placement,
            firstCompletedDay: day,
            bestScorePercent: 80
        )
        let streak = StreakState(
            current: 4,
            longest: 9,
            lastActiveDay: day,
            freezes: 1,
            daysTowardNextFreeze: 2,
            freezeUsedDays: [reviewed]
        )
        let finished = Fixture.id("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBB1")
        let active = Fixture.active(id: Fixture.id("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBB2"), day: day)

        try await writeStore(at: url, contentVersion: version) { store in
            try await store.updateSettings(settings)
            try await store.commit(
                SessionCommit(
                    sessionID: finished,
                    cards: [card],
                    lessonProgress: lesson,
                    streak: streak,
                    completed: Fixture.completed(finished, day: day, lessonID: lesson.lessonID)
                )
            )
            try await store.saveActiveSession(active)
        }

        let reopened = try await readStore(at: url, contentVersion: "not-the-stored-version")
        #expect(reopened.contentVersion == version)
        #expect(reopened.settings == settings)
        #expect(reopened.cards == [card])
        #expect(reopened.lessonProgress == [lesson])
        #expect(reopened.streak == streak)
        #expect(reopened.completedSessions.map(\.sessionID) == [finished])
        #expect(reopened.completedSessions.first?.completedDay == day)
        #expect(reopened.activeSession == active)

        try await writeStore(at: url, contentVersion: "not-the-stored-version") { store in
            try await store.resetAll()
        }
        let cleared = try await readStore(at: url, contentVersion: "still-not-stored")
        #expect(cleared.contentVersion == version)
        #expect(cleared.settings.dailyGoal == .light)
        #expect(cleared.settings.showTransliteration == false)
        #expect(cleared.settings.placementTakenDay == nil)
        #expect(cleared.cards.isEmpty)
        #expect(cleared.lessonProgress.isEmpty)
        #expect(cleared.streak == .initial)
        #expect(cleared.activeSession == nil)
        #expect(cleared.completedSessions.isEmpty)
        #expect(cleared.lastReconciledContentVersion == nil)
        #expect(cleared.latestObservedDay == nil)
    }

    @Test func placementWriteIsOneSaveAndAFailureKeepsThePreviousRows() async throws {
        let container = try ProgressContainer.make(name: UUID().uuidString, inMemory: true)
        let store = SwiftDataProgressStore(modelContainer: container, contentVersion: "test")
        let day = LocalDay(year: 2026, month: 11, day: 2)
        let bundle = placementBundle()
        _ = try await ProgressReconciler.run(store: store, content: bundle, on: day)
        let savesAfterReconcile = await store.successfulSaveCount

        let commit = placementCommit(
            scores: [
                PlacementUnitScore(
                    unitID: mustID("u-greetings"),
                    correct: 4,
                    questions: 5,
                    skipped: true
                ),
            ],
            in: bundle,
            takenOn: day
        )
        try await store.applyPlacement(commit)
        #expect(await store.successfulSaveCount == savesAfterReconcile + 1)
        let stored = try await store.load()
        #expect(stored.settings.placementTakenDay == day)
        #expect(stored.lessonProgress.map(\.lessonID.rawValue) == ["l-greetings-1"])
        #expect(stored.lessonProgress.first?.source == .placement)
        #expect(stored.cards.map(\.itemID.rawValue) == ["e-one", "e-two"])
        #expect(stored.cards.allSatisfy { $0.source == .placement })
        #expect(!stored.lessonProgress.contains { $0.lessonID.rawValue == "l-sounds" })

        let again = try await ProgressReconciler.run(store: store, content: bundle, on: day)
        #expect(again == stored)
        #expect(await store.successfulSaveCount == savesAfterReconcile + 1)

        let beforeFailure = try await store.load()
        await store.prepareFailedSave()
        do {
            try await store.applyPlacement(
                PlacementCommit(
                    lessonProgress: [
                        LessonProgress(
                            lessonID: mustLesson("l-extra"),
                            source: .placement,
                            firstCompletedDay: day,
                            bestScorePercent: 100
                        ),
                    ],
                    cards: [ReviewCard.introduced(itemID: mustItem("e-extra"), on: day, source: .placement)],
                    placementTakenDay: day.adding(days: 4)
                )
            )
            Issue.record("a failed placement save should throw")
        } catch let error as ProgressWriteError {
            #expect(error == .saveFailed)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        let afterFailure = try await store.load()
        #expect(afterFailure == beforeFailure)
        let reconciled = try await ProgressReconciler.run(store: store, content: bundle, on: day)
        #expect(reconciled == beforeFailure)
        #expect(await store.successfulSaveCount == savesAfterReconcile + 1)
    }

    @Test func placementDoesNotOverwriteACardWithHistoryOrLowerAScore() async throws {
        let container = try ProgressContainer.make(name: UUID().uuidString, inMemory: true)
        let store = SwiftDataProgressStore(modelContainer: container, contentVersion: "test")
        let day = LocalDay(year: 2026, month: 11, day: 2)
        let kept = ReviewCard(
            itemID: mustItem("e-kept"),
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
            lessonID: mustLesson("l-done"),
            source: .completed,
            firstCompletedDay: day.adding(days: -30),
            bestScorePercent: 100
        )
        let session = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCC2")!
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
        let savesBefore = await store.successfulSaveCount
        try await store.applyPlacement(PlacementCommit(
            lessonProgress: [
                LessonProgress(
                    lessonID: finished.lessonID,
                    source: .placement,
                    firstCompletedDay: day,
                    bestScorePercent: 80
                ),
                LessonProgress(
                    lessonID: mustLesson("l-greetings-1"),
                    source: .placement,
                    firstCompletedDay: day,
                    bestScorePercent: 80
                ),
            ],
            cards: [
                ReviewCard.introduced(itemID: kept.itemID, on: day.adding(days: 1), source: .placement),
                ReviewCard.introduced(itemID: mustItem("e-place"), on: day.adding(days: 1), source: .placement),
            ],
            placementTakenDay: day
        ))
        #expect(await store.successfulSaveCount == savesBefore + 1)
        let stored = try await store.load()
        #expect(stored.cards.first { $0.itemID == kept.itemID } == kept)
        #expect(stored.lessonProgress.contains(finished))
        #expect(stored.lessonProgress.contains { $0.lessonID.rawValue == "l-greetings-1" && $0.bestScorePercent == 80 })
        #expect(stored.cards.contains { $0.itemID.rawValue == "e-place" && $0.source == .placement })
        #expect(stored.settings.placementTakenDay == day)
    }
}

private func memoryStore(_ version: String = "2026.11.0") throws -> SwiftDataProgressStore {
    let container = try ProgressContainer.make(name: UUID().uuidString, inMemory: true)
    return SwiftDataProgressStore(modelContainer: container, contentVersion: version)
}

private func writeStore(
    at url: URL,
    contentVersion: String,
    _ body: (SwiftDataProgressStore) async throws -> Void
) async throws {
    let container = try ProgressContainer.make(at: url)
    let store = SwiftDataProgressStore(modelContainer: container, contentVersion: contentVersion)
    try await body(store)
}

private func makeV1File() async throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pashto-guard-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("Progress.store")
    try await writeStore(at: url, contentVersion: "2026.11.0") { store in
        try await store.updateSettings(.initial)
    }
    return url
}

private func expectOpenThrows(_ expected: ProgressPersistenceError, at url: URL) throws {
    let before = try storedBytes(around: url)
    do {
        _ = try ProgressContainer.make(at: url)
        Issue.record("Expected \(expected)")
    } catch let error as ProgressPersistenceError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
    #expect(try storedBytes(around: url) == before)
}

private func readStore(at url: URL, contentVersion: String) async throws -> ProgressSnapshot {
    let container = try ProgressContainer.make(at: url)
    let store = SwiftDataProgressStore(modelContainer: container, contentVersion: contentVersion)
    return try await store.load()
}

@MainActor
private func seededActiveSession(
    payloadVersion: Int,
    payload: Data,
    sessionID: String
) throws -> (container: ModelContainer, store: SwiftDataProgressStore) {
    let container = try ProgressContainer.make(name: UUID().uuidString, inMemory: true)
    let writer = container.mainContext
    writer.autosaveEnabled = false
    let day = DayNumber.encode(LocalDay(year: 2026, month: 11, day: 1))
    writer.insert(
        ReviewCardRecord(
            itemID: "e-keep",
            easeFactor: 2.5,
            intervalDays: 1,
            repetitions: 0,
            lapses: 0,
            dueDay: day,
            lastReviewedDay: nil,
            createdDay: day,
            state: ReviewCardState.active.rawValue,
            source: ReviewCardSource.lesson.rawValue
        )
    )
    writer.insert(
        ActiveSessionRecord(
            key: RecordKey.active,
            sessionID: Fixture.id(sessionID),
            kind: SessionKind.lesson.rawValue,
            lessonID: nil,
            startedDay: day,
            contentVersion: "2026.11.0",
            payloadVersion: payloadVersion,
            payload: payload,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    )
    try writer.save()
    let store = SwiftDataProgressStore(modelContainer: container, contentVersion: "2026.11.0")
    return (container, store)
}

/// `#expect(throws:)` from a `@MainActor` test sends the closure off the
/// main actor. Xcode 16 rejects that. This stays on the main actor.
@MainActor
private func expectStoreThrows(
    _ expected: ProgressPersistenceError,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        Issue.record("Expected \(expected)")
    } catch let error as ProgressPersistenceError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@MainActor
private func expectKeptCard(in container: ModelContainer, loaded: ProgressSnapshot) throws {
    #expect(loaded.cards.map(\.itemID.rawValue) == ["e-keep"])
    #expect(loaded.cards.first?.easeFactor == 2.5)
    let reader = ModelContext(container)
    let sessions = try reader.fetch(FetchDescriptor<ActiveSessionRecord>())
    let cards = try reader.fetch(FetchDescriptor<ReviewCardRecord>())
    #expect(sessions.isEmpty)
    #expect(cards.count == 1)
    #expect(cards.first?.itemID == "e-keep")
    #expect(cards.first?.easeFactor == 2.5)
}

/// Bytes of the store and its write-ahead log. Shared-memory files are not compared.
private func storedBytes(around url: URL) throws -> [String: Data] {
    var files: [String: Data] = [:]
    for file in [url, URL(fileURLWithPath: url.path + "-wal")] {
        guard FileManager.default.fileExists(atPath: file.path) else { continue }
        files[file.lastPathComponent] = try Data(contentsOf: file)
    }
    return files
}

enum FutureSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [Note.self] }

    @Model
    final class Note {
        var text: String

        init(text: String) {
            self.text = text
        }
    }
}

/// Rewrites a closed SwiftData file so a test can hide the model version
/// or add an entity the guard must notice. The checkpoint keeps the edit in
/// the main database instead of a later write-ahead log.
private enum StoreFileEdit {
    static func apply(to url: URL, _ body: (OpaquePointer) throws -> Void) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw ProgressPersistenceError.failedToOpen("The progress store could not be edited.")
        }
        defer { sqlite3_close(database) }
        try exec("PRAGMA wal_checkpoint(TRUNCATE)", in: database)
        try body(database)
        try exec("PRAGMA wal_checkpoint(TRUNCATE)", in: database)
    }

    /// Adds one model-hash key. `NSStoreModelVersionHashes` is what the guard
    /// compares with SchemaV1, so this is an entity the file claims to contain.
    static func addModelHash(named name: String, at url: URL) throws {
        var metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: url,
            options: nil
        )
        var hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Any] ?? [:]
        hashes[name] = Data(repeating: 0, count: 32)
        metadata[NSStoreModelVersionHashesKey] = hashes
        metadata[NSStoreModelVersionIdentifiersKey] = [currentSchemaMarker]
        try NSPersistentStoreCoordinator.setMetadata(
            metadata,
            forPersistentStoreOfType: NSSQLiteStoreType,
            at: url,
            options: nil
        )
    }

    /// Leaves the SwiftData version marker at SchemaV1 so a later failure is
    /// the snapshot row, not the marker.
    static func keepCurrentSchemaMarker(at url: URL) throws {
        var metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: url,
            options: nil
        )
        metadata[NSStoreModelVersionIdentifiersKey] = [currentSchemaMarker]
        try NSPersistentStoreCoordinator.setMetadata(
            metadata,
            forPersistentStoreOfType: NSSQLiteStoreType,
            at: url,
            options: nil
        )
    }

    private static var currentSchemaMarker: String {
        let version = SchemaV1.versionIdentifier
        return "\(version.major).\(version.minor).\(version.patch)"
    }

    static func setSnapshotVersion(_ version: Int, in database: OpaquePointer) throws {
        let tables = try strings("SELECT name FROM sqlite_master WHERE type = 'table'", in: database)
        guard let table = tables.first(where: { $0.range(of: "STOREMETARECORD", options: .caseInsensitive) != nil }),
              isSafeIdentifier(table)
        else {
            throw ProgressPersistenceError.failedToOpen("StoreMetaRecord is not in the file.")
        }
        let names = try strings("SELECT name FROM pragma_table_info('\(table)')", in: database)
        guard let column = names.first(where: { $0.range(of: "SNAPSHOTVERSION", options: .caseInsensitive) != nil }),
              isSafeIdentifier(column)
        else {
            throw ProgressPersistenceError.failedToOpen("snapshotVersion is not in StoreMetaRecord.")
        }
        try exec("UPDATE \(table) SET \(column) = \(version)", in: database)
        guard sqlite3_changes(database) >= 1 else {
            throw ProgressPersistenceError.failedToOpen("StoreMetaRecord was not updated.")
        }
    }

    private static func exec(_ sql: String, in database: OpaquePointer) throws {
        var error: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(database, sql, nil, nil, &error)
        guard code == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "sqlite \(code)"
            sqlite3_free(error)
            throw ProgressPersistenceError.failedToOpen(message)
        }
    }

    private static func strings(_ sql: String, in database: OpaquePointer) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ProgressPersistenceError.failedToOpen("The store query could not be prepared.")
        }
        defer { sqlite3_finalize(statement) }
        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let cString = sqlite3_column_text(statement, 0) else { continue }
            values.append(String(cString: cString))
        }
        return values
    }

    private static func isSafeIdentifier(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}

private enum FuturePlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FutureSchema.self] }
    static var stages: [MigrationStage] { [] }
}

private enum FutureStore {
    static func write(at url: URL, text: String) throws {
        let schema = Schema(versionedSchema: FutureSchema.self)
        let configuration = ModelConfiguration(
            "Future",
            schema: schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: FuturePlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(FutureSchema.Note(text: text))
        try context.save()
    }

    static func read(at url: URL) throws -> String? {
        let schema = Schema(versionedSchema: FutureSchema.self)
        let configuration = ModelConfiguration(
            "Future",
            schema: schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: FuturePlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<FutureSchema.Note>()).first?.text
    }
}

private enum Fixture {
    static let day = LocalDay(year: 2026, month: 11, day: 1)

    static func id(_ raw: String) -> UUID {
        guard let id = UUID(uuidString: raw) else {
            preconditionFailure("UUID \(raw) is not valid")
        }
        return id
    }

    static func item(_ raw: String) -> ItemID {
        guard let item = ItemID(rawValue: raw) else {
            preconditionFailure("Item id \(raw) is not valid")
        }
        return item
    }

    static func lesson(_ raw: String) -> LessonID {
        guard let lesson = LessonID(rawValue: raw) else {
            preconditionFailure("Lesson id \(raw) is not valid")
        }
        return lesson
    }

    static func card(_ raw: String, ease: Double, day: LocalDay) -> ReviewCard {
        ReviewCard(
            itemID: item(raw),
            easeFactor: ease,
            intervalDays: 0,
            repetitions: 0,
            lapses: 0,
            dueDay: day,
            lastReviewedDay: nil,
            createdDay: day,
            state: .active,
            source: .lesson
        )
    }

    static func streak(on day: LocalDay, freezes: Int) -> StreakState {
        StreakState(
            current: 3,
            longest: 3,
            lastActiveDay: day,
            freezes: freezes,
            daysTowardNextFreeze: 1,
            freezeUsedDays: []
        )
    }

    static func completed(_ id: UUID, day: LocalDay, lessonID: LessonID? = nil) -> CompletedSession {
        CompletedSession(
            sessionID: id,
            kind: .lesson,
            lessonID: lessonID,
            completedDay: day,
            questionCount: 1,
            firstTryCorrect: 1
        )
    }

    static func simpleCommit() -> SessionCommit {
        let identifier = id("CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCC1")
        return SessionCommit(
            sessionID: identifier,
            cards: [card("e-two", ease: 2.5, day: day)],
            lessonProgress: nil,
            streak: .initial,
            completed: completed(identifier, day: day)
        )
    }

    static func active(id: UUID, day: LocalDay) -> ActiveSessionSnapshot {
        let target = item("e-salam")
        let task = SessionTask(
            payload: .choice(
                QuizTask(
                    kind: .meaningPashtoToEnglish,
                    targetID: target,
                    prompt: "hello",
                    usage: nil,
                    options: [QuizOption(itemID: target, text: "hello")]
                )
            ),
            isRepeat: false
        )
        return ActiveSessionSnapshot(
            sessionID: id,
            kind: .lesson,
            lessonID: lesson("l-greetings-1"),
            startedDay: day,
            lastAnswerDay: day,
            contentVersion: "2026.11.0",
            lesson: LessonSession(
                lessonID: lesson("l-greetings-1"),
                tasks: [],
                answers: [SessionAnswer(task: task, answer: .choice(target), result: .correct)]
            )
        )
    }
}

private func mustItem(_ raw: String) -> ItemID {
    guard let id = ItemID(rawValue: raw) else { preconditionFailure("bad item \(raw)") }
    return id
}

private func mustLesson(_ raw: String) -> LessonID {
    guard let id = LessonID(rawValue: raw) else { preconditionFailure("bad lesson \(raw)") }
    return id
}

private func mustID(_ raw: String) -> UnitID {
    guard let id = UnitID(rawValue: raw) else { preconditionFailure("bad unit \(raw)") }
    return id
}

private func placementItem(_ id: String, pashto: String, en: String) -> ContentItem {
    ContentItem(
        id: mustItem(id),
        kind: .word,
        pashto: pashto,
        translit: en,
        pronunciation: en,
        en: en,
        verification: Verification(status: .verified, checkedBy: "test", checkedOn: "2026-11-01")
    )
}

private func placementBundle() -> ContentBundle {
    let sound = placementItem("e-sound", pashto: "sound", en: "sound")
    let one = placementItem("e-one", pashto: "one", en: "one")
    let two = placementItem("e-two", pashto: "two", en: "two")
    let sounds = Lesson(
        id: mustLesson("l-sounds"),
        title: "Sounds",
        items: [LessonItemRef(item: sound.id, role: .soundExample, sound: "a")]
    )
    let greetings = Lesson(
        id: mustLesson("l-greetings-1"),
        title: "Hello",
        items: [
            LessonItemRef(item: one.id, role: .introduce),
            LessonItemRef(item: two.id, role: .introduce),
            LessonItemRef(item: sound.id, role: .soundExample, sound: "a"),
        ]
    )
    return ContentBundle(
        contentVersion: "test",
        variant: ContentBundle.kabulVariant,
        romanization: Romanization(table: [], difficultCharacters: [], unstressedWords: []),
        items: [sound, one, two],
        units: [
            CourseUnit(id: mustID("u-sounds"), track: "main", title: "Sounds", lessons: [sounds]),
            CourseUnit(id: mustID("u-greetings"), track: "main", title: "Greetings", lessons: [greetings]),
        ],
        nonDistractorGroups: []
    )
}
