import Foundation
import PashtoCore
import Testing

@testable import PashtoPersistence

struct StoreRestartTests {
    @Test func moveAsideMovesTheStoreAndSidecarsWithoutDeletingOrOverwriting() throws {
        let directory = try makeDirectory("pashto-move")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("Progress.store")
        let wal = URL(fileURLWithPath: store.path + "-wal")
        let shm = URL(fileURLWithPath: store.path + "-shm")
        let sibling = directory.appendingPathComponent("notes.txt")
        let storeBytes = Data("progress-bytes".utf8)
        let walBytes = Data("wal-bytes".utf8)
        let shmBytes = Data("shm-bytes".utf8)
        let siblingBytes = Data("leave-me".utf8)
        try storeBytes.write(to: store)
        try walBytes.write(to: wal)
        try shmBytes.write(to: shm)
        try siblingBytes.write(to: sibling)

        let timestamp = "20261102T120000Z"
        let existing = directory
            .appendingPathComponent(ProgressStoreRestart.backupsDirectoryName, isDirectory: true)
            .appendingPathComponent(timestamp, isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let marker = existing.appendingPathComponent("marker.txt")
        let markerBytes = Data("original-backup".utf8)
        try markerBytes.write(to: marker)

        let storeInode = try fileNumber(at: store)
        let walInode = try fileNumber(at: wal)
        let shmInode = try fileNumber(at: shm)

        let preserved = try ProgressStoreRestart.moveAside(storeAt: store, timestamp: timestamp)

        #expect(preserved.settings == nil)
        #expect(preserved.backupDirectory.lastPathComponent == "\(timestamp)-2")
        #expect(Set(preserved.movedFiles.map(\.lastPathComponent)) == [
            "Progress.store", "Progress.store-wal", "Progress.store-shm",
        ])
        for file in [store, wal, shm] {
            #expect(FileManager.default.fileExists(atPath: file.path) == false)
        }
        #expect(try Data(contentsOf: preserved.backupDirectory.appendingPathComponent("Progress.store")) == storeBytes)
        #expect(try Data(contentsOf: preserved.backupDirectory.appendingPathComponent("Progress.store-wal")) == walBytes)
        #expect(try Data(contentsOf: preserved.backupDirectory.appendingPathComponent("Progress.store-shm")) == shmBytes)
        #expect(try fileNumber(at: preserved.backupDirectory.appendingPathComponent("Progress.store")) == storeInode)
        #expect(try fileNumber(at: preserved.backupDirectory.appendingPathComponent("Progress.store-wal")) == walInode)
        #expect(try fileNumber(at: preserved.backupDirectory.appendingPathComponent("Progress.store-shm")) == shmInode)
        #expect(try Data(contentsOf: marker) == markerBytes)
        #expect(try Data(contentsOf: sibling) == siblingBytes)
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func aBadBackupNameDoesNotMoveTheStore() throws {
        let directory = try makeDirectory("pashto-name")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("Progress.store")
        let bytes = Data("stay".utf8)
        try bytes.write(to: store)

        #expect(throws: ProgressPersistenceError.self) {
            try ProgressStoreRestart.moveAside(storeAt: store, timestamp: "../escape")
        }
        #expect(try Data(contentsOf: store) == bytes)
        #expect(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("Backups").path
            ) == false
        )
    }

    @Test func moveAsideKeepsSettingsAndDoesNotRewriteTheStore() async throws {
        let directory = try makeDirectory("pashto-settings")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Progress.store")
        let day = LocalDay(year: 2026, month: 11, day: 1)
        let settings = UserSettings(
            dailyGoal: .serious,
            showTransliteration: false,
            placementTakenDay: day
        )
        let card = ReviewCard.introduced(itemID: try item("e-salam"), on: day)
        let sessionID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEE2")!
        try await writeStore(at: storeURL, contentVersion: "2026.11.0") { store in
            try await store.updateSettings(settings)
            try await store.commit(
                SessionCommit(
                    sessionID: sessionID,
                    cards: [card],
                    lessonProgress: nil,
                    streak: StreakState(
                        current: 4,
                        longest: 4,
                        lastActiveDay: day,
                        freezes: 2,
                        daysTowardNextFreeze: 0,
                        freezeUsedDays: []
                    ),
                    completed: CompletedSession(
                        sessionID: sessionID,
                        kind: .lesson,
                        lessonID: nil,
                        completedDay: day,
                        questionCount: 1,
                        firstTryCorrect: 1
                    )
                )
            )
        }

        let before = try Data(contentsOf: storeURL)
        let read = try StoredSettings.read(at: storeURL)
        #expect(read == settings)
        #expect(try Data(contentsOf: storeURL) == before)

        let preserved = try ProgressStoreRestart.moveAside(storeAt: storeURL, timestamp: "20261102T150000Z")
        #expect(preserved.settings == settings)
        let backupStore = preserved.movedFiles.first { $0.lastPathComponent == "Progress.store" }
        let backup = try #require(backupStore)
        #expect(try Data(contentsOf: backup) == before)
        #expect(FileManager.default.fileExists(atPath: storeURL.path) == false)

        let backedUp = try await readStore(at: backup, contentVersion: "ignored")
        #expect(backedUp.settings == settings)
        #expect(backedUp.cards == [card])
        #expect(backedUp.streak.freezes == 2)
        #expect(backedUp.streak.current == 4)

        let container = try ProgressContainer.make(at: storeURL)
        let fresh = SwiftDataProgressStore(modelContainer: container, contentVersion: "unbundled")
        if let restored = preserved.settings {
            try await fresh.updateSettings(restored)
        }
        let opened = try await fresh.load()
        #expect(opened.settings == settings)
        #expect(opened.cards.isEmpty)
        #expect(opened.lessonProgress.isEmpty)
        #expect(opened.streak == .initial)
        #expect(opened.completedSessions.isEmpty)
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func fileNumber(at url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let number = attributes[.systemFileNumber] as? NSNumber else {
            Issue.record("No file number for \(url.lastPathComponent)")
            throw CancellationError()
        }
        return number.uint64Value
    }

    private func item(_ raw: String) throws -> ItemID {
        guard let item = ItemID(rawValue: raw) else {
            Issue.record("Item id \(raw) is not valid")
            throw CancellationError()
        }
        return item
    }
}
