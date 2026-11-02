/// Clamps stored progress into the range the rest of the core accepts.
///
/// `load()` calls this. A future SwiftData store calls the same function
/// after it reads a row, so a bad value does not stay in the snapshot the
/// logic sees. The stored row is not rewritten here.
///
/// Freezes outside 0...2 move to the nearest end. A daily goal that is not
/// 5, 10, or 15 becomes the standard goal, 10. Ease below 1.3 and at least 0
/// becomes 1.3. Ease that is negative, NaN, or infinite becomes the starting
/// ease, 2.5. A negative interval becomes 0, the interval of a new card.
/// Repetitions, lapses, the score, and the freeze counter are left as stored.
public func validated(_ snapshot: ProgressSnapshot) -> ProgressSnapshot {
    let cards = snapshot.cards.map(validatedCard)
    let streak = validatedStreak(snapshot.streak)
    let settings = UserSettings(
        dailyGoal: validatedDailyGoal(snapshot.settings.dailyGoal.rawValue),
        showTransliteration: snapshot.settings.showTransliteration,
        placementTakenDay: snapshot.settings.placementTakenDay
    )
    if cards == snapshot.cards, streak == snapshot.streak, settings == snapshot.settings {
        return snapshot
    }
    return ProgressSnapshot(
        snapshotVersion: snapshot.snapshotVersion,
        contentVersion: snapshot.contentVersion,
        cards: cards,
        lessonProgress: snapshot.lessonProgress,
        streak: streak,
        settings: settings,
        activeSession: snapshot.activeSession,
        completedSessions: snapshot.completedSessions,
        lastReconciledContentVersion: snapshot.lastReconciledContentVersion,
        latestObservedDay: snapshot.latestObservedDay
    )
}

/// 5, 10, and 15 stay. Any other integer becomes `.regular` (10).
///
/// SwiftData stores the goal as an integer. The typed settings cannot hold
/// a value outside the enum, so the store calls this while reading the column.
public func validatedDailyGoal(_ rawValue: Int) -> DailyGoal {
    DailyGoal(rawValue: rawValue) ?? .regular
}

private func validatedCard(_ card: ReviewCard) -> ReviewCard {
    let ease = validatedEase(card.easeFactor)
    let interval = validatedInterval(card.intervalDays)
    if ease == card.easeFactor, interval == card.intervalDays {
        return card
    }
    return ReviewCard(
        itemID: card.itemID,
        easeFactor: ease,
        intervalDays: interval,
        repetitions: card.repetitions,
        lapses: card.lapses,
        dueDay: card.dueDay,
        lastReviewedDay: card.lastReviewedDay,
        createdDay: card.createdDay,
        state: card.state,
        source: card.source
    )
}

private func validatedStreak(_ streak: StreakState) -> StreakState {
    let freezes = min(max(streak.freezes, 0), StreakState.maximumFreezes)
    if freezes == streak.freezes { return streak }
    return StreakState(
        current: streak.current,
        longest: streak.longest,
        lastActiveDay: streak.lastActiveDay,
        freezes: freezes,
        daysTowardNextFreeze: streak.daysTowardNextFreeze,
        freezeUsedDays: streak.freezeUsedDays
    )
}

private func validatedEase(_ ease: Double) -> Double {
    guard ease.isFinite, ease >= 0 else { return ReviewCard.initialEaseFactor }
    if ease < ReviewCard.minimumEaseFactor { return ReviewCard.minimumEaseFactor }
    return ease
}

private func validatedInterval(_ interval: Int) -> Int {
    interval < 0 ? 0 : interval
}
