/// The numbers that decide a placement test.
///
/// The standard test asks 5 questions in each of the first four units after
/// the alphabet: The basics, Greetings, Introducing yourself, and Family. Four
/// correct answers skip that unit. A lower score stops the test. The alphabet,
/// the first unit in the course, is never one of these units.
public struct PlacementPolicy: Hashable, Sendable {
    /// Questions asked for one unit.
    public var questionsPerUnit: Int
    /// Correct answers required to skip the unit. The count is out of `questionsPerUnit`.
    public var correctToSkip: Int
    /// How many units after the alphabet can be tested, in course order.
    ///
    /// 4 means the first four units after the alphabet. A later unit is not part of the test.
    public var unitCount: Int

    /// Five questions, four to skip, and the first four units after the alphabet.
    public static let standard = PlacementPolicy(questionsPerUnit: 5, correctToSkip: 4, unitCount: 4)

    public init(questionsPerUnit: Int, correctToSkip: Int, unitCount: Int) {
        self.questionsPerUnit = questionsPerUnit
        self.correctToSkip = correctToSkip
        self.unitCount = unitCount
    }
}
