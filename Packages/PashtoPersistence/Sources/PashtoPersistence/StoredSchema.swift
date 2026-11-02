import Foundation
import SwiftData
import SQLite3

/// Reads a SwiftData file without opening it in `ModelContainer`.
///
/// On the macOS 15 / Xcode 16 toolchain, opening a store from a schema this
/// plan does not contain does not throw. It replaces the file. This check
/// runs first, read-only, and leaves the file alone.
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

    static func refuseIfNewer(at url: URL) throws {
        let snapshot = try read(at: url)
        let current = SchemaV1.versionIdentifier
        if let newer = snapshot.versions.first(where: { $0 > current }) {
            throw ProgressPersistenceError.newerSchema(
                "Stored schema version \(newer) is newer than \(current)."
            )
        }
        let unknown = snapshot.entities.filter { !isKnownEntity($0) }
        if !snapshot.entities.isEmpty, snapshot.entities.allSatisfy({ !isKnownEntity($0) }) {
            throw ProgressPersistenceError.newerSchema(
                "Stored entities \(unknown.sorted().joined(separator: ", ")) are not in schema \(current)."
            )
        }
    }

    private static func isKnownEntity(_ name: String) -> Bool {
        if knownEntities.contains(name) { return true }
        return knownEntities.contains { name.hasSuffix(".\($0)") }
    }

    private static func read(at url: URL) throws -> (versions: [Schema.Version], entities: [String]) {
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
        let versions = versionIdentifiers(in: database).compactMap(schemaVersion)
        let entities = column("SELECT Z_NAME FROM Z_PRIMARYKEY", in: database)
        return (versions, entities)
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
