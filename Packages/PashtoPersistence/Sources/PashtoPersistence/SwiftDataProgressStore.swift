import Foundation
import os
import PashtoCore
import SwiftData

/// Log for a dropped active session. No lesson text is included.
private let progressLog = Logger(subsystem: "com.mangallabs.pashto", category: "progress")

/// SwiftData store for one device.
///
/// Translation and `save()` live here. The streak, the daily plan, and the
/// lesson rules stay in PashtoCore. `load` builds a snapshot and passes it
/// through `validated`. Clamped numbers are what the caller sees. The stored
/// row is not rewritten.
///
/// Autosave is off. A write reaches the file only when `save()` returns.
/// If `save()` throws, the context is rolled back and the same error is
/// thrown to the caller. Rows from an earlier successful save stay, including
/// an active lesson saved after a previous answer. The app can keep that
/// lesson in memory and try the save again on the next answer, or when it
/// moves to the background. This package does not show that message.
///
/// A newer snapshot or schema throws, and nothing is written over it.
/// An active session this build cannot read — an older payload version, or
/// JSON that does not decode — is deleted on `load`, logged, and the rest
/// of the file loads. A newer session payload is not deleted.
@ModelActor
public actor SwiftDataProgressStore: ProgressStore {
    private let installedContentVersion: String

    /// `contentVersion` is the bundle version used until the file has its own.
    /// After the first successful write, `load` returns the version stored
    /// in the file. Later calls do not replace it.
    public init(modelContainer: ModelContainer, contentVersion: String) {
        let modelContext = ModelContext(modelContainer)
        modelContext.autosaveEnabled = false
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
        self.modelContainer = modelContainer
        self.installedContentVersion = contentVersion
    }

    public func load() async throws -> ProgressSnapshot {
        try refuseIfNewer()
        try discardUnreadableActiveSession()
        return validated(try makeSnapshot())
    }

    public func saveActiveSession(_ session: ActiveSessionSnapshot) async throws {
        try write {
            try self.upsert(session)
            try self.insertMetaIfNeeded()
        }
    }

    public func discardActiveSession() async throws {
        try write {
            if let active = try self.activeRow() {
                self.modelContext.delete(active)
            }
        }
    }

    public func commit(_ commit: SessionCommit) async throws {
        guard commit.sessionID == commit.completed.sessionID else {
            throw ProgressStoreError.mismatchedSessionID
        }
        try write {
            // Already stored: leave completedDay, cards, and the streak alone.
            if try self.hasCompleted(commit.sessionID) {
                return
            }
            try self.upsert(commit.cards)
            if let lesson = commit.lessonProgress {
                try self.upsert(lesson)
            }
            try self.upsert(commit.streak)
            self.insert(commit.completed)
            if let active = try self.activeRow(), active.sessionID == commit.sessionID {
                self.modelContext.delete(active)
            }
            try self.insertMetaIfNeeded()
        }
    }

    public func applyReconciliation(_ changes: [ReviewCard]) async throws {
        guard !changes.isEmpty else { return }
        try write {
            try self.upsert(changes)
            try self.insertMetaIfNeeded()
        }
    }

    public func updateSettings(_ settings: UserSettings) async throws {
        try write {
            try self.upsert(settings)
            try self.insertMetaIfNeeded()
        }
    }

    public func resetAll() async throws {
        try write {
            try self.deleteAll(ReviewCardRecord.self)
            try self.deleteAll(LessonProgressRecord.self)
            try self.deleteAll(StreakRecord.self)
            try self.deleteAll(ActiveSessionRecord.self)
            try self.deleteAll(CompletedSessionRecord.self)
            if let settings = try self.settingsRow() {
                settings.placementTakenDay = nil
            }
            if let meta = try self.metaRow() {
                meta.lastReconciledContentVersion = nil
                meta.latestObservedDay = nil
            } else {
                try self.insertMetaIfNeeded()
            }
        }
    }

    /// One transaction. A thrown error, including a failed `save()`, rolls
    /// the context back so a half-applied commit is not kept. The error is
    /// the original one: the caller decides whether to continue in memory.
    private func write(_ body: () throws -> Void) throws {
        do {
            try refuseIfNewer()
            try body()
            if modelContext.hasChanges {
                try modelContext.save()
            }
        } catch {
            if modelContext.hasChanges {
                modelContext.rollback()
            }
            throw error
        }
    }

    /// A newer snapshot or a newer session payload must not be overwritten.
    /// An older snapshot this build does not migrate is refused the same way.
    /// An older or unreadable active session is not refused here. `load`
    /// deletes that row instead.
    private func refuseIfNewer() throws {
        if let meta = try metaRow() {
            if meta.snapshotVersion > ProgressSnapshot.currentVersion {
                throw ProgressPersistenceError.newerSnapshot(meta.snapshotVersion)
            }
            if meta.snapshotVersion < ProgressSnapshot.currentVersion {
                throw ProgressPersistenceError.unsupportedSnapshot(meta.snapshotVersion)
            }
        }
        if let active = try activeRow(),
           active.payloadVersion > ActiveSessionSnapshot.currentPayloadVersion {
            throw ProgressPersistenceError.newerPayload(active.payloadVersion)
        }
    }

    /// Deletes one active session this build cannot read, then saves that
    /// deletion on its own. The other rows stay. A failed `save()` is rolled
    /// back and rethrown, so a session that is still on disk is not reported
    /// as gone.
    private func discardUnreadableActiveSession() throws {
        guard let active = try activeRow() else { return }
        do {
            _ = try activeSession(active)
        } catch ProgressPersistenceError.newerPayload(let version) {
            throw ProgressPersistenceError.newerPayload(version)
        } catch {
            let version = active.payloadVersion
            modelContext.delete(active)
            if modelContext.hasChanges {
                do {
                    try modelContext.save()
                } catch {
                    if modelContext.hasChanges {
                        modelContext.rollback()
                    }
                    throw error
                }
            }
            progressLog.error("Dropped an active session that could not be read. Payload version \(version).")
        }
    }

    private func makeSnapshot() throws -> ProgressSnapshot {
        let meta = try metaRow()
        var cards: [ReviewCard] = []
        for record in try cardRows() {
            cards.append(try reviewCard(record))
        }
        cards.sort { $0.itemID.rawValue < $1.itemID.rawValue }

        var lessons: [LessonProgress] = []
        for record in try lessonRows() {
            lessons.append(try lessonProgress(record))
        }
        lessons.sort { $0.lessonID.rawValue < $1.lessonID.rawValue }

        var completed: [CompletedSession] = []
        for record in try completedRows() {
            completed.append(try completedSession(record))
        }
        completed.sort { lhs, rhs in
            if lhs.completedDay != rhs.completedDay {
                return lhs.completedDay < rhs.completedDay
            }
            return lhs.sessionID.uuidString < rhs.sessionID.uuidString
        }

        let streak: StreakState
        if let record = try streakRow() {
            streak = try streakState(record)
        } else {
            streak = .initial
        }
        let settings: UserSettings
        if let record = try settingsRow() {
            settings = try userSettings(record)
        } else {
            settings = .initial
        }
        let active: ActiveSessionSnapshot?
        if let record = try activeRow() {
            active = try activeSession(record)
        } else {
            active = nil
        }
        let observed: LocalDay?
        if let number = meta?.latestObservedDay {
            observed = try DayNumber.decode(number)
        } else {
            observed = nil
        }
        return ProgressSnapshot(
            snapshotVersion: meta?.snapshotVersion ?? ProgressSnapshot.currentVersion,
            contentVersion: meta?.contentVersion ?? installedContentVersion,
            cards: cards,
            lessonProgress: lessons,
            streak: streak,
            settings: settings,
            activeSession: active,
            completedSessions: completed,
            lastReconciledContentVersion: meta?.lastReconciledContentVersion,
            latestObservedDay: observed
        )
    }

    private func insertMetaIfNeeded() throws {
        if try metaRow() != nil { return }
        modelContext.insert(
            StoreMetaRecord(
                key: RecordKey.meta,
                contentVersion: installedContentVersion,
                snapshotVersion: ProgressSnapshot.currentVersion,
                lastReconciledContentVersion: nil,
                latestObservedDay: nil
            )
        )
    }

    private func upsert(_ cards: [ReviewCard]) throws {
        var lastByID: [String: ReviewCard] = [:]
        var order: [String] = []
        for card in cards {
            let id = card.itemID.rawValue
            if lastByID[id] == nil {
                order.append(id)
            }
            lastByID[id] = card
        }
        for id in order {
            guard let card = lastByID[id] else { continue }
            try upsert(card)
        }
    }

    private func upsert(_ card: ReviewCard) throws {
        let itemID = card.itemID.rawValue
        let matches = try cardRows().filter { $0.itemID == itemID }
        if matches.count > 1 {
            throw ProgressPersistenceError.duplicateStoredValue(field: "itemID", value: itemID)
        }
        if let record = matches.first {
            record.easeFactor = card.easeFactor
            record.intervalDays = card.intervalDays
            record.repetitions = card.repetitions
            record.lapses = card.lapses
            record.dueDay = DayNumber.encode(card.dueDay)
            record.lastReviewedDay = card.lastReviewedDay.map(DayNumber.encode)
            record.createdDay = DayNumber.encode(card.createdDay)
            record.state = card.state.rawValue
            record.source = card.source.rawValue
            return
        }
        modelContext.insert(
            ReviewCardRecord(
                itemID: itemID,
                easeFactor: card.easeFactor,
                intervalDays: card.intervalDays,
                repetitions: card.repetitions,
                lapses: card.lapses,
                dueDay: DayNumber.encode(card.dueDay),
                lastReviewedDay: card.lastReviewedDay.map(DayNumber.encode),
                createdDay: DayNumber.encode(card.createdDay),
                state: card.state.rawValue,
                source: card.source.rawValue
            )
        )
    }

    private func upsert(_ progress: LessonProgress) throws {
        let lessonID = progress.lessonID.rawValue
        let matches = try lessonRows().filter { $0.lessonID == lessonID }
        if matches.count > 1 {
            throw ProgressPersistenceError.duplicateStoredValue(field: "lessonID", value: lessonID)
        }
        if let record = matches.first {
            record.source = progress.source.rawValue
            record.firstCompletedDay = DayNumber.encode(progress.firstCompletedDay)
            record.bestScorePercent = progress.bestScorePercent
            return
        }
        modelContext.insert(
            LessonProgressRecord(
                lessonID: lessonID,
                source: progress.source.rawValue,
                firstCompletedDay: DayNumber.encode(progress.firstCompletedDay),
                bestScorePercent: progress.bestScorePercent
            )
        )
    }

    private func upsert(_ streak: StreakState) throws {
        let days = streak.freezeUsedDays.map(DayNumber.encode)
        if let record = try streakRow() {
            record.current = streak.current
            record.longest = streak.longest
            record.lastActiveDay = streak.lastActiveDay.map(DayNumber.encode)
            record.freezes = streak.freezes
            record.daysTowardNextFreeze = streak.daysTowardNextFreeze
            record.freezeUsedDays = days
            return
        }
        modelContext.insert(
            StreakRecord(
                key: RecordKey.streak,
                current: streak.current,
                longest: streak.longest,
                lastActiveDay: streak.lastActiveDay.map(DayNumber.encode),
                freezes: streak.freezes,
                daysTowardNextFreeze: streak.daysTowardNextFreeze,
                freezeUsedDays: days
            )
        )
    }

    private func upsert(_ settings: UserSettings) throws {
        if let record = try settingsRow() {
            record.dailyGoal = settings.dailyGoal.rawValue
            record.showTransliteration = settings.showTransliteration
            record.placementTakenDay = settings.placementTakenDay.map(DayNumber.encode)
            return
        }
        modelContext.insert(
            SettingsRecord(
                key: RecordKey.settings,
                dailyGoal: settings.dailyGoal.rawValue,
                showTransliteration: settings.showTransliteration,
                placementTakenDay: settings.placementTakenDay.map(DayNumber.encode)
            )
        )
    }

    private func upsert(_ session: ActiveSessionSnapshot) throws {
        let payload = try SessionJSON.encode(session)
        let startedDay = DayNumber.encode(session.startedDay)
        if let record = try activeRow() {
            record.sessionID = session.sessionID
            record.kind = session.kind.rawValue
            record.lessonID = session.lessonID?.rawValue
            record.startedDay = startedDay
            record.contentVersion = session.contentVersion
            record.payloadVersion = session.payloadVersion
            record.payload = payload
            record.updatedAt = Date()
            return
        }
        modelContext.insert(
            ActiveSessionRecord(
                key: RecordKey.active,
                sessionID: session.sessionID,
                kind: session.kind.rawValue,
                lessonID: session.lessonID?.rawValue,
                startedDay: startedDay,
                contentVersion: session.contentVersion,
                payloadVersion: session.payloadVersion,
                payload: payload,
                updatedAt: Date()
            )
        )
    }

    private func insert(_ completed: CompletedSession) {
        modelContext.insert(
            CompletedSessionRecord(
                sessionID: completed.sessionID,
                kind: completed.kind.rawValue,
                lessonID: completed.lessonID?.rawValue,
                completedDay: DayNumber.encode(completed.completedDay),
                questionCount: completed.questionCount,
                firstTryCorrect: completed.firstTryCorrect
            )
        )
    }

    private func hasCompleted(_ sessionID: UUID) throws -> Bool {
        try completedRows().contains { $0.sessionID == sessionID }
    }

    private func reviewCard(_ record: ReviewCardRecord) throws -> ReviewCard {
        guard let itemID = ItemID(rawValue: record.itemID) else {
            throw ProgressPersistenceError.invalidIdentifier(field: "itemID", value: record.itemID)
        }
        guard let state = ReviewCardState(rawValue: record.state) else {
            throw ProgressPersistenceError.unknownStoredValue(field: "ReviewCard.state", value: record.state)
        }
        guard let source = ReviewCardSource(rawValue: record.source) else {
            throw ProgressPersistenceError.unknownStoredValue(field: "ReviewCard.source", value: record.source)
        }
        return ReviewCard(
            itemID: itemID,
            easeFactor: record.easeFactor,
            intervalDays: record.intervalDays,
            repetitions: record.repetitions,
            lapses: record.lapses,
            dueDay: try DayNumber.decode(record.dueDay),
            lastReviewedDay: try optionalDay(record.lastReviewedDay),
            createdDay: try DayNumber.decode(record.createdDay),
            state: state,
            source: source
        )
    }

    private func lessonProgress(_ record: LessonProgressRecord) throws -> LessonProgress {
        guard let lessonID = LessonID(rawValue: record.lessonID) else {
            throw ProgressPersistenceError.invalidIdentifier(field: "lessonID", value: record.lessonID)
        }
        guard let source = LessonProgress.Source(rawValue: record.source) else {
            throw ProgressPersistenceError.unknownStoredValue(field: "LessonProgress.source", value: record.source)
        }
        return LessonProgress(
            lessonID: lessonID,
            source: source,
            firstCompletedDay: try DayNumber.decode(record.firstCompletedDay),
            bestScorePercent: record.bestScorePercent
        )
    }

    private func streakState(_ record: StreakRecord) throws -> StreakState {
        StreakState(
            current: record.current,
            longest: record.longest,
            lastActiveDay: try optionalDay(record.lastActiveDay),
            freezes: record.freezes,
            daysTowardNextFreeze: record.daysTowardNextFreeze,
            freezeUsedDays: try record.freezeUsedDays.map(DayNumber.decode)
        )
    }

    /// The goal column is an int. `validatedDailyGoal` is the core mapping.
    /// `validated` still runs on the snapshot afterwards.
    private func userSettings(_ record: SettingsRecord) throws -> UserSettings {
        UserSettings(
            dailyGoal: validatedDailyGoal(record.dailyGoal),
            showTransliteration: record.showTransliteration,
            placementTakenDay: try optionalDay(record.placementTakenDay)
        )
    }

    private func activeSession(_ record: ActiveSessionRecord) throws -> ActiveSessionSnapshot {
        if record.payloadVersion > ActiveSessionSnapshot.currentPayloadVersion {
            throw ProgressPersistenceError.newerPayload(record.payloadVersion)
        }
        if record.payloadVersion < ActiveSessionSnapshot.currentPayloadVersion {
            throw ProgressPersistenceError.unsupportedPayload(record.payloadVersion)
        }
        let session = try SessionJSON.decode(record.payload)
        guard session.payloadVersion == record.payloadVersion else {
            throw ProgressPersistenceError.unreadableActiveSession
        }
        return session
    }

    private func completedSession(_ record: CompletedSessionRecord) throws -> CompletedSession {
        guard let kind = SessionKind(rawValue: record.kind) else {
            throw ProgressPersistenceError.unknownStoredValue(field: "CompletedSession.kind", value: record.kind)
        }
        let lessonID: LessonID?
        if let raw = record.lessonID {
            guard let parsed = LessonID(rawValue: raw) else {
                throw ProgressPersistenceError.invalidIdentifier(field: "lessonID", value: raw)
            }
            lessonID = parsed
        } else {
            lessonID = nil
        }
        return CompletedSession(
            sessionID: record.sessionID,
            kind: kind,
            lessonID: lessonID,
            completedDay: try DayNumber.decode(record.completedDay),
            questionCount: record.questionCount,
            firstTryCorrect: record.firstTryCorrect
        )
    }

    private func optionalDay(_ number: Int?) throws -> LocalDay? {
        guard let number else { return nil }
        return try DayNumber.decode(number)
    }

    private func cardRows() throws -> [ReviewCardRecord] {
        let rows = try fetchAll(ReviewCardRecord.self)
        var seen = Set<String>()
        for row in rows {
            if !seen.insert(row.itemID).inserted {
                throw ProgressPersistenceError.duplicateStoredValue(field: "itemID", value: row.itemID)
            }
        }
        return rows
    }

    private func lessonRows() throws -> [LessonProgressRecord] {
        let rows = try fetchAll(LessonProgressRecord.self)
        var seen = Set<String>()
        for row in rows {
            if !seen.insert(row.lessonID).inserted {
                throw ProgressPersistenceError.duplicateStoredValue(field: "lessonID", value: row.lessonID)
            }
        }
        return rows
    }

    private func completedRows() throws -> [CompletedSessionRecord] {
        try fetchAll(CompletedSessionRecord.self)
    }

    private func streakRow() throws -> StreakRecord? {
        try single(fetchAll(StreakRecord.self).filter { $0.key == RecordKey.streak }, field: "streak")
    }

    private func settingsRow() throws -> SettingsRecord? {
        try single(fetchAll(SettingsRecord.self).filter { $0.key == RecordKey.settings }, field: "settings")
    }

    private func metaRow() throws -> StoreMetaRecord? {
        try single(fetchAll(StoreMetaRecord.self).filter { $0.key == RecordKey.meta }, field: "meta")
    }

    private func activeRow() throws -> ActiveSessionRecord? {
        try single(fetchAll(ActiveSessionRecord.self).filter { $0.key == RecordKey.active }, field: "active")
    }

    private func single<Model>(_ rows: [Model], field: String) throws -> Model? {
        if rows.count > 1 {
            throw ProgressPersistenceError.duplicateStoredValue(field: field, value: field)
        }
        return rows.first
    }

    private func fetchAll<Model: PersistentModel>(_ type: Model.Type) throws -> [Model] {
        try modelContext.fetch(FetchDescriptor<Model>())
    }

    private func deleteAll<Model: PersistentModel>(_ type: Model.Type) throws {
        for row in try fetchAll(type) {
            modelContext.delete(row)
        }
    }
}

/// JSON for one active lesson. The column `payloadVersion` is checked before this runs.
private enum SessionJSON {
    static func encode(_ session: ActiveSessionSnapshot) throws -> Data {
        try JSONEncoder().encode(session)
    }

    static func decode(_ data: Data) throws -> ActiveSessionSnapshot {
        do {
            return try JSONDecoder().decode(ActiveSessionSnapshot.self, from: data)
        } catch let error as ProgressPersistenceError {
            throw error
        } catch {
            throw ProgressPersistenceError.unreadableActiveSession
        }
    }
}
