import Foundation

/// A stored progress file was written by a different build.
public enum ProgressSnapshotError: Error, Equatable, Sendable {
    /// The file is newer than this build. The caller must not replace it.
    case newerVersion(Int)
    /// The file is older than this build. Nothing migrates it yet.
    case unsupportedVersion(Int)
}

/// The stored learner state. Logic reads this value and does not read the store.
///
/// `snapshotVersion` is the JSON shape of this value. It is not the SwiftData
/// schema version. `contentVersion` is the content bundle the progress was
/// saved against. A snapshot whose `snapshotVersion` is newer than
/// `currentVersion` fails to decode, so there is no value to write back over
/// the stored one.
public struct ProgressSnapshot: Hashable, Sendable {
    public static let currentVersion = 1

    public let snapshotVersion: Int
    public let contentVersion: String
    public let cards: [ReviewCard]
    public let lessonProgress: [LessonProgress]
    public let streak: StreakState
    public let settings: UserSettings
    public let activeSession: ActiveSessionSnapshot?
    public let completedSessions: [CompletedSession]
    /// The content version last compared with the cards. Nothing writes this yet.
    public let lastReconciledContentVersion: String?
    /// The latest civil day the app has seen. Nothing writes this yet.
    public let latestObservedDay: LocalDay?

    public init(
        snapshotVersion: Int = currentVersion,
        contentVersion: String,
        cards: [ReviewCard],
        lessonProgress: [LessonProgress],
        streak: StreakState,
        settings: UserSettings,
        activeSession: ActiveSessionSnapshot?,
        completedSessions: [CompletedSession],
        lastReconciledContentVersion: String?,
        latestObservedDay: LocalDay?
    ) {
        self.snapshotVersion = snapshotVersion
        self.contentVersion = contentVersion
        self.cards = cards
        self.lessonProgress = lessonProgress
        self.streak = streak
        self.settings = settings
        self.activeSession = activeSession
        self.completedSessions = completedSessions
        self.lastReconciledContentVersion = lastReconciledContentVersion
        self.latestObservedDay = latestObservedDay
    }

    /// No cards, no lessons, no streak, and the standard settings.
    public static func empty(contentVersion: String) -> ProgressSnapshot {
        ProgressSnapshot(
            contentVersion: contentVersion,
            cards: [],
            lessonProgress: [],
            streak: .initial,
            settings: .initial,
            activeSession: nil,
            completedSessions: [],
            lastReconciledContentVersion: nil,
            latestObservedDay: nil
        )
    }
}

extension ProgressSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case snapshotVersion
        case contentVersion
        case cards
        case lessonProgress
        case streak
        case settings
        case activeSession
        case completedSessions
        case lastReconciledContentVersion
        case latestObservedDay
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let snapshotVersion = try container.decode(Int.self, forKey: .snapshotVersion)
        guard snapshotVersion == Self.currentVersion else {
            if snapshotVersion > Self.currentVersion {
                throw ProgressSnapshotError.newerVersion(snapshotVersion)
            }
            throw ProgressSnapshotError.unsupportedVersion(snapshotVersion)
        }
        self.snapshotVersion = snapshotVersion
        contentVersion = try container.decode(String.self, forKey: .contentVersion)
        cards = try container.decode([ReviewCard].self, forKey: .cards)
        lessonProgress = try container.decode([LessonProgress].self, forKey: .lessonProgress)
        streak = try container.decode(StreakState.self, forKey: .streak)
        settings = try container.decode(UserSettings.self, forKey: .settings)
        activeSession = try container.decodeIfPresent(ActiveSessionSnapshot.self, forKey: .activeSession)
        completedSessions = try container.decode([CompletedSession].self, forKey: .completedSessions)
        lastReconciledContentVersion = try container.decodeIfPresent(
            String.self,
            forKey: .lastReconciledContentVersion
        )
        latestObservedDay = try container.decodeIfPresent(LocalDay.self, forKey: .latestObservedDay)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(snapshotVersion, forKey: .snapshotVersion)
        try container.encode(contentVersion, forKey: .contentVersion)
        try container.encode(cards, forKey: .cards)
        try container.encode(lessonProgress, forKey: .lessonProgress)
        try container.encode(streak, forKey: .streak)
        try container.encode(settings, forKey: .settings)
        try container.encode(activeSession, forKey: .activeSession)
        try container.encode(completedSessions, forKey: .completedSessions)
        try container.encode(lastReconciledContentVersion, forKey: .lastReconciledContentVersion)
        try container.encode(latestObservedDay, forKey: .latestObservedDay)
    }
}

/// Lesson cards created on `day`. Placement cards are not counted.
///
/// The same item id counts once. A paused lesson card created on `day` counts,
/// because it was introduced that day. A lesson card from another day does not.
public func newItemsShown(on day: LocalDay, in cards: [ReviewCard]) -> Int {
    var seen: Set<ItemID> = []
    for card in cards where card.source == .lesson && card.createdDay == day {
        seen.insert(card.itemID)
    }
    return seen.count
}

/// The `PathProgress` for `day`.
///
/// Finished and placement-skipped lessons are both finished. The new-item
/// count is `newItemsShown(on:in:)`. The cards are the snapshot's cards,
/// paused ones included. This function does not validate and does not read
/// a clock. `load()` is what clamps out-of-range values.
public func pathProgress(_ snapshot: ProgressSnapshot, on day: LocalDay) -> PathProgress {
    PathProgress(
        cards: snapshot.cards,
        finishedLessonIDs: Set(snapshot.lessonProgress.map(\.lessonID)),
        newItemsShownToday: newItemsShown(on: day, in: snapshot.cards)
    )
}
