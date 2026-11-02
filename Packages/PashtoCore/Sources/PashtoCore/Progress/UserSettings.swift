/// Settings the learner can change. The usual goal is 10 new items.
public struct UserSettings: Codable, Hashable, Sendable {
    /// Ten new items, and transliteration shown. No placement test yet.
    public static let initial = UserSettings(
        dailyGoal: .regular,
        showTransliteration: true,
        placementTakenDay: nil
    )

    public let dailyGoal: DailyGoal
    public let showTransliteration: Bool
    /// Set when the learner takes the placement test, so it is not offered again.
    public let placementTakenDay: LocalDay?

    public init(dailyGoal: DailyGoal, showTransliteration: Bool, placementTakenDay: LocalDay?) {
        self.dailyGoal = dailyGoal
        self.showTransliteration = showTransliteration
        self.placementTakenDay = placementTakenDay
    }
}
