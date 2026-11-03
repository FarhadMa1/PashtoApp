import Foundation
import Observation

/// Plays the pair timeline. Sleep is injectable so a test can run the sequence without waiting.
///
/// The view reads `steps` and `shakeToken`. `played` is the beats in the order they were applied.
@MainActor
@Observable
public final class PairMergeClock {
    public private(set) var steps: [ItemID: PairMergeStep] = [:]
    public private(set) var shakeToken = 0
    public private(set) var played: [Beat] = []

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored nonisolated(unsafe) private let sleep: @Sendable (TimeInterval) async -> Void

    public struct Beat: Equatable, Sendable {
        public var time: TimeInterval
        public var id: ItemID
        public var step: PairMergeStep

        public init(time: TimeInterval, id: ItemID, step: PairMergeStep) {
            self.time = time
            self.id = id
            self.step = step
        }
    }

    /// `sleep` waits for one gap. The default waits on the system clock.
    nonisolated public init(sleep: (@Sendable (TimeInterval) async -> Void)? = nil) {
        self.sleep = sleep ?? { seconds in
            let milliseconds = Int((seconds * 1000).rounded())
            try? await Task.sleep(for: .milliseconds(milliseconds))
        }
    }

    public func play(events: [(id: ItemID, mark: QuizResultMark)], reduceMotion: Bool) {
        task?.cancel()
        generation += 1
        let generation = generation
        var upcoming: [(time: TimeInterval, id: ItemID, step: PairMergeStep)] = []
        var next: [ItemID: PairMergeStep] = [:]
        var beats: [Beat] = []
        var shakes = false
        for event in events {
            let frames = PairMergePlan.frames(mark: event.mark, reduceMotion: reduceMotion)
            if let first = frames.first {
                next[event.id] = first.step
                beats.append(Beat(time: first.time, id: event.id, step: first.step))
            }
            for frame in frames where frame.time > 0 {
                upcoming.append((frame.time, event.id, frame.step))
            }
            if event.mark == .incorrect, !reduceMotion { shakes = true }
        }
        upcoming.sort { lhs, rhs in
            if lhs.time == rhs.time { return lhs.id.rawValue < rhs.id.rawValue }
            return lhs.time < rhs.time
        }
        steps = next
        played = beats
        if shakes { shakeToken += 1 }
        let frames = upcoming
        let pause = sleep
        task = Task { @MainActor [weak self] in
            var elapsed = 0.0
            for frame in frames {
                let wait = frame.time - elapsed
                if wait > 0.000_5 {
                    await pause(wait)
                }
                guard let self, !Task.isCancelled, self.generation == generation else { return }
                elapsed = frame.time
                self.steps[frame.id] = frame.step
                self.played.append(Beat(time: frame.time, id: frame.id, step: frame.step))
            }
        }
    }

    public func stop() {
        generation += 1
        task?.cancel()
        steps = [:]
        played = []
    }

    /// Waits until the current timeline has finished or been cancelled.
    public func waitUntilIdle() async {
        await task?.value
    }
}
