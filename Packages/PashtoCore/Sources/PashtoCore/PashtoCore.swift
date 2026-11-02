/// Pure-Swift module boundary for lesson content, quizzes, the daily plan, the lesson path, the streak, stored progress, and civil dates.
///
/// This package must stay free of Apple-only frameworks so `swift test`
/// can run on Linux. Content types decode `Data`. They do not read files
/// or the current locale. Only `SystemDateProvider` reads the process clock.
public enum PashtoCore {
    /// Stable name the app target references so the package dependency stays linked.
    public static let moduleName = "PashtoCore"
}
