import Foundation
import SQLite3
import Testing
import PashtoCore
@testable import PashtoPersistence

/// Writes one Schema V1 store when `PASHTO_SCHEMA_V1_STORE` is set.
///
/// The writes are the same as `makeV1File`: `ProgressContainer` opens
/// `SchemaV1`, then `updateSettings(.initial)` stores the content version
/// `2026.11.0`. The write-ahead log is checkpointed into the main file.
/// Without the variable this test does not write. It does not replace the
/// checked-in fixture. ADR 0001 is the record of the run that produced it.
struct SchemaV1StoreGenerator {
    @Test func writesSchemaV1StoreWhenRequested() async throws {
        let raw = ProcessInfo.processInfo.environment["PASHTO_SCHEMA_V1_STORE"] ?? ""
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }

        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-v1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("SchemaV1.store")
        try await writeStore(at: url, contentVersion: "2026.11.0") { store in
            try await store.updateSettings(.initial)
        }
        try checkpointMainFile(at: url)
        let copy = directory.appendingPathComponent("reopen.store")
        try FileManager.default.copyItem(at: url, to: copy)
        let loaded = try await readStore(at: copy, contentVersion: "not-the-stored-version")
        #expect(loaded == ProgressSnapshot.empty(contentVersion: "2026.11.0"))
        let header = try Data(contentsOf: url).prefix(16)
        #expect(header == Data("SQLite format 3\0".utf8))
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        try FileManager.default.copyItem(at: url, to: output)
        #expect(FileManager.default.fileExists(atPath: output.path + "-wal") == false)
        #expect(FileManager.default.fileExists(atPath: output.path + "-shm") == false)
    }
}

/// Folds the write-ahead log into the main database and deletes the sidecars.
/// A later open of the main file alone is the file that can be checked in.
private func checkpointMainFile(at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        throw ProgressPersistenceError.failedToOpen("The V1 store could not be checkpointed.")
    }
    defer { sqlite3_close(database) }
    var error: UnsafeMutablePointer<CChar>?
    let code = sqlite3_exec(database, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, &error)
    guard code == SQLITE_OK else {
        let message = error.map { String(cString: $0) } ?? "sqlite \(code)"
        sqlite3_free(error)
        throw ProgressPersistenceError.failedToOpen(message)
    }
    for suffix in ["-wal", "-shm"] {
        let sidecar = URL(fileURLWithPath: url.path + suffix)
        guard FileManager.default.fileExists(atPath: sidecar.path) else { continue }
        if suffix == "-wal" {
            let size = try FileManager.default.attributesOfItem(atPath: sidecar.path)[.size] as? NSNumber
            if (size?.intValue ?? 0) > 0 {
                throw ProgressPersistenceError.failedToOpen("The write-ahead log was not emptied.")
            }
        }
        try FileManager.default.removeItem(at: sidecar)
    }
}
