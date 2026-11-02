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
/// Entity names come from `NSStoreModelVersionHashes` in the store metadata.
/// That dictionary is the `Z_PLIST` blob in `Z_METADATA`, read with SQLite in
/// query-only mode from a private copy. `metadataForPersistentStore` is not
/// used: on this toolchain it rewrites the `-shm` sidecar of the file it
/// opens. The copy keeps that write, if any, off the caller's file. A key
/// that is not one of `SchemaV1`'s entities is a newer store.
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
        // Temporary trace for the newer-schema byte check. Removed once the
        // open path is fixed. Reading these bytes does not open SQLite.
        diag("phase=before-open original=\(fileStamp(url))")
        let copy = try copiedStore(at: url)
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        diag("phase=after-copy original=\(fileStamp(url)) copy=\(fileStamp(copy))")
        let database: OpaquePointer
        do {
            database = try openReadOnly(copy)
            diag("phase=after-sqlite-open original=\(fileStamp(url)) copy=\(fileStamp(copy))")
        } catch {
            diag("phase=sqlite-open-threw original=\(fileStamp(url)) copy=\(fileStamp(copy))")
            throw error
        }
        defer { sqlite3_close(database) }
        let metadata: [String: Any]
        do {
            metadata = try storeMetadata(in: database)
            diag("phase=after-metadata original=\(fileStamp(url)) copy=\(fileStamp(copy))")
        } catch {
            diag("phase=metadata-threw original=\(fileStamp(url)) copy=\(fileStamp(copy))")
            throw error
        }
        let snapshot = (
            versionIdentifiers(in: metadata),
            try entityNames(in: metadata),
            snapshotVersion(in: database)
        )
        diag("phase=after-check original=\(fileStamp(url)) copy=\(fileStamp(copy))")
        return snapshot
    }

    private static func diag(_ message: String) {
        FileHandle.standardError.write(Data("SCHEMA-DIAG \(message)\n".utf8))
    }

    /// Size and checksum of the main file and both sidecars. `absent` means
    /// that path does not exist.
    private static func fileStamp(_ url: URL) -> String {
        ["", "-wal", "-shm"].map { suffix in
            let label = suffix.isEmpty ? "main" : String(suffix.dropFirst())
            let path = url.path + suffix
            guard FileManager.default.fileExists(atPath: path),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path))
            else { return "\(label)=absent" }
            return "\(label)=\(data.count):\(fnv(data))"
        }.joined(separator: ",")
    }

    private static func fnv(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
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

    /// `Z_METADATA.Z_PLIST` is the keyed archive Core Data stores beside the rows.
    /// The connection is already query-only, so this select cannot checkpoint
    /// or replace a sidecar.
    private static func storeMetadata(in database: OpaquePointer) throws -> [String: Any] {
        let tables = column("SELECT name FROM sqlite_master WHERE type = 'table'", in: database)
        guard let table = tables.first(where: { $0.caseInsensitiveCompare("Z_METADATA") == .orderedSame }),
              isSafeIdentifier(table)
        else {
            throw ProgressPersistenceError.failedToOpen("The progress store has no metadata table.")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT Z_PLIST FROM \(table) LIMIT 1", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw ProgressPersistenceError.failedToOpen(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw ProgressPersistenceError.failedToOpen("The progress store has no metadata row.")
        }
        guard sqlite3_column_type(statement, 0) != SQLITE_NULL, let blob = sqlite3_column_blob(statement, 0) else {
            throw ProgressPersistenceError.failedToOpen("The progress store metadata is empty.")
        }
        let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 0)))
        return try metadataDictionary(from: data)
    }

    private static func metadataDictionary(from data: Data) throws -> [String: Any] {
        let classes: [AnyClass] = [
            NSDictionary.self, NSArray.self, NSString.self, NSNumber.self, NSData.self, NSDate.self, NSSet.self,
        ]
        if let object = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data),
           let metadata = object as? [String: Any] {
            return metadata
        }
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        guard let metadata = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [String: Any] else {
            throw ProgressPersistenceError.failedToOpen("The progress store metadata could not be read.")
        }
        return metadata
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
        // query_only rejects a write, including a checkpoint, on this connection.
        // A file that is not a database fails here and is closed before return.
        guard sqlite3_exec(database, "PRAGMA query_only = ON", nil, nil, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(database))
            sqlite3_close(database)
            throw ProgressPersistenceError.failedToOpen(message)
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
