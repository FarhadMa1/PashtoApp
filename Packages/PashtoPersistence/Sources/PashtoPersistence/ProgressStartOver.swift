import Foundation
import PashtoCore
import SwiftData

/// What a fresh store keeps from the file that was moved aside.
///
/// The daily goal and transliteration are the stored values. `placementTakenDay`
/// is nil, matching `resetAll`, so the placement test can be offered again.
/// `contentVersion` is the version stored with the progress. When the file
/// had no meta row, it is the version installed in this build.
public struct CarriedProgress: Equatable, Sendable {
    public let settings: UserSettings
    public let contentVersion: String
    public let backupDirectory: URL
    public let movedFiles: [URL]

    public init(
        settings: UserSettings,
        contentVersion: String,
        backupDirectory: URL,
        movedFiles: [URL]
    ) {
        self.settings = settings
        self.contentVersion = contentVersion
        self.backupDirectory = backupDirectory
        self.movedFiles = movedFiles
    }
}

/// The container for the fresh store, and the values written into it.
public struct RestartedStore: Sendable {
    public let container: ModelContainer
    public let carried: CarriedProgress

    public init(container: ModelContainer, carried: CarriedProgress) {
        self.container = container
        self.carried = carried
    }
}

/// Replaces a progress store the learner has chosen to start over.
///
/// The old file is moved aside first. `make` creates the fresh store, and
/// `write` records the carried settings and content version. When either
/// throws, the files that appeared at the original path are removed and the
/// backup is moved back. The backup bytes are not deleted.
public enum ProgressStartOver {
    @MainActor
    public static func replace(
        storeAt url: URL,
        timestamp: String,
        installedContentVersion: String,
        make: (URL) throws -> ModelContainer,
        write: (ModelContainer, CarriedProgress) async throws -> Void,
        beforeWrite: (() throws -> Void)? = nil
    ) async throws -> RestartedStore {
        let preserved = try ProgressStoreRestart.moveAside(storeAt: url, timestamp: timestamp)
        let carried = CarriedProgress(
            settings: settingsForNewStore(preserved.settings),
            contentVersion: preserved.contentVersion ?? installedContentVersion,
            backupDirectory: preserved.backupDirectory,
            movedFiles: preserved.movedFiles
        )
        // Held outside the do block so a failure can release the container
        // before the new files are removed.
        var created: ModelContainer?
        do {
            let container = try make(url)
            created = container
            if let beforeWrite {
                try beforeWrite()
            }
            try await write(container, carried)
            return RestartedStore(container: container, carried: carried)
        } catch {
            created = nil
            ProgressStoreRestart.undoReplacement(storeAt: url, preserved: preserved)
            throw error
        }
    }

    /// Goal and transliteration stay. The placement day does not.
    private static func settingsForNewStore(_ settings: UserSettings?) -> UserSettings {
        let source = settings ?? .initial
        return UserSettings(
            dailyGoal: source.dailyGoal,
            showTransliteration: source.showTransliteration,
            placementTakenDay: nil
        )
    }
}
