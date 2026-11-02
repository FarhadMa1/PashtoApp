import Foundation
import PashtoCore
import SwiftData
import SQLite3

/// Reads a SwiftData file without opening it in `ModelContainer`.
///
/// On the macOS 15 / Xcode 16 toolchain, opening a store from a schema this
/// plan does not contain does not throw. It replaces the file. This check
/// runs first, read-only, and leaves the file alone.
///
/// One unknown entity is enough to refuse the file. A SwiftData version
/// marker other than `SchemaV1` does the same. `StoreMetaRecord.snapshotVersion`
/// is compared with `ProgressSnapshot.currentVersion` even when that marker
/// is missing, and a newer value is refused before the container opens.
enum StoredSchema {
    private static let knownEntities: Set<String> = [
        "ReviewCardRecord",
        "LessonProgressRecord",
        "StreakRecord",
        "SettingsRecord",
        "StoreMetaRecord",
        "ActiveSessionRecord",
        "CompletedSessionRecord",
    ]

    /// Persistent-history rows SwiftData writes beside the model entities.
    private static let systemEntities: Set<String> = [
        "CHANGE",
        "TRANSACTION",
        "TRANSACTIONSTRING",
    ]

    static func refuseIfNewer(at url: URL) throws {
        let snapshot = try read(at: url)
        let currentSchema = SchemaV1.versionIdentifier
        for identifier in snapshot.versionIdentifiers where !identifier.isEmpty {
            guard let version = schemaVersion(identifier), version == currentSchema else {
                throw ProgressPersistenceError.newerSchema(
                    "Stored schema marker \(identifier) is not \(currentSchema)."
                )
            }
        }
        let unknown = snapshot.entities.filter { !isKnownEntity($0) && !isSystemEntity($0) }
        if !unknown.isEmpty {
            throw ProgressPersistenceError.newerSchema(
                "Stored entity \(unknown.sorted().joined(separator: ", ")) is not in schema \(currentSchema)."
            )
        }
        if let stored = snapshot.snapshotVersion, stored > ProgressSnapshot.currentVersion {
            throw ProgressPersistenceError.newerSnapshot(stored)
        }
    }

    private static func isKnownEntity(_ name: String) -> Bool {
        if knownEntities.contains(name) { return true }
        return knownEntities.contains { name.hasSuffix(".\($0)") }
    }

    private static func isSystemEntity(_ name: String) -> Bool {
        systemEntities.contains(name) || systemEntities.contains { name.hasSuffix(".\($0)") }
    }

    private static func read(at url: URL) throws -> (versionIdentifiers: [String], entities: [String], snapshotVersion: Int?) {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("pashto-schema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.copyItem(
                at: source,
                to: scratch.appendingPathComponent(url.lastPathComponent + suffix)
            )
        }
        let copy = scratch.appendingPathComponent(url.lastPathComponent)
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(copy.path, &database, flags, nil) == SQLITE_OK, let database else {
            throw ProgressPersistenceError.failedToOpen("The progress store could not be read.")
        }
        defer { sqlite3_close(database) }
        return (
            versionIdentifiers(in: database),
            column("SELECT Z_NAME FROM Z_PRIMARYKEY", in: database),
            snapshotVersion(in: database)
        )
    }

    private static func versionIdentifiers(in database: OpaquePointer) -> [String] {
        let rows = blobs("SELECT Z_PLIST FROM Z_METADATA", in: database)
        var identifiers: [String] = []
        for data in rows {
            guard
                let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
                let plist = object as? [String: Any],
                let stored = plist["NSStoreModelVersionIdentifiers"] as? [String]
            else { continue }
            identifiers.append(contentsOf: stored)
        }
        return identifiers
    }

    /// The integer on `StoreMetaRecord`. Nil when the file has no such row.
    private static func snapshotVersion(in database: OpaquePointer) -> Int? {
        let tables = column("SELECT name FROM sqlite_master WHERE type = 'table'", in: database)
        guard let table = tables.first(where: { $0.range(of: "STOREMETARECORD", options: .caseInsensitive) != nil }),
              isSafeIdentifier(table)
        else { return nil }
        let names = column("SELECT name FROM pragma_table_info('\(table)')", in: database)
        guard let columnName = names.first(where: { $0.range(of: "SNAPSHOTVERSION", options: .caseInsensitive) != nil }),
              isSafeIdentifier(columnName)
        else { return nil }
        var statement: OpaquePointer?
        let sql = "SELECT \(columnName) FROM \(table)"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        var newest: Int?
        while sqlite3_step(statement) == SQLITE_ROW {
            if sqlite3_column_type(statement, 0) == SQLITE_NULL { continue }
            let value = Int(sqlite3_column_int64(statement, 0))
            newest = max(newest ?? value, value)
        }
        return newest
    }

    private static func isSafeIdentifier(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func schemaVersion(_ identifier: String) -> Schema.Version? {
        let parts = identifier.split(separator: ".")
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2])
        else { return nil }
        return Schema.Version(major, minor, patch)
    }

    private static func column(_ sql: String, in database: OpaquePointer) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let cString = sqlite3_column_text(statement, 0) else { continue }
            values.append(String(cString: cString))
        }
        return values
    }

    private static func blobs(_ sql: String, in database: OpaquePointer) -> [Data] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        var values: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let blob = sqlite3_column_blob(statement, 0) else { continue }
            let count = Int(sqlite3_column_bytes(statement, 0))
            values.append(Data(bytes: blob, count: count))
        }
        return values
    }
}
