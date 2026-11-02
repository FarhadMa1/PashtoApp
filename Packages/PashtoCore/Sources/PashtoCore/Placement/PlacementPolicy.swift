/// The numbers that decide a placement test.
///
/// The standard test asks 5 questions in each of units 1, 2 and 3. Four
/// correct answers skip that unit. A lower score stops the test. The alphabet,
/// the first unit in the course, is never one of these units.
public struct PlacementPolicy: Hashable, Sendable {
    /// Questions asked for one unit.
    public var questionsPerUnit: Int
    /// Correct answers required to skip the unit. The count is out of `questionsPerUnit`.
    public var correctToSkip: Int
    /// How many units after the alphabet can be tested, in course order.
    ///
    /// 3 means units 1, 2 and 3. A later unit is not part of the test.
    public var unitCount: Int

    /// Five questions, four to skip, and units 1 through 3.
    public static let standard = PlacementPolicy(questionsPerUnit: 5, correctToSkip: 4, unitCount: 3)

    public init(questionsPerUnit: Int, correctToSkip: Int, unitCount: Int) {
        self.questionsPerUnit = questionsPerUnit
        self.correctToSkip = correctToSkip
        self.unitCount = unitCount
    }
}
