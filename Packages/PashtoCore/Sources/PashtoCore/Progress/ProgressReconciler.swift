import Foundation

/// What startup does with the one active session.
///
/// A finished lesson is committed. An unfinished lesson is resumed only when
/// `canResume` is true, and dropped otherwise. A review starts over. A payload
/// from a newer app is left untouched.
public enum SessionStartup: Hashable, Sendable {
    /// The unfinished lesson can be continued.
    case resume
    /// Every question is answered. Commit this. Do not resume it and do not drop it.
    case commit(SessionCommit)
    /// The session cannot be continued. Drop it. This creates no cards and no streak day.
    case discard
    /// The payload is newer than this build. Leave the stored session as it is.
    case keep
}

/// Cards after one comparison with a content bundle.
///
/// `snapshot` is the progress with those cards applied and with
/// `lastReconciledContentVersion` set to the bundle version. Lesson rows are
/// not removed. `contentVersion` on the snapshot is not changed. `cardChanges`
/// is what the store upserts. It is empty when no card was paused, restored,
/// or added.
public struct ContentReconciliation: Hashable, Sendable {
    public let snapshot: ProgressSnapshot
    public let cardChanges: [ReviewCard]

    public init(snapshot: ProgressSnapshot, cardChanges: [ReviewCard]) {
        self.snapshot = snapshot
        self.cardChanges = cardChanges
    }
}

/// Compares stored progress with the content bundle at startup.
///
/// Call `run` after `load`. It is idempotent: a second call sees the cards
/// and the committed session the first call wrote, and it does not write
/// them again. The content version it stores is only a debug marker.
///
/// `today` is an argument. Nothing here reads a clock.
public enum ProgressReconciler {
    /// New cards for items added to a lesson the learner already finished.
    ///
    /// At most this many become due on one civil day. The approved note said
    /// "for example, at most 10 per day, like placement cards." Placement
    /// spreading is a later step and uses 10, so this uses 10. The first
    /// cards are due on `today`, then the next day, in course order, including
    /// past the first week.
    public static let maximumNewCardsPerDay = 10

    /// Pauses cards whose items are gone, restores cards whose items came
    /// back, and adds cards for new items in lessons the learner already
    /// finished.
    ///
    /// A card is paused when its item is not in `content.items`. It is not
    /// deleted. The ease, the interval, the due day, and the other history
    /// stay. When the item is in the bundle again, the card is active and
    /// that history, including `dueDay`, is the same. Text on an item is not
    /// read, so a spelling fix with the same id changes nothing.
    ///
    /// A removed lesson row stays. The path ignores a lesson id that is not
    /// in the bundle. A new lesson adds no row and no card until the learner
    /// finishes it, unless the new item belongs to a lesson that is already
    /// finished. Those new cards are spread by `maximumNewCardsPerDay`.
    /// `createdDay` is the lesson's `firstCompletedDay`, so they are not
    /// counted as items introduced on `today`. `source` is `lesson`. A lesson
    /// skipped by the placement test counts as finished here too.
    ///
    /// The active session is not changed. `sessionAction` decides that.
    public static func reconcile(
        _ snapshot: ProgressSnapshot,
        with content: ContentBundle,
        on today: LocalDay
    ) -> ContentReconciliation {
        let present = Set(content.items.map(\.id))
        var cards: [ReviewCard] = []
        var changes: [ReviewCard] = []
        for card in snapshot.cards {
            let updated = aligned(card, present: present)
            cards.append(updated)
            if updated != card {
                changes.append(updated)
            }
        }

        var finished: [LessonID: LessonProgress] = [:]
        for row in snapshot.lessonProgress where finished[row.lessonID] == nil {
            finished[row.lessonID] = row
        }
        var known = Set(cards.map(\.itemID))
        var added = 0
        for introduction in CourseOrder(content).introductions {
            guard let progress = finished[introduction.lessonID] else { continue }
            guard present.contains(introduction.itemID) else { continue }
            guard known.insert(introduction.itemID).inserted else { continue }
            let card = catchUpCard(
                itemID: introduction.itemID,
                created: progress.firstCompletedDay,
                index: added,
                on: today
            )
            added += 1
            cards.append(card)
            changes.append(card)
        }

        let reconciled = ProgressSnapshot(
            snapshotVersion: snapshot.snapshotVersion,
            contentVersion: snapshot.contentVersion,
            cards: cards.sorted { $0.itemID.rawValue < $1.itemID.rawValue },
            lessonProgress: snapshot.lessonProgress.sorted { $0.lessonID.rawValue < $1.lessonID.rawValue },
            streak: snapshot.streak,
            settings: snapshot.settings,
            activeSession: snapshot.activeSession,
            completedSessions: snapshot.completedSessions,
            lastReconciledContentVersion: content.contentVersion,
            latestObservedDay: snapshot.latestObservedDay
        )
        return ContentReconciliation(
            snapshot: reconciled,
            cardChanges: changes.sorted { $0.itemID.rawValue < $1.itemID.rawValue }
        )
    }

