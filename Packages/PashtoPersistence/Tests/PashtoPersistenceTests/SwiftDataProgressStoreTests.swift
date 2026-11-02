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
        try StoreFileEdit.apply(to: url) { database in
            try StoreFileEdit.insertEntity(named: "ExtraRecord", in: database)
            try StoreFileEdit.clearVersionIdentifiers(in: database)
        }
        try expectOpenLeavesFileUntouched(at: url)
    }

    @Test func newerStoreMetaVersionIsLeftUntouched() async throws {
        let url = try await makeV1File()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try StoreFileEdit.apply(to: url) { database in
            try StoreFileEdit.setSnapshotVersion(ProgressSnapshot.currentVersion + 1, in: database)
            try StoreFileEdit.clearVersionIdentifiers(in: database)
        }
        try expectOpenLeavesFileUntouched(at: url)
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

private func expectOpenLeavesFileUntouched(at url: URL) throws {
    let before = try storedBytes(around: url)
    do {
        _ = try ProgressContainer.make(at: url)
        Issue.record("a store this schema does not own should not open")
    } catch {
        #expect(error is ProgressPersistenceError)
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

    static func insertEntity(named name: String, in database: OpaquePointer) throws {
        try exec(
            """
            INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME, Z_SUPER, Z_MAX)
            SELECT COALESCE(MAX(Z_ENT), 0) + 1, '\(name)', 0, 0 FROM Z_PRIMARYKEY
            """,
            in: database
        )
        guard sqlite3_changes(database) == 1 else {
            throw ProgressPersistenceError.failedToOpen("The extra entity was not stored.")
        }
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

    static func clearVersionIdentifiers(in database: OpaquePointer) throws {
        let rows = try blobs("SELECT rowid, Z_PLIST FROM Z_METADATA", in: database)
        guard !rows.isEmpty else {
            throw ProgressPersistenceError.failedToOpen("The store has no metadata row.")
        }
        for (rowid, data) in rows {
            let object = try PropertyListSerialization.propertyList(from: data, format: nil)
            guard var plist = object as? [String: Any] else {
                throw ProgressPersistenceError.failedToOpen("The store metadata is not a dictionary.")
            }
            plist["NSStoreModelVersionIdentifiers"] = [String]()
            let rewritten = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            try bindBlob(rewritten, rowid: rowid, in: database)
        }
    }

    private static func bindBlob(_ data: Data, rowid: Int64, in database: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "UPDATE Z_METADATA SET Z_PLIST = ? WHERE rowid = ?", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw ProgressPersistenceError.failedToOpen("The metadata update could not be prepared.")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let bound = data.withUnsafeBytes { raw in
            sqlite3_bind_blob(statement, 1, raw.baseAddress, Int32(data.count), transient)
        }
        guard bound == SQLITE_OK else {
            throw ProgressPersistenceError.failedToOpen("The metadata blob could not be stored.")
        }
        guard sqlite3_bind_int64(statement, 2, rowid) == SQLITE_OK else {
            throw ProgressPersistenceError.failedToOpen("The metadata row could not be selected.")
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ProgressPersistenceError.failedToOpen("The metadata row was not updated.")
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

    private static func blobs(_ sql: String, in database: OpaquePointer) throws -> [(Int64, Data)] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ProgressPersistenceError.failedToOpen("The store query could not be prepared.")
        }
        defer { sqlite3_finalize(statement) }
        var values: [(Int64, Data)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let rowid = sqlite3_column_int64(statement, 0)
            guard let blob = sqlite3_column_blob(statement, 1) else { continue }
            let count = Int(sqlite3_column_bytes(statement, 1))
            values.append((rowid, Data(bytes: blob, count: count)))
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
