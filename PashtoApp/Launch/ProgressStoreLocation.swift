import Foundation

/// Where the on-device progress file lives.
///
/// Application Support, not a shared container. The file is `Progress.store`.
/// Backups from Start over are a `Backups` directory beside it.
enum ProgressStoreLocation {
    static func url(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("PashtoProgress", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Progress.store")
    }
}
