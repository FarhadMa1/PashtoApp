import Foundation
import Testing
import PashtoCore
@testable import PashtoPersistence

/// The store checked in before the first TestFlight build.
/// ADR 0001 records the macOS run that wrote it. This test opens that file.
struct SchemaV1FixtureTests {
    @Test func checkedInStoreOpensAsSchemaV1() async throws {
        let bundled = try fixtureStore()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-v1-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("SchemaV1.store")
        try FileManager.default.copyItem(at: bundled, to: url)
        let loaded = try await readStore(at: url, contentVersion: "not-the-stored-version")
        #expect(loaded == ProgressSnapshot.empty(contentVersion: "2026.11.0"))
        #expect(loaded.snapshotVersion == ProgressSnapshot.currentVersion)
    }
}

private func fixtureStore() throws -> URL {
    if let url = Bundle.module.url(
        forResource: "SchemaV1",
        withExtension: "store",
        subdirectory: "Fixtures"
    ) {
        return url
    }
    let candidates = [
        Bundle.module.bundleURL.appendingPathComponent("Fixtures/SchemaV1.store"),
        Bundle.module.bundleURL.appendingPathComponent("SchemaV1.store"),
    ]
    if let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
        return url
    }
    throw ProgressPersistenceError.failedToOpen("SchemaV1.store is not in the test bundle.")
}
