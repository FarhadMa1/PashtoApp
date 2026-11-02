import Foundation
import PashtoCore
import SQLite3

/// A store that was moved aside, and the settings read from it first.
///
/// `settings` is nil when the file had no settings row or could not be read.
/// The moved files are the original bytes. `backupDirectory` may not exist
/// when there was no file to move.
public struct PreservedProgress: Equatable, Sendable {
    public let settings: UserSettings?
    /// The content version stored in the file, when the meta row could be read.
    public let contentVersion: String?
    public let backupDirectory: URL
    public let movedFiles: [URL]

    public init(
        settings: UserSettings?,
        contentVersion: String?,
        backupDirectory: URL,
        movedFiles: [URL]
    ) {
        self.settings = settings
        self.contentVersion = contentVersion
        self.backupDirectory = backupDirectory
        self.movedFiles = movedFiles
    }
}

/// Moves a progress store out of the way so a new file can be created.
///
/// The store and its `-wal` and `-shm` sidecars move into
/// `Backups/<timestamp>/` next to the store. When that directory already
/// exists, the next free suffix is used and the old directory is not
/// changed. The bytes are not rewritten. Nothing is deleted: a failed move
/// is moved back, and a file that cannot be moved back stays in the backup.
///
/// Settings and the content version are read from a copy before the move.
/// The caller writes the fresh store. This type does not open `ModelContainer`
/// and does not create the replacement file. A later failure uses
/// `undoReplacement`, which removes only the files that appeared at the
/// original path and moves the backup back.
public enum ProgressStoreRestart {
    /// Sibling directory that holds one folder per start-over.
    public static let backupsDirectoryName = "Backups"

    /// Sidecars SwiftData keeps beside the store. The empty suffix is the store.
    static let fileSuffixes = ["", "-wal", "-shm"]

    public static func moveAside(storeAt url: URL, timestamp: String) throws -> PreservedProgress {
        try validate(timestamp)
        let header = readHeader(at: url)
        let files = existingFiles(at: url)
        let backups = url.deletingLastPathComponent()
            .appendingPathComponent(backupsDirectoryName, isDirectory: true)
        guard !files.isEmpty else {
            return PreservedProgress(
                settings: header.settings,
                contentVersion: header.contentVersion,
                backupDirectory: backups,
                movedFiles: []
            )
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: backups, withIntermediateDirectories: true)
        let directory = try uniqueDirectory(timestamp, in: backups, fileManager: fileManager)
        var moved: [(source: URL, destination: URL)] = []
        do {
            for file in files {
                let destination = directory.appendingPathComponent(file.lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) {
                    throw ProgressPersistenceError.failedToOpen(
                        "Backup \(destination.lastPathComponent) already exists."
                    )
                }
                try fileManager.moveItem(at: file, to: destination)
                moved.append((file, destination))
            }
        } catch {
            restore(moved, fileManager: fileManager)
            throw error
        }
        return PreservedProgress(
            settings: header.settings,
            contentVersion: header.contentVersion,
            backupDirectory: directory,
            movedFiles: moved.map(\.destination)
        )
    }

    /// Removes the store files created after `moveAside`, then moves the backup back.
    ///
    /// The files at the original path are the ones this attempt created. They
    /// are the only files removed. Each backup file is moved back to the name
    /// it had. A backup file is left in place when the original path is still
    /// occupied, so the original bytes stay on disk.
    static func undoReplacement(storeAt url: URL, preserved: PreservedProgress) {
        let fileManager = FileManager.default
        for suffix in fileSuffixes {
            let created = URL(fileURLWithPath: url.path + suffix)
            guard fileManager.fileExists(atPath: created.path), !fileManager.isDirectory(created) else {
                continue
            }
            try? fileManager.removeItem(at: created)
        }
        let parent = url.deletingLastPathComponent()
        for backedUp in preserved.movedFiles {
            let destination = parent.appendingPathComponent(backedUp.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) { continue }
            try? fileManager.moveItem(at: backedUp, to: destination)
        }
    }

