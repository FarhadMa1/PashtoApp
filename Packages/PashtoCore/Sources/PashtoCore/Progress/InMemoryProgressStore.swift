/// An in-memory `ProgressStore` for tests. A screen can use the same type before SwiftData exists.
///
/// `commit` builds the next snapshot and then replaces the stored one, so a
/// commit is all of its writes or none of them. A second commit with the
/// same session id returns before that replacement. Cards are upserted by
/// `itemID`: the last card with an id in one commit is the one that is kept,
/// and a later commit replaces that card instead of adding another.
///
/// `load` sorts cards and lessons by id and then clamps out-of-range values.
/// The stored copy is left as it was written. This store does not fail a
/// write. A store that can fail is what the write-failure contract uses.
public actor InMemoryProgressStore: ProgressStore {
    private var snapshot: ProgressSnapshot

    public init(contentVersion: String = "") {
        snapshot = .empty(contentVersion: contentVersion)
    }

    public func load() async throws -> ProgressSnapshot {
        validated(canonical(snapshot))
    }

    public func saveActiveSession(_ session: ActiveSessionSnapshot) async throws {
        store(snapshot, activeSession: session)
    }

    public func discardActiveSession() async throws {
        store(snapshot, activeSession: nil)
    }

    public func commit(_ commit: SessionCommit) async throws {
        guard commit.sessionID == commit.completed.sessionID else {
            throw ProgressStoreError.mismatchedSessionID
        }
        if snapshot.completedSessions.contains(where: { $0.sessionID == commit.sessionID }) {
            return
        }

        var cards = snapshot.cards
        for card in commit.cards {
            upsert(card, into: &cards)
        }
        var lessons = snapshot.lessonProgress
        if let progress = commit.lessonProgress {
            upsert(progress, into: &lessons)
        }
        let active = snapshot.activeSession?.sessionID == commit.sessionID ? nil : snapshot.activeSession
        store(
            snapshot,
            cards: sortedCards(cards),
            lessonProgress: sortedLessons(lessons),
            streak: commit.streak,
            activeSession: active,
            completedSessions: snapshot.completedSessions + [commit.completed]
        )
    }

    public func applyReconciliation(_ changes: [ReviewCard]) async throws {
        guard !changes.isEmpty else { return }
        var cards = snapshot.cards
        for change in changes {
            upsert(change, into: &cards)
        }
        store(snapshot, cards: sortedCards(cards), activeSession: snapshot.activeSession)
    }

    public func updateSettings(_ settings: UserSettings) async throws {
        store(snapshot, settings: settings, activeSession: snapshot.activeSession)
    }

    public func resetAll() async throws {
        // The daily goal and transliteration stay. placementTakenDay is cleared
        // so the placement test can be offered again. contentVersion describes
        // the installed content, not the learner's progress.
        let settings = UserSettings(
            dailyGoal: snapshot.settings.dailyGoal,
            showTransliteration: snapshot.settings.showTransliteration,
            placementTakenDay: nil
        )
        snapshot = ProgressSnapshot(
            snapshotVersion: snapshot.snapshotVersion,
            contentVersion: snapshot.contentVersion,
            cards: [],
            lessonProgress: [],
            streak: .initial,
            settings: settings,
            activeSession: nil,
            completedSessions: [],
            lastReconciledContentVersion: nil,
            latestObservedDay: nil
        )
    }

    /// `activeSession` is the value to store, including nil when the session is cleared.
    ///
    /// Callers that keep the session pass `base.activeSession`. A default of
    /// nil would drop it whenever a caller updated some other field.
    private func store(
        _ base: ProgressSnapshot,
        cards: [ReviewCard]? = nil,
        lessonProgress: [LessonProgress]? = nil,
        streak: StreakState? = nil,
        settings: UserSettings? = nil,
        activeSession: ActiveSessionSnapshot?,
        completedSessions: [CompletedSession]? = nil
    ) {
        snapshot = ProgressSnapshot(
            snapshotVersion: base.snapshotVersion,
            contentVersion: base.contentVersion,
            cards: cards ?? base.cards,
            lessonProgress: lessonProgress ?? base.lessonProgress,
            streak: streak ?? base.streak,
            settings: settings ?? base.settings,
            activeSession: activeSession,
            completedSessions: completedSessions ?? base.completedSessions,
            lastReconciledContentVersion: base.lastReconciledContentVersion,
            latestObservedDay: base.latestObservedDay
        )
    }

    private func canonical(_ snapshot: ProgressSnapshot) -> ProgressSnapshot {
        let cards = sortedCards(snapshot.cards)
        let lessons = sortedLessons(snapshot.lessonProgress)
        if cards == snapshot.cards, lessons == snapshot.lessonProgress {
            return snapshot
        }
        return ProgressSnapshot(
            snapshotVersion: snapshot.snapshotVersion,
            contentVersion: snapshot.contentVersion,
            cards: cards,
            lessonProgress: lessons,
            streak: snapshot.streak,
            settings: snapshot.settings,
            activeSession: snapshot.activeSession,
            completedSessions: snapshot.completedSessions,
            lastReconciledContentVersion: snapshot.lastReconciledContentVersion,
            latestObservedDay: snapshot.latestObservedDay
        )
    }

    private func upsert(_ card: ReviewCard, into cards: inout [ReviewCard]) {
        if let index = cards.firstIndex(where: { $0.itemID == card.itemID }) {
            cards[index] = card
        } else {
            cards.append(card)
        }
    }

    private func upsert(_ progress: LessonProgress, into lessons: inout [LessonProgress]) {
        if let index = lessons.firstIndex(where: { $0.lessonID == progress.lessonID }) {
            lessons[index] = progress
        } else {
            lessons.append(progress)
        }
    }

    private func sortedCards(_ cards: [ReviewCard]) -> [ReviewCard] {
        cards.sorted { $0.itemID.rawValue < $1.itemID.rawValue }
    }

    private func sortedLessons(_ lessons: [LessonProgress]) -> [LessonProgress] {
        lessons.sorted { $0.lessonID.rawValue < $1.lessonID.rawValue }
    }
}
