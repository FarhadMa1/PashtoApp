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
///
/// A missing or undecodable `content.json` or `release-units.json` uses that
/// same storage error and does not open the home. Start over is hidden in
/// that case: moving the progress file aside would not restore the course.
/// Try again reads the bundle again.
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

    private(set) var phase: Phase
    /// The capped review queue from the last Start review. Nil until then.
    private(set) var startedReview: ShortCappedReview?
    /// The course the app was given, and the ids from `release-units.json`.
    ///
    /// Both stay empty when those files are missing or cannot be decoded, and
    /// the storage error is shown. The session is never built from the whole
    /// course in their place.
    private var course: ContentBundle?
    private var releasedUnitIDs: [UnitID] = []
    private var lessonCache = ReleasedLessonCache()
    /// VoiceOver at the last refresh. Letter lessons change tasks when it flips.
    private var voiceOverRunning: Bool
    private var lessonLaunch = RootLessonSession()
    private let appStoreID: String
    private var storeURL: URL?
    private let clock: DayClock<SystemDateProvider>
    private var container: ModelContainer?
    private var progressStore: SwiftDataProgressStore?
    private var snapshot: ProgressSnapshot?
    private var isOpening = false
    /// Start over only helps a store that will not open. It stays hidden when
    /// the bundled course itself could not be read.
    private(set) var offersStartOver = false

    var isAppStoreButtonVisible: Bool {
        showsAppStoreButton(appStoreID: appStoreID)
    }

    var isReviewing: Bool {
        startedReview != nil
    }

    /// The lesson quiz on screen. Nil when the learner is on the home.
    var activeLesson: LessonSession? {
        lessonLaunch.isActive ? lessonLaunch.session : nil
    }

    /// Items the open quiz may draw. Released units only.
    var lessonItems: [ContentItem] {
        lessonLaunch.items
    }

    /// Lessons the home can start. Empty when the release list is empty.
    ///
    /// A lesson that would open with no questions is left out. The list is
    /// cached. It is rebuilt when progress changes and when VoiceOver turns
    /// on or off, because VoiceOver changes which tasks a lesson is given.
    private(set) var releasedLessons: [ReleasedLesson] = []

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
        self.voiceOverRunning = UIAccessibility.isVoiceOverRunning
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        self.clock = DayClock(provider: SystemDateProvider(), calendar: calendar)
        if prepareCourse() != nil {
            refreshReleasedLessons()
        }
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
        guard let version = prepareCourse() else { return }
        do {
            let url = try resolvedURL()
            let container = try ProgressContainer.make(at: url)
            let store = SwiftDataProgressStore(
                modelContainer: container,
                contentVersion: version
            )
            let snapshot = try await store.load()
            self.container = container
            self.progressStore = store
            self.snapshot = snapshot
            refreshReleasedLessons()
            phase = phase(for: progressScreen(streak: snapshot.streak, on: clock.today))
        } catch {
            container = nil
            progressStore = nil
            snapshot = nil
            refreshReleasedLessons()
            phase = phase(for: progressScreen(for: progressOpenFailure(for: error)))
        }
    }

    func tryAgain() async {
        guard phase == .storageError else { return }
        await loadProgress()
    }

    func confirmStartOver() async {
        guard phase == .storageError, !isOpening else { return }
        guard let version = prepareCourse() else { return }
        isOpening = true
        defer { isOpening = false }
        container = nil
        progressStore = nil
        snapshot = nil
        refreshReleasedLessons()
        do {
            let url = try resolvedURL()
            let restarted = try await ProgressStartOver.replace(
                storeAt: url,
                timestamp: Self.backupTimestamp(Date()),
                installedContentVersion: version,
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
            refreshReleasedLessons()
            phase = phase(for: progressScreen(streak: snapshot.streak, on: clock.today))
        } catch {
            container = nil
            progressStore = nil
            snapshot = nil
            refreshReleasedLessons()
            phase = .storageError
        }
    }

    /// Selects today's capped review queue and leaves Welcome back.
    ///
    /// The queue is the one `shortCappedReview` already returns. This does not
    /// open a lesson quiz. Every stored card id is treated as known, because
    /// this queue is not drawn from the course. Otherwise it would be empty.
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

    /// Rebuilds the home list when VoiceOver turns on or off.
    ///
    /// `RootView` forwards `accessibilityVoiceOverEnabled`, the SwiftUI
    /// equivalent of `UIAccessibility.voiceOverStatusDidChangeNotification`.
    /// A lesson that loses every task under the new setting drops off the home.
    func voiceOverChanged(to enabled: Bool) {
        guard enabled != voiceOverRunning else { return }
        voiceOverRunning = enabled
        refreshReleasedLessons()
    }

    /// Opens a quiz for one released lesson. An unlisted lesson does not start.
    func startLesson(_ lessonID: LessonID) {
        voiceOverChanged(to: UIAccessibility.isVoiceOverRunning)
        guard phase == .ready, let course else { return }
        var rng = SystemRandomNumberGenerator()
        var launch = lessonLaunch
        launch.start(
            lessonID: lessonID,
            in: course,
            seenLessonIDs: snapshot?.lessonProgress.map(\.lessonID) ?? [],
            releasedUnitIDs: releasedUnitIDs,
            showsPronunciation: snapshot?.settings.showTransliteration ?? true,
            voiceOver: voiceOverRunning,
            using: &rng
        )
        lessonLaunch = launch
    }

    /// Finishing or leaving the quiz. The home is shown again.
    func endLesson() {
        var launch = lessonLaunch
        launch.end()
        lessonLaunch = launch
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

    /// The bundled content version, or nil when the storage error is already showing.
    private func prepareCourse() -> String? {
        let load = Self.bundledCourse(in: .main)
        switch load {
        case .ready(let bundled):
            course = bundled.bundle
            releasedUnitIDs = bundled.releasedUnitIDs
            offersStartOver = true
            return bundled.installedContentVersion
        case .unavailable:
            course = nil
            releasedUnitIDs = []
            offersStartOver = false
            refreshReleasedLessons()
            if let screen = load.blockingScreen {
                phase = phase(for: screen)
            }
            return nil
        }
    }

    private func refreshReleasedLessons() {
        lessonCache.refresh(
            course: course,
            releasedUnitIDs: releasedUnitIDs,
            seenLessonIDs: snapshot?.lessonProgress.map(\.lessonID) ?? [],
            showsPronunciation: snapshot?.settings.showTransliteration ?? true,
            voiceOver: voiceOverRunning
        )
        let lessons = lessonCache.lessons
        if lessons != releasedLessons {
            releasedLessons = lessons
        }
    }

    private static func bundledCourse(in bundle: Bundle) -> BundledCourseLoad {
        BundledCourseLoader.load(
            content: bundledData(resource: "content", in: bundle),
            releaseUnits: bundledData(resource: "release-units", in: bundle)
        )
    }

    /// Nil when the file is missing or cannot be read. Decoding is separate.
    private static func bundledData(resource: String, in bundle: Bundle) -> Data? {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
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
