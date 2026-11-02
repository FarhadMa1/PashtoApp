import Foundation
import SwiftData

/// Fixed keys for the single-row models.
enum RecordKey {
    static let streak = "streak"
    static let settings = "settings"
    static let meta = "meta"
    static let active = "active"
}

/// SwiftData schema for progress. Version 1.0.0.
///
/// The model classes stay inside this enum so a later schema can copy them.
/// They are internal. The app talks to `SwiftDataProgressStore`, not to rows.
///
/// V1 can still change until the first installed TestFlight build. After that,
/// a change is a new `SchemaVn` and a stage on `ProgressMigrationPlan`.
/// There are no relationships. Cards, lessons, and sessions point at each
/// other with stable content ids only.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            ReviewCardRecord.self,
            LessonProgressRecord.self,
            StreakRecord.self,
            SettingsRecord.self,
            StoreMetaRecord.self,
            ActiveSessionRecord.self,
            CompletedSessionRecord.self,
        ]
    }

    /// One row per content item id. `@Attribute(.unique)` is the safety net.
    /// The store still fetches the row and updates it, because a unique
    /// collision in SwiftData updates the old row instead of throwing.
    @Model
    final class ReviewCardRecord {
        @Attribute(.unique) var itemID: String
        var easeFactor: Double
        var intervalDays: Int
        var repetitions: Int
        var lapses: Int
        /// `LocalDay` as days since 1970-01-01.
        var dueDay: Int
        var lastReviewedDay: Int?
        var createdDay: Int
        /// `ReviewCardState.rawValue`.
        var state: String
        /// `ReviewCardSource.rawValue`.
        var source: String

        init(
            itemID: String,
            easeFactor: Double,
            intervalDays: Int,
            repetitions: Int,
            lapses: Int,
            dueDay: Int,
            lastReviewedDay: Int?,
            createdDay: Int,
            state: String,
            source: String
        ) {
            self.itemID = itemID
            self.easeFactor = easeFactor
            self.intervalDays = intervalDays
            self.repetitions = repetitions
            self.lapses = lapses
            self.dueDay = dueDay
            self.lastReviewedDay = lastReviewedDay
            self.createdDay = createdDay
            self.state = state
            self.source = source
        }
    }

    /// One row per lesson id.
    @Model
    final class LessonProgressRecord {
        @Attribute(.unique) var lessonID: String
        /// `LessonProgress.Source.rawValue`.
        var source: String
        var firstCompletedDay: Int
        var bestScorePercent: Int

        init(lessonID: String, source: String, firstCompletedDay: Int, bestScorePercent: Int) {
            self.lessonID = lessonID
            self.source = source
            self.firstCompletedDay = firstCompletedDay
            self.bestScorePercent = bestScorePercent
        }
    }

    /// The one streak row. `key` is always `streak`.
    ///
    /// `freezeUsedDays` is the covered days on `StreakState`. The draft schema
    /// had no column for them. They are day numbers, newest window included,
    /// in the order the core stored them.
    @Model
    final class StreakRecord {
        @Attribute(.unique) var key: String
        var current: Int
        var longest: Int
        var lastActiveDay: Int?
        var freezes: Int
        var daysTowardNextFreeze: Int
        var freezeUsedDays: [Int]

        init(
            key: String,
            current: Int,
            longest: Int,
            lastActiveDay: Int?,
            freezes: Int,
            daysTowardNextFreeze: Int,
            freezeUsedDays: [Int]
        ) {
            self.key = key
            self.current = current
            self.longest = longest
            self.lastActiveDay = lastActiveDay
            self.freezes = freezes
            self.daysTowardNextFreeze = daysTowardNextFreeze
            self.freezeUsedDays = freezeUsedDays
        }
    }

    /// The one settings row. `key` is always `settings`.
    @Model
    final class SettingsRecord {
        @Attribute(.unique) var key: String
        /// 5, 10, or 15 in normal use. `load` maps anything else with `validatedDailyGoal`.
        var dailyGoal: Int
        var showTransliteration: Bool
        var placementTakenDay: Int?

        init(key: String, dailyGoal: Int, showTransliteration: Bool, placementTakenDay: Int?) {
            self.key = key
            self.dailyGoal = dailyGoal
            self.showTransliteration = showTransliteration
            self.placementTakenDay = placementTakenDay
        }
    }

    /// The one metadata row. `key` is always `meta`.
    ///
    /// `contentVersion` and `snapshotVersion` are the core snapshot's versions.
    /// The draft schema only had the reconciliation cursor and the latest
    /// observed day. Both versions are stored so a newer snapshot can be
    /// refused without writing, and so `contentVersion` survives a relaunch.
    @Model
    final class StoreMetaRecord {
        @Attribute(.unique) var key: String
        var contentVersion: String
        var snapshotVersion: Int
        var lastReconciledContentVersion: String?
        var latestObservedDay: Int?

        init(
            key: String,
            contentVersion: String,
            snapshotVersion: Int,
            lastReconciledContentVersion: String?,
            latestObservedDay: Int?
        ) {
            self.key = key
            self.contentVersion = contentVersion
            self.snapshotVersion = snapshotVersion
            self.lastReconciledContentVersion = lastReconciledContentVersion
            self.latestObservedDay = latestObservedDay
        }
    }

    /// At most one lesson in progress. `key` is always `active`.
    ///
    /// `payload` is `ActiveSessionSnapshot` as JSON. `payloadVersion` is the
    /// column checked before that JSON is decoded, so a newer payload is not
    /// read and then written back without the fields this build does not know.
    @Model
    final class ActiveSessionRecord {
        @Attribute(.unique) var key: String
        var sessionID: UUID
        /// `SessionKind.rawValue`.
        var kind: String
        var lessonID: String?
        var startedDay: Int
        var contentVersion: String
        var payloadVersion: Int
        var payload: Data
        var updatedAt: Date

        init(
            key: String,
            sessionID: UUID,
            kind: String,
            lessonID: String?,
            startedDay: Int,
            contentVersion: String,
            payloadVersion: Int,
            payload: Data,
            updatedAt: Date
        ) {
            self.key = key
            self.sessionID = sessionID
            self.kind = kind
            self.lessonID = lessonID
            self.startedDay = startedDay
            self.contentVersion = contentVersion
            self.payloadVersion = payloadVersion
            self.payload = payload
            self.updatedAt = updatedAt
        }
    }

    /// One row per finished session. A second commit with the same id changes nothing.
    @Model
    final class CompletedSessionRecord {
        @Attribute(.unique) var sessionID: UUID
        var kind: String
        var lessonID: String?
        var completedDay: Int
        var questionCount: Int
        var firstTryCorrect: Int

        init(
            sessionID: UUID,
            kind: String,
            lessonID: String?,
            completedDay: Int,
            questionCount: Int,
            firstTryCorrect: Int
        ) {
            self.sessionID = sessionID
            self.kind = kind
            self.lessonID = lessonID
            self.completedDay = completedDay
            self.questionCount = questionCount
            self.firstTryCorrect = firstTryCorrect
        }
    }
}

typealias ReviewCardRecord = SchemaV1.ReviewCardRecord
typealias LessonProgressRecord = SchemaV1.LessonProgressRecord
typealias StreakRecord = SchemaV1.StreakRecord
typealias SettingsRecord = SchemaV1.SettingsRecord
typealias StoreMetaRecord = SchemaV1.StoreMetaRecord
typealias ActiveSessionRecord = SchemaV1.ActiveSessionRecord
typealias CompletedSessionRecord = SchemaV1.CompletedSessionRecord

/// Migration plan from the first revision. `stages` is empty while only V1 exists.
enum ProgressMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