    private static func validate(_ timestamp: String) throws {
        let allowed = timestamp.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" || scalar == "."
        }
        guard !timestamp.isEmpty,
              timestamp != "." && timestamp != "..",
              !timestamp.hasPrefix("."),
              allowed
        else {
            throw ProgressPersistenceError.failedToOpen("The backup name is not valid.")
        }
    }

    /// The first directory under `backups` that is not already there.
    private static func uniqueDirectory(
        _ timestamp: String,
        in backups: URL,
        fileManager: FileManager
    ) throws -> URL {
        var candidate = backups.appendingPathComponent(timestamp, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = backups.appendingPathComponent("\(timestamp)-\(suffix)", isDirectory: true)
            suffix += 1
            if suffix > 1000 {
                throw ProgressPersistenceError.failedToOpen("No free backup directory was found.")
            }
        }
        try fileManager.createDirectory(at: candidate, withIntermediateDirectories: false)
        return candidate
    }

    private static func existingFiles(at url: URL) -> [URL] {
        let fileManager = FileManager.default
        return fileSuffixes.compactMap { suffix in
            let file = URL(fileURLWithPath: url.path + suffix)
            guard fileManager.fileExists(atPath: file.path),
                  !fileManager.isDirectory(file)
            else { return nil }
            return file
        }
    }

    private static func readHeader(at url: URL) -> StoredHeader {
        (try? StoredSettings.load(at: url)) ?? StoredHeader(settings: nil, contentVersion: nil)
    }

    /// Puts files back when a later move fails. A file that cannot return
    /// stays where it was moved. It is not deleted.
    private static func restore(_ moved: [(source: URL, destination: URL)], fileManager: FileManager) {
        for pair in moved.reversed() {
            if fileManager.fileExists(atPath: pair.source.path) { continue }
            try? fileManager.moveItem(at: pair.destination, to: pair.source)
        }
    }
}

extension FileManager {
    fileprivate func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        return isDirectory.boolValue
    }
}

struct StoredHeader: Equatable {
    var settings: UserSettings?
    var contentVersion: String?
}

/// Reads `SettingsRecord` without opening the store in SwiftData.
///
/// The read uses a copy, so the file the learner owns is not written. A
/// missing file, a missing table, or columns this build does not recognise
/// come back as nil settings. Start over can still move that file.
enum StoredSettings {
    static func read(at url: URL) throws -> UserSettings? {
        try load(at: url).settings
    }

    static func contentVersion(at url: URL) -> String? {
        (try? load(at: url))?.contentVersion
    }

    static func load(at url: URL) throws -> StoredHeader {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path), !fileManager.isDirectory(url) else {
            return StoredHeader(settings: nil, contentVersion: nil)
        }
        let copy = try copiedStore(at: url)
        defer { try? fileManager.removeItem(at: copy.deletingLastPathComponent()) }
        let database = try openReadOnly(copy)
        defer { sqlite3_close(database) }
        // The connection is already read-only. This keeps a library that
        // ignores the open flag from writing the copy.
        _ = sqlite3_exec(database, "PRAGMA query_only = ON", nil, nil, nil)

