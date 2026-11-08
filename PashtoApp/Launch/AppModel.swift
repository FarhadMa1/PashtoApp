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
/// Try again reads the bundle again. When the course is still missing, the
/// error screen gives a shake, or a fade when Reduce Motion is on.
///
/// Each answer is saved on the active lesson. A failed answer stays in memory:
/// the quiz continues, and that save is tried again on the next answer and
/// when the app goes to the background. That background write asks for time
/// to finish. A retry still waiting when the lesson finishes is dropped, so
/// the finished lesson is not put back in progress. The storage error is shown
/// when the finished lesson still cannot be saved, when progress cannot be
/// loaded, and when a read fails while a lesson is opening. Try again retries
/// a failed finish and keeps the answers. A failed read while opening reloads,
/// and Start over stays hidden, as it does for a failed save and a missing
/// course. Start over is offered when the progress store cannot be opened.
/// A second tap while a lesson is opening is ignored. Opening a lesson from
/// its home row continues a saved lesson on the day it started or the next
/// day, unless VoiceOver would now skip a question that is still waiting.
/// Startup runs the progress reconciler. The home list follows `snapshot`.
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
    /// Decoded once at startup. Try again replaces it only when the bytes change.
    private var decodedCourse: BundledCourseDecode?
    private var home = ReleasedLessonList()
    /// The lesson on screen. Its session id is what a finish is allowed to close.
    private var openLesson = OpenLesson()
    private let appStoreID: String
    private var storeURL: URL?
    private let clock: DayClock<DateProviderBox>
    private var container: ModelContainer?
    private var progressStore: SwiftDataProgressStore?
    /// Keeps a background save alive until it lands. Not part of the screen.
    @ObservationIgnored
    private let backgroundSave = BackgroundLessonSave()
    /// The home list reads this in `didSet`, so a finished lesson cannot leave it stale.
    private var snapshot: ProgressSnapshot? {
        didSet { refreshReleasedLessons() }
    }
    private let lessonOpen = LessonOpening()
    /// Increments when Try again still cannot read the course. The error screen reacts.
    private(set) var courseStillMissingToken = 0
    /// True while Try again is still working. The error screen shows progress and disables its buttons.
    private(set) var isRetrying = false
    /// From-values for the home animation after a finish. The home consumes this once.
    private var homeMotion = HomeMotionCue()
    /// The finish the home has not played yet. Nil after it is consumed, and nil on a relaunch.
    private(set) var pendingHomeMotion: PendingHomeMotion?
    /// Rescue and freeze events still waiting. The day on each one is already stored.
    private var streakMotion = StreakMotionCue()
    /// What the home has not claimed. Empty after the claim, and empty on a relaunch.
    private(set) var pendingStreakEvents: [StreakEventID] = []
    /// Why the storage error is showing. Nil on every other screen.
    ///
    /// Start over is offered only when the progress store could not be opened.
    /// A missing course, a failed lesson save, and a failed read while opening
    /// a lesson keep that button hidden.
    private var storageErrorReason: StorageErrorReason?

    /// Start over only helps a store that will not open.
    var offersStartOver: Bool {
        guard let storageErrorReason else { return false }
        return storageErrorActions(for: storageErrorReason).showsStartOver
    }

    var isAppStoreButtonVisible: Bool {
        showsAppStoreButton(appStoreID: appStoreID)
    }

    var isReviewing: Bool {
        startedReview != nil
    }

    /// Counted days the home shows. A gap the freezes cannot cover is 0.
    /// The stored streak is left as it is. The home does not add a caption.
    var streakCount: Int {
        guard let snapshot else { return 0 }
        return displayedStreakCount(snapshot.streak, on: clock.today)
    }

    /// New items introduced today, against `goalTotal`.
    var goalDone: Int {
        guard let snapshot else { return 0 }
        return newItemsShown(on: clock.today, in: snapshot.cards)
    }

    /// The stored new-item limit: 5, 10, or 15.
    var goalTotal: Int {
        snapshot?.settings.dailyGoal.newItemLimit ?? DailyGoal.regular.newItemLimit
    }

    /// Lessons already finished or skipped by placement. The path draws these.
    var finishedLessonIDs: Set<LessonID> {
        Set(snapshot?.lessonProgress.map(\.lessonID) ?? [])
    }

    /// The lesson quiz on screen. Nil when the learner is on the home.
    var activeLesson: LessonSession? {
        openLesson.session
    }

    /// Items the open quiz may draw. Released units only.
    var lessonItems: [ContentItem] {
        openLesson.items
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

    init(
        storeURL: URL?,
        appStoreID: String,
        phase: Phase,
        dateProvider: any DateProvider = SystemDateProvider()
    ) {
        self.storeURL = storeURL
        self.appStoreID = appStoreID
        self.phase = phase
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        self.clock = DayClock(provider: DateProviderBox(dateProvider), calendar: calendar)
        prepareCourse()
        if self.phase == .storageError, storageErrorReason == nil {
            storageErrorReason = .progressUnreadable
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
        guard lessonOpen.begin() else { return }
        defer { lessonOpen.end() }
        guard let version = decodedCourse?.installedContentVersion, let course else { return }
        do {
            let url = try resolvedURL()
            let container = try ProgressContainer.make(at: url)
            let store = SwiftDataProgressStore(
                modelContainer: container,
                contentVersion: version
            )
            let snapshot = try await ProgressReconciler.run(
                store: store,
                content: course,
                on: clock.today
            )
            self.container = container
            self.progressStore = store
            self.snapshot = snapshot
            storageErrorReason = nil
            phase = phase(for: progressScreen(streak: snapshot.streak, on: clock.today))
        } catch {
            container = nil
            progressStore = nil
            snapshot = nil
            let screen = progressScreen(for: progressOpenFailure(for: error))
            storageErrorReason = screen == .storageError ? .progressUnreadable : nil
            phase = phase(for: screen)
        }
    }

    func tryAgain() async {
        guard phase == .storageError, !isRetrying else { return }
        isRetrying = true
        defer { isRetrying = false }
        if let storageErrorReason, storageErrorActions(for: storageErrorReason).retriesLessonSave {
            await retryFailedLessonSave()
            return
        }
        if prepareCourse() == nil {
            courseStillMissingToken += 1
        }
        await loadProgress()
    }

    func confirmStartOver() async {
        guard phase == .storageError, !lessonOpen.isOpening else { return }
        guard let storageErrorReason, storageErrorActions(for: storageErrorReason).showsStartOver else {
            return
        }
        guard let version = prepareCourse() else { return }
        guard lessonOpen.begin() else { return }
        defer { lessonOpen.end() }
        openLesson.endLesson()
        openLesson.discardPendingSaves()
        container = nil
        progressStore = nil
        snapshot = nil
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
    /// `RootView` forwards `accessibilityVoiceOverEnabled`. That environment
    /// value is the only VoiceOver source. A lesson that loses every task
    /// under the new setting drops off the home.
    func voiceOverChanged(to enabled: Bool) {
        home.setVoiceOver(enabled)
        publishLessons()
    }

    /// Opens a quiz for one released lesson. An unlisted lesson does not start.
    ///
    /// `voiceOver` is the value `RootView` already read from the environment.
    /// A lesson that was saved and can still be continued opens where it left off.
    /// A second tap while this open is still loading does not start another.
    func startLesson(_ lessonID: LessonID, voiceOver: Bool) async {
        voiceOverChanged(to: voiceOver)
        guard phase == .ready, let course, let store = progressStore else { return }
        guard lessonOpen.begin() else { return }
        defer { lessonOpen.end() }
        do {
            await openLesson.waitUntilSavesFinish()
            if openLesson.hasUnsavedAnswers {
                openLesson.retryUnsavedAnswers(to: store)
                await openLesson.waitUntilSavesFinish()
            }
            let progress = try await store.load()
            var rng = SystemRandomNumberGenerator()
            openLesson.startLesson(
                lessonID: lessonID,
                in: course,
                progress: progress,
                releasedUnitIDs: releasedUnitIDs,
                showsPronunciation: progress.settings.showTransliteration,
                voiceOver: home.voiceOver,
                on: clock.today,
                using: &rng
            )
        } catch {
            storageErrorReason = .lessonOpenUnreadable
            phase = .storageError
        }
    }

    /// Saves the answer that was just given. The quiz stays on that question.
    ///
    /// The record is taken before this returns, so closing the quiz does not
    /// drop the answer. A failed save is not shown. The next answer and a
    /// background retry write the whole session. Progress already stored stays.
    func saveAnswer(_ session: LessonSession) {
        guard let store = progressStore else { return }
        openLesson.saveAnswer(session, on: clock.today, to: store)
    }

    /// Writes an answer the store has not kept yet. Called when the app backgrounds.
    ///
    /// The system is asked for time to finish the write. The task ends when the
    /// save has landed, or when that time runs out.
    func saveLessonOnBackground() {
        guard let store = progressStore, openLesson.hasUnsavedAnswers else { return }
        let token = backgroundSave.begin()
        openLesson.retryUnsavedAnswers(to: store)
        Task {
            await openLesson.waitUntilSavesFinish()
            self.backgroundSave.end(matching: token)
        }
    }

    /// The learner finished the quiz. One commit saves the lesson, the cards, and the streak.
    ///
    /// Called when the last answer is given. Continue does not call this, so
    /// `day` is the civil day the quiz finished. A failed save shows the
    /// storage error and does not remove progress or the answers still on screen.
    /// The finished session replaces the last question immediately, so that
    /// question cannot be answered again. The quiz closes after the save, and
    /// only when `openLesson` is still this session. A lesson opened while the
    /// save was in flight stays on screen.
    func finishLesson(_ session: LessonSession) {
        let finished = openLesson.attempt?.sessionID
        let bundled = course
        let store = progressStore
        let day = clock.today
        let beforeStreak = snapshot.map { displayedStreakCount($0.streak, on: day) } ?? 0
        let beforeGoal = snapshot.map { newItemsShown(on: day, in: $0.cards) } ?? 0
        let beforeStreakState = snapshot?.streak ?? .initial
        let lessonID = session.lessonID
        openLesson.showFinishedSession(session)
        Task {
            guard let bundled, let store else { return }
            do {
                let saved = try await openLesson.finishLesson(
                    session,
                    on: day,
                    in: bundled,
                    to: store
                )
                showHomeMotion(
                    beforeStreak: beforeStreak,
                    beforeGoal: beforeGoal,
                    beforeStreakState: beforeStreakState,
                    lesson: lessonID,
                    saved: saved
                )
                snapshot = saved
                openLesson.endLessonIfStill(finished)
                storageErrorReason = nil
                phase = phase(for: progressScreen(streak: saved.streak, on: day))
            } catch {
                storageErrorReason = .lessonSaveFailed
                phase = phase(for: screenAfterFailedLessonSave())
            }
        }
    }

    /// Leaving the quiz before the end. Answers already saved stay saved.
    func endLesson() {
        openLesson.endLesson()
    }

    /// Writes the finished lesson again. The answers kept on screen are what get saved.
    private func retryFailedLessonSave() async {
        guard let course, let store = progressStore else { return }
        let finished = openLesson.attempt?.sessionID
        let day = clock.today
        let beforeStreak = snapshot.map { displayedStreakCount($0.streak, on: day) } ?? 0
        let beforeGoal = snapshot.map { newItemsShown(on: day, in: $0.cards) } ?? 0
        let beforeStreakState = snapshot?.streak ?? .initial
        let lessonID = openLesson.session?.lessonID
        do {
            let saved = try await openLesson.retryFailedFinish(in: course, to: store)
            if let lessonID {
                showHomeMotion(
                    beforeStreak: beforeStreak,
                    beforeGoal: beforeGoal,
                    beforeStreakState: beforeStreakState,
                    lesson: lessonID,
                    saved: saved
                )
            }
            snapshot = saved
            openLesson.endLessonIfStill(finished)
            storageErrorReason = nil
            phase = phase(for: progressScreen(streak: saved.streak, on: day))
        } catch {
            storageErrorReason = .lessonSaveFailed
            phase = phase(for: screenAfterFailedLessonSave())
        }
    }

    /// Records the home motion for a finish that just landed.
    ///
    /// `beforeStreak` and `beforeGoal` were taken on the day the quiz finished,
    /// before this save returned. The home plays the cue once and then clears it.
    private func showHomeMotion(
        beforeStreak: Int,
        beforeGoal: Int,
        beforeStreakState: StreakState,
        lesson: LessonID,
        saved: ProgressSnapshot
    ) {
        let finished = saved.lessonProgress.contains(where: { $0.lessonID == lesson }) ? lesson : nil
        homeMotion.stage(
            PendingHomeMotion(
                id: UUID(),
                streakFrom: beforeStreak,
                goalFrom: beforeGoal,
                lessonID: finished
            )
        )
        pendingHomeMotion = homeMotion.pending
        streakMotion.stage(StreakMotion.events(before: beforeStreakState, after: saved.streak))
        pendingStreakEvents = streakMotion.pending
    }

    /// The home takes one kind of event. The same day is not returned again.
    func claimStreakEvents(_ kind: StreakEventID.Kind) -> [StreakEventID] {
        let claimed = streakMotion.claim(kind)
        pendingStreakEvents = streakMotion.pending
        return claimed
    }

    /// Drops the home animation after the home has played it.
    func consumePendingHomeMotion() {
        _ = homeMotion.consume()
        pendingHomeMotion = homeMotion.pending
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
        let content = Self.bundledData(resource: "content", in: .main)
        let releaseUnits = Self.bundledData(resource: "release-units", in: .main)
        let decoded: BundledCourseDecode
        if let decodedCourse {
            decoded = decodedCourse.replacing(content: content, releaseUnits: releaseUnits)
        } else {
            decoded = BundledCourseDecode(content: content, releaseUnits: releaseUnits)
        }
        decodedCourse = decoded
        switch decoded.load {
        case .ready(let bundled):
            course = bundled.bundle
            releasedUnitIDs = bundled.releasedUnitIDs
            home.setCourse(bundled.bundle, releasedUnitIDs: bundled.releasedUnitIDs)
            if storageErrorReason == .courseUnreadable {
                storageErrorReason = nil
            }
            publishLessons()
            return bundled.installedContentVersion
        case .unavailable:
            course = nil
            releasedUnitIDs = []
            home.setCourse(nil, releasedUnitIDs: [])
            storageErrorReason = .courseUnreadable
            publishLessons()
            if let screen = decoded.load.blockingScreen {
                phase = phase(for: screen)
            }
            return nil
        }
    }

    /// Copies the list `snapshot` just refreshed. Called from `snapshot`'s `didSet`.
    private func refreshReleasedLessons() {
        home.snapshot = snapshot
        publishLessons()
    }

    private func publishLessons() {
        let lessons = home.lessons
        if lessons != releasedLessons {
            releasedLessons = lessons
        }
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

/// One system background task for a lesson save.
///
/// Which attempt is current lives in `BackgroundSaveOrder`. A later save keeps
/// the same system task. An earlier end does not stop that later save.
/// Ending the task twice is ignored. The system ending the task still ends it.
@MainActor
private final class BackgroundLessonSave {
    private var taskID: UIBackgroundTaskIdentifier = .invalid
    private var order = BackgroundSaveOrder()

    /// Asks for time to write. Returns the token this attempt holds.
    func begin() -> Int {
        let token = order.begin()
        if taskID == .invalid {
            taskID = UIApplication.shared.beginBackgroundTask { [weak self] in
                self?.endCurrent()
            }
        }
        return token
    }

    /// Ends the task when `expected` is still the latest begin.
    func end(matching expected: Int) {
        guard order.end(matching: expected) else { return }
        endCurrent()
    }

    private func endCurrent() {
        guard taskID != .invalid else { return }
        let ending = taskID
        taskID = .invalid
        UIApplication.shared.endBackgroundTask(ending)
    }
}
