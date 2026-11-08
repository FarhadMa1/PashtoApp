import Foundation

/// Which background lesson save is the one still running.
///
/// `begin` starts one attempt and returns its token. A later `begin` keeps
/// the same system task. `end(matching:)` stops it only when that token is
/// still the latest, so an earlier attempt cannot end the later save.
/// Ending a token that already ended does nothing.
public struct BackgroundSaveOrder: Equatable, Sendable {
    public private(set) var token = 0
    public private(set) var running = false

    public init() {}

    /// The token this attempt holds. The save is running afterwards.
    public mutating func begin() -> Int {
        token += 1
        running = true
        return token
    }

    /// True when `expected` is the latest begin and the task should stop.
    public mutating func end(matching expected: Int) -> Bool {
        guard running, expected == token else { return false }
        running = false
        return true
    }
}
