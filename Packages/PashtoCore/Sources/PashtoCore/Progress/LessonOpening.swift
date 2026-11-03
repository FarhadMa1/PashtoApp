import Foundation

/// One lesson open at a time.
///
/// `begin` is false while an earlier open has not finished. The caller ignores
/// that tap, so two taps cannot open two lessons. `end` allows the next open.
@MainActor
public final class LessonOpening {
    public private(set) var isOpening = false

    public init() {}

    /// True when this call may load and open a lesson.
    public func begin() -> Bool {
        guard !isOpening else { return false }
        isOpening = true
        return true
    }

    /// The open has finished, succeeded or failed.
    public func end() {
        isOpening = false
    }
}
