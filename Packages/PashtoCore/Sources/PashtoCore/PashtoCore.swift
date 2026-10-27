/// Pure-Swift module boundary for lesson content and, later, quiz logic.
///
/// This package must stay free of Apple-only frameworks so `swift test`
/// can run on Linux. Content types decode `Data`. They do not read files,
/// the clock, or the current locale.
public enum PashtoCore {
    /// Stable name the app target references so the package dependency stays linked.
    public static let moduleName = "PashtoCore"
}
