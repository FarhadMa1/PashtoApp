import Foundation
import PashtoCore
import PashtoPersistence
import SwiftData
import UIKit

/// Opens progress and chooses Update needed, the storage error, Welcome back, or the app.
///
/// A newer store is only shown. Start over runs only from the storage error.
/// It moves the file aside, then writes the goal, transliteration, and content
/// version into a fresh store. The placement day is cleared. A failure removes
/// the fresh file and moves the backup back.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case loading
        case updateNeeded
        case storageError
        case welcomeBack
        case ready
    }

    /// Content is not in the app bundle yet. The store keeps this until a bundle version is written.
    static let installedContentVersion = "unbundled"

    private(set) var phase: Phase
    /// The capped review queue from the last Start review. Nil until then.
    private(set) var startedReview: ShortCappedReview?
    private let appStoreID: String
    private var storeURL: URL?
    private let clock: DayClock<SystemDateProvider>
    private var container: ModelContainer?
    private var progressStore: SwiftDataProgressStore?
    private var snapshot: ProgressSnapshot?
    private var isOpening = false

    var isAppStoreButtonVisible: Bool {
        showsAppStoreButton(appStoreID: appStoreID)
    }

    var isReviewing: Bool {
        startedReview != nil
    }

    /// `ProgressScreen` is the choice in PashtoCore. `Phase` also has loading,
    /// which that choice does not.
    private func phase(for screen: ProgressScreen) -> Phase {
        switch screen {
        case .updateNeeded: .updateNeeded
        case .storageError: .storageError
        case .welcomeBack: .welcomeBack
        case .ready: .ready
        }
    }

    init(storeURL: URL?, appStoreID: String, phase: Phase) {
        self.storeURL = storeURL
        self.appStoreID = appStoreID
        self.phase = phase
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        self.clock = DayClock(provider: SystemDateProvider(), calendar: calendar)
    }

    static let appStoreIDKey = "AppStoreID"

    static func live() -> AppModel {
        let url = try? ProgressStoreLocation.url()
        let identifier = Bundle.main.object(forInfoDictionaryKey: appStoreIDKey) as? String ?? ""
        return AppModel(
            storeURL: url,
            appStoreID: identifier,
            phase: url == nil ? .storageError : .loading
        )
    }

    func loadProgress() async {
        guard !isOpening else { return }
        isOpening = true
        defer { isOpening = false }
        do {
            let url = try resolvedURL()
            let container = try ProgressContainer.make(at: url)
            let store = SwiftDataProgressStore(
                modelContainer: container,
                contentVersion: Self.installedContentVersion
            )
            let snapshot = try await store.load()
            self.container = container
            self.progressStore = store
            self.snapshot = snapshot
            phase = phase(for: progressScreen(streak: snapshot.streak, on: clock.today))
        } catch {
            container = nil
            progressStore = nil
            snapshot = nil
            phase = phase(for: progressScreen(for: progressOpenFailure(for: error)))
        }
    }

    func tryAgain() async {
        guard phase == .storageError else { return }
        await loadProgress()
    }

    func confirmStartOver() async {
        guard phase == .storageError, !isOpening else { return }
        isOpening = true
        defer { isOpening = false }
        container = nil
        progressStore = nil
        snapshot = nil
        do {
            let url = try resolvedURL()
            let restarted = try await ProgressStartOver.replace(
                storeAt: url,
                timestamp: Self.backupTimestamp(Date()),
                installedContentVersion: Self.installedContentVersion,
                make: { url in
                    try ProgressContainer.make(at: url)
                },
                write: { container, carried in
                    let store = SwiftDataProgressStore(
                        modelContainer: container,
                        contentVersion: carried.contentVersion
                    )
                    try await store.updateSettings(carried.settings)
                }
            )
            let store = SwiftDataProgressStore(
                modelContainer: restarted.container,
                contentVersion: restarted.carried.contentVersion
            )
            let snapshot = try await store.load()
            self.container = restarted.container
            self.progressStore = store
            self.snapshot = snapshot
            phase = phase(for: progressScreen(streak: snapshot.streak, on: clock.today))
        } catch {
            container = nil
            progressStore = nil
            snapshot = nil
            phase = .storageError
        }
    }

    /// Selects today's capped review queue and leaves Welcome back.
    ///
    /// The quiz screen is not in this revision. The queue is the one
    /// `shortCappedReview` already returns. Content is not bundled yet, so
    /// every stored card id is treated as known. Otherwise the queue would
    /// be empty.
    func startReview() {
        guard phase == .welcomeBack, let snapshot else {
            phase = .ready
            return
        }
        let today = clock.today
        let known = Set(snapshot.cards.map(\.itemID))
        startedReview = shortCappedReview(
            cards: snapshot.cards,
            knownItemIDs: known,
            goal: snapshot.settings.dailyGoal,
            newItemsShownToday: newItemsShown(on: today, in: snapshot.cards),
            on: today
        )
        phase = .ready
    }

    func openAppStore() {
        guard phase == .updateNeeded, let id = appStoreIDForListing(appStoreID) else {
            return
        }
        guard let url = URL(string: "https://apps.apple.com/app/id\(id)") else {
            return
        }
        UIApplication.shared.open(url)
    }

    private func resolvedURL() throws -> URL {
        if let storeURL { return storeURL }
        let url = try ProgressStoreLocation.url()
        storeURL = url
        return url
    }

    /// UTC, so the backup folder name does not depend on the locale.
    private static func backupTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}
