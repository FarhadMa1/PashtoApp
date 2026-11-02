import Foundation
import PashtoCore
import SwiftData
import Testing

@testable import PashtoPersistence

struct ProgressScreenPersistenceTests {
    @Test func newerErrorsChooseUpdateNeeded() {
        let failures: [ProgressPersistenceError] = [
            .newerSchema("Stored entity ExtraRecord is not in schema."),
            .newerSnapshot(ProgressSnapshot.currentVersion + 1),
            .newerPayload(ActiveSessionSnapshot.currentPayloadVersion + 1),
        ]
        for failure in failures {
            #expect(progressScreen(for: progressOpenFailure(for: failure)) == .updateNeeded)
            #expect(progressScreen(for: failure.openFailure).canStartOver == false)
        }
    }

    @Test func otherErrorsChooseStorageError() {
        let failures: [Error] = [
            ProgressPersistenceError.failedToOpen("disk"),
            ProgressPersistenceError.unsupportedSnapshot(0),
            ProgressPersistenceError.unknownStoredValue(field: "ReviewCard.state", value: "nope"),
            ProgressPersistenceError.invalidDayNumber(-1),
            NSError(domain: "Pashto", code: 1),
        ]
        for failure in failures {
            #expect(progressScreen(for: progressOpenFailure(for: failure)) == .storageError)
        }
    }

    @Test @MainActor func loadOfANewerPayloadChoosesUpdateNeeded() async throws {
        let newer = ActiveSessionSnapshot.currentPayloadVersion + 1
        let seeded = try seededActiveSession(
            payloadVersion: newer,
            payload: Data("newer".utf8),
            sessionID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAA9"
        )
        do {
            _ = try await seeded.store.load()
            Issue.record("load should throw for a newer payload")
        } catch {
            #expect(progressScreen(for: progressOpenFailure(for: error)) == .updateNeeded)
        }

        let sessions = try ModelContext(seeded.container).fetch(FetchDescriptor<ActiveSessionRecord>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.payloadVersion == newer)
    }

    @Test func loadOfANewerSnapshotChoosesUpdateNeeded() async throws {
        let url = try await makeV1File()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let newer = ProgressSnapshot.currentVersion + 1
        try StoreFileEdit.apply(to: url) { database in
            try StoreFileEdit.setSnapshotVersion(newer, in: database)
        }
        try StoreFileEdit.keepCurrentSchemaMarker(at: url)
        let before = try storedBytes(around: url)

        do {
            let container = try ProgressContainer.make(at: url)
            let store = SwiftDataProgressStore(modelContainer: container, contentVersion: "2026.11.0")
            _ = try await store.load()
            Issue.record("a newer snapshot should not load")
        } catch {
            #expect(progressScreen(for: progressOpenFailure(for: error)) == .updateNeeded)
        }
        #expect(try storedBytes(around: url) == before)
    }

    @Test func aNewerSchemaFileChoosesUpdateNeededAndIsLeftUntouched() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pashto-screen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Progress.store")
        try FutureStore.write(at: url, text: "keep-me")
        let before = try storedBytes(around: url)

        do {
            _ = try ProgressContainer.make(at: url)
            Issue.record("a newer schema should not open")
        } catch {
            #expect(progressScreen(for: progressOpenFailure(for: error)) == .updateNeeded)
        }
        #expect(try storedBytes(around: url) == before)
        #expect(try FutureStore.read(at: url) == "keep-me")
    }

    @Test func anUnreadableFileChoosesStorageError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pashto-garbled-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Progress.store")
        try Data("not a store".utf8).write(to: url)
        let before = try storedBytes(around: url)
        #expect(before[url.lastPathComponent + "-wal"] == nil)
        #expect(before[url.lastPathComponent + "-shm"] == nil)

        do {
            _ = try ProgressContainer.make(at: url)
            Issue.record("a garbled file should not open")
        } catch {
            #expect(progressScreen(for: progressOpenFailure(for: error)) == .storageError)
        }
        #expect(try storedBytes(around: url) == before)
    }

    @Test @MainActor func loadOfAnUnknownValueChoosesStorageError() async throws {
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
                state: "nope",
                source: ReviewCardSource.lesson.rawValue
            )
        )
        try writer.save()
        let store = SwiftDataProgressStore(modelContainer: container, contentVersion: "2026.11.0")
        do {
            _ = try await store.load()
            Issue.record("an unknown stored value should throw")
        } catch {
            #expect(progressScreen(for: progressOpenFailure(for: error)) == .storageError)
        }
    }

    @Test func aReadableStoreChoosesReady() async throws {
        let url = try await makeV1File()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let loaded = try await readStore(at: url, contentVersion: "2026.11.0")
        #expect(progressScreen(streak: loaded.streak, on: LocalDay(year: 2026, month: 11, day: 1)) == .ready)
    }

    @Test func loadOfAnUncoveredBreakChoosesWelcomeBackAndKeepsFreezes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pashto-welcome-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Progress.store")
        let last = LocalDay(year: 2026, month: 11, day: 1)
        let today = LocalDay(year: 2026, month: 11, day: 5)
        let streakState = StreakState(
            current: 4,
            longest: 9,
            lastActiveDay: last,
            freezes: 2,
            daysTowardNextFreeze: 0,
            freezeUsedDays: []
        )
        let sessionID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDD1")!
        try await writeStore(at: url, contentVersion: "2026.11.0") { store in
            try await store.commit(
                SessionCommit(
                    sessionID: sessionID,
                    cards: [],
                    lessonProgress: nil,
                    streak: streakState,
                    completed: CompletedSession(
                        sessionID: sessionID,
                        kind: .lesson,
                        lessonID: nil,
                        completedDay: last,
                        questionCount: 1,
                        firstTryCorrect: 1
                    )
                )
            )
        }

        let loaded = try await readStore(at: url, contentVersion: "2026.11.0")
        #expect(loaded.streak.freezes == 2)
        #expect(progressScreen(streak: loaded.streak, on: today) == .welcomeBack)
        let next = streak(loaded.streak, after: .completedSession, on: today)
        #expect(next.freezes == 2)
        #expect(next.current == 1)
    }
}
