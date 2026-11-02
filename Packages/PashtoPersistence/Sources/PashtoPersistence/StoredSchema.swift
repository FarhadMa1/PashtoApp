import CoreData
import Foundation
import PashtoCore
import SwiftData
import SQLite3

/// Reads a SwiftData file without opening it in `ModelContainer`.
///
/// On the macOS 15 / Xcode 16 toolchain, opening a store from a schema this
/// plan does not contain does not throw. It replaces the file. This check
/// runs first and leaves the original file alone.
///
/// Entity names come from `NSStoreModelVersionHashes` in the store metadata
/// (`NSPersistentStoreCoordinator.metadataForPersistentStore`). That dictionary
/// lists the model entities only, not Core Data's persistent-history tables.
/// A key that is not one of `SchemaV1`'s entities is a newer store.
///
/// `StoreMetaRecord.snapshotVersion` is a row, not store metadata. It is read
/// from a copy of the file and compared with `ProgressSnapshot.currentVersion`.
/// A newer value is refused even when the SwiftData version marker is missing.
enum StoredSchema {
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
        let unknown = snapshot.entityNames.filter { !modelEntityNames.contains($0) }
        if !unknown.isEmpty {
            throw ProgressPersistenceError.newerSchema(
                "Stored entity \(unknown.sorted().joined(separator: ", ")) is not in schema \(currentSchema)."
            )
        }
        if let stored = snapshot.snapshotVersion, stored > ProgressSnapshot.currentVersion {
            throw ProgressPersistenceError.newerSnapshot(stored)
        }
    }

    private static var modelEntityNames: Set<String> {
        Set(Schema(versionedSchema: SchemaV1.self).entities.map(\.name))
    }

    private static func read(at url: URL) throws -> (versionIdentifiers: [String], entityNames: [String], snapshotVersion: Int?) {
        let copy = try copiedStore(at: url)
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let metadata = try storeMetadata(at: copy)
        let database = try openReadOnly(copy)
        defer { sqlite3_close(database) }
        return (
            versionIdentifiers(in: metadata),
            try entityNames(in: metadata),
            snapshotVersion(in: database)
        )
    }

    /// A copy so the metadata read and the snapshot query cannot touch the file
    /// the caller asked to open.
    private static func copiedStore(at url: URL) throws -> URL {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("pashto-schema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.copyItem(
                at: source,
                to: scratch.appendingPathComponent(url.lastPathComponent + suffix)
            )
        }
        return scratch.appendingPathComponent(url.lastPathComponent)
    }

    private static func storeMetadata(at url: URL) throws -> [String: Any] {
        do {
            return try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType,
                at: url,
                options: nil
            )
        } catch {
            throw ProgressPersistenceError.failedToOpen("\(error)")
        }
    }

    private static func versionIdentifiers(in metadata: [String: Any]) -> [String] {
        if let values = metadata[NSStoreModelVersionIdentifiersKey] as? [String] {
            return values
        }
        if let values = metadata[NSStoreModelVersionIdentifiersKey] as? [Any] {
            return values.compactMap { $0 as? String }
        }
        return []
    }

    private static func entityNames(in metadata: [String: Any]) throws -> [String] {
        if let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Any] {
            return Array(hashes.keys)
        }
        if let hashes = metadata[NSStoreModelVersionHashesKey] as? [AnyHashable: Any] {
            return hashes.keys.compactMap { $0 as? String }
        }
        throw ProgressPersistenceError.newerSchema("The store has no model hashes.")
    }

    private static func openReadOnly(_ url: URL) throws -> OpaquePointer {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            throw ProgressPersistenceError.failedToOpen("The progress store could not be read.")
        }
        return database
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
}