        let settings: UserSettings?
        do {
            settings = try readSettings(in: database)
        } catch {
            settings = nil
        }
        return StoredHeader(
            settings: settings,
            contentVersion: try? readContentVersion(in: database)
        )
    }

    private static func readSettings(in database: OpaquePointer) throws -> UserSettings? {
        let tables = try column("SELECT name FROM sqlite_master WHERE type = 'table'", in: database)
        guard let table = tables.first(where: { $0.range(of: "SETTINGSRECORD", options: .caseInsensitive) != nil }),
              isSafeIdentifier(table)
        else { return nil }

        let columns = try column("SELECT name FROM pragma_table_info('\(table)')", in: database)
        guard let goal = named(columns, containing: "DAILYGOAL"),
              let transliteration = named(columns, containing: "SHOWTRANSLITERATION"),
              let placement = named(columns, containing: "PLACEMENTTAKENDAY")
        else {
            throw ProgressPersistenceError.failedToOpen(
                "Settings columns were \(columns.joined(separator: ", "))."
            )
        }
        let key = columns.first { name in
            let upper = name.uppercased()
            return upper == "KEY" || upper == "ZKEY"
        }

        var sql = "SELECT \(goal), \(transliteration), \(placement) FROM \(table)"
        if let key, isSafeIdentifier(key) {
            sql += " WHERE \(key) = 'settings'"
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ProgressPersistenceError.failedToOpen("The settings query could not be prepared.")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        let dailyGoal = validatedDailyGoal(Int(sqlite3_column_int64(statement, 0)))
        let showTransliteration = sqlite3_column_int64(statement, 1) != 0
        let placementDay: LocalDay?
        if sqlite3_column_type(statement, 2) == SQLITE_NULL {
            placementDay = nil
        } else {
            placementDay = try? DayNumber.decode(Int(sqlite3_column_int64(statement, 2)))
        }
        return UserSettings(
            dailyGoal: dailyGoal,
            showTransliteration: showTransliteration,
            placementTakenDay: placementDay
        )
    }

    /// `ZCONTENTVERSION` only. `ZLASTRECONCILEDCONTENTVERSION` also contains
    /// that word and is a different column.
    private static func readContentVersion(in database: OpaquePointer) throws -> String? {
        let tables = try column("SELECT name FROM sqlite_master WHERE type = 'table'", in: database)
        guard let table = tables.first(where: { $0.range(of: "STOREMETARECORD", options: .caseInsensitive) != nil }),
              isSafeIdentifier(table)
        else { return nil }
        let columns = try column("SELECT name FROM pragma_table_info('\(table)')", in: database)
        guard let version = exactColumn(columns, "CONTENTVERSION") else { return nil }
        let key = columns.first { name in
            let upper = name.uppercased()
            return upper == "KEY" || upper == "ZKEY"
        }
        var sql = "SELECT \(version) FROM \(table)"
        if let key, isSafeIdentifier(key) {
            sql += " WHERE \(key) = 'meta'"
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard sqlite3_column_type(statement, 0) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, 0)
        else { return nil }
        let value = String(cString: cString)
        return value.isEmpty ? nil : value
    }

    /// The content-version column. A reconciled-version column contains the
    /// same word and is left out. The shortest remaining name is the match.
    private static func exactColumn(_ columns: [String], _ target: String) -> String? {
        let matches = columns.filter { name in
            guard isSafeIdentifier(name) else { return false }
            let upper = name.uppercased()
            if upper.contains("RECONCILED") { return false }
            return upper == target || upper == "Z\(target)" || upper.hasSuffix(target)
        }
        return matches.min { $0.count < $1.count }
    }

    /// A copy so the settings query cannot touch the file that will be moved.
    private static func copiedStore(at url: URL) throws -> URL {
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("pashto-settings-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
        for suffix in ProgressStoreRestart.fileSuffixes {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.copyItem(
                at: source,
                to: scratch.appendingPathComponent(url.lastPathComponent + suffix)
            )
        }
        return scratch.appendingPathComponent(url.lastPathComponent)
    }

    private static func openReadOnly(_ url: URL) throws -> OpaquePointer {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            throw ProgressPersistenceError.failedToOpen("The progress store could not be read.")
        }
        return database
    }

    private static func column(_ sql: String, in database: OpaquePointer) throws -> [String] {
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

    private static func named(_ columns: [String], containing needle: String) -> String? {
        guard let name = columns.first(where: { $0.range(of: needle, options: .caseInsensitive) != nil }),
              isSafeIdentifier(name)
        else { return nil }
        return name
    }

    private static func isSafeIdentifier(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
