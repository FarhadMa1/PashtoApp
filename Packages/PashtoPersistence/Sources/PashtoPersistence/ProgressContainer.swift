import Foundation
import SwiftData

/// Opens the on-device progress store.
///
/// A file this build does not understand throws. This type never deletes a
/// store it cannot open, and it never creates a replacement file in that case.
/// The screen that offers "Try again" and then "Start fresh" is not here.
public enum ProgressContainer {
    /// The store named Progress.
    ///
    /// Pass `inMemory: true` for a test or a preview. In-memory stores that
    /// share a name share rows. Tests that need an empty store use
    /// `make(name:inMemory:)` with a new name. `cloudKitDatabase` is `.none`:
    /// progress stays on the device.
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        try make(name: "Progress", inMemory: inMemory, url: nil)
    }

    /// An isolated store. `name` is the identity of an in-memory store.
    public static func make(name: String, inMemory: Bool) throws -> ModelContainer {
        try make(name: name, inMemory: inMemory, url: nil)
    }

    /// A file-backed store. `url` is the SwiftData file, including its name.
    /// The parent directory must already exist.
    public static func make(at url: URL) throws -> ModelContainer {
        try make(name: "Progress", inMemory: false, url: url)
    }

    private static func make(name: String, inMemory: Bool, url: URL?) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(
                name,
                schema: schema,
                url: url,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                name,
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                allowsSave: true,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
        }
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: ProgressMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            throw openError(error)
        }
    }

    /// SwiftData's "unknown model version" is a store this plan does not contain.
    /// That includes a schema newer than V1. Other open failures stay separate
    /// so a full disk is not reported as a newer app.
    private static func openError(_ error: Error) -> ProgressPersistenceError {
        let nsError = error as NSError
        let text = "\(error) \(nsError.localizedDescription) \(nsError.userInfo)"
        if text.localizedCaseInsensitiveContains("unknown model version") {
            return .newerSchema(text)
        }
        return .failedToOpen(text)
    }
}