    /// What to do with one stored session on `today`.
    ///
    /// A newer payload is kept, even when the lesson is finished or the
    /// session is a review. A session whose id is already in
    /// `completedSessions` is dropped and not committed again. A finished
    /// lesson this build can read is committed on `lastAnswerDay`. An
    /// unfinished lesson uses `canResume`. Anything else, including an
    /// unfinished review, is dropped.
    public static func sessionAction(
        for session: ActiveSessionSnapshot,
        in snapshot: ProgressSnapshot,
        content: ContentBundle,
        on today: LocalDay
    ) -> SessionStartup {
        if session.payloadVersion > ActiveSessionSnapshot.currentPayloadVersion {
            return .keep
        }
        if snapshot.completedSessions.contains(where: { $0.sessionID == session.sessionID }) {
            return .discard
        }
        if mustCommit(session) {
            guard let commit = sessionCommit(
                for: session,
                in: content,
                cards: snapshot.cards,
                lessonProgress: snapshot.lessonProgress,
                streak: snapshot.streak
            ) else {
                return .keep
            }
            return .commit(commit)
        }
        if canResume(session, on: today, contentVersion: content.contentVersion) {
            return .resume
        }
        return .discard
    }

    /// Loads `store`, commits or drops the active session, then reconciles
    /// cards with `content`.
    ///
    /// A throw from `load` or `commit` writes nothing further. A failed
    /// commit leaves the active session in place. A newer snapshot that
    /// `load` refuses is not overwritten. The reconciliation marker is
    /// written only when it changed, in the same save as any card changes.
    public static func run(
        store: any ProgressStore,
        content: ContentBundle,
        on today: LocalDay
    ) async throws -> ProgressSnapshot {
        var snapshot = try await store.load()
        if let session = snapshot.activeSession {
            switch sessionAction(for: session, in: snapshot, content: content, on: today) {
            case .commit(let commit):
                try await store.commit(commit)
                snapshot = try await store.load()
            case .discard:
                try await store.discardActiveSession()
                snapshot = try await store.load()
            case .resume, .keep:
                break
            }
        }
        let reconciled = reconcile(snapshot, with: content, on: today)
        let versionChanged = reconciled.snapshot.lastReconciledContentVersion
            != snapshot.lastReconciledContentVersion
        if !reconciled.cardChanges.isEmpty || versionChanged {
            try await store.applyReconciliation(
                reconciled.cardChanges,
                reconciledContentVersion: content.contentVersion
            )
            snapshot = try await store.load()
        }
        return snapshot
    }

    private static func aligned(_ card: ReviewCard, present: Set<ItemID>) -> ReviewCard {
        let state: ReviewCardState = present.contains(card.itemID) ? .active : .paused
        guard state != card.state else { return card }
        return ReviewCard(
            itemID: card.itemID,
            easeFactor: card.easeFactor,
            intervalDays: card.intervalDays,
            repetitions: card.repetitions,
            lapses: card.lapses,
            dueDay: card.dueDay,
            lastReviewedDay: card.lastReviewedDay,
            createdDay: card.createdDay,
            state: state,
            source: card.source
        )
    }

    private static func catchUpCard(
        itemID: ItemID,
        created: LocalDay,
        index: Int,
        on today: LocalDay
    ) -> ReviewCard {
        let offset = index / maximumNewCardsPerDay
        return ReviewCard(
            itemID: itemID,
            easeFactor: ReviewCard.initialEaseFactor,
            intervalDays: 0,
            repetitions: 0,
            lapses: 0,
            dueDay: today.adding(days: offset),
            lastReviewedDay: nil,
            createdDay: created,
            state: .active,
            source: .lesson
        )
    }
}
