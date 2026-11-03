import PashtoCore
import SwiftUI

/// Root once progress has loaded.
///
/// `reviewStarted` is true after Welcome back's Start review. A lesson quiz
/// is shown when the caller has already built one. The session carries the
/// pronunciation setting it started with. Units that are not in
/// `release-units.json` are not part of that session. Tapping a released
/// lesson starts one. The last answer saves the lesson and shows the
/// celebration. Continue only closes that celebration. Leaving early returns
/// here without it.
/// An empty release list keeps the placeholder.
struct ContentView: View {
    var reviewStarted: Bool = false
    var quiz: LessonSession?
    var quizItems: [ContentItem] = []
    /// Lessons from the release list. Empty keeps the placeholder below.
    var lessons: [ReleasedLesson] = []
    var streakCount: Int = 0
    var goalDone: Int = 0
    var goalTotal: Int = 10
    var finishedLessonIDs: Set<LessonID> = []
    var pendingHomeMotion: PendingHomeMotion?
    var consumeHomeMotion: () -> Void = {}
    var startLesson: (LessonID) -> Void = { _ in }
    var endSession: () -> Void = {}
    var answerSession: (LessonSession) -> Void = { _ in }
    var finishSession: (LessonSession) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var celebration: LessonSession?
    /// The cue being played. It outlives `pendingHomeMotion`, which is cleared after the play.
    @State private var heldMotion: PendingHomeMotion?
    @State private var streakAtFinal = false
    @State private var goalAtFinal = false
    @State private var pathAtFinal = false
    @State private var streakPulse = 0
    @State private var goalHaptic = 0

    var body: some View {
        if let celebration {
            LessonFinishedView(session: celebration) {
                self.celebration = nil
            }
            .accessibilityIdentifier(reviewStarted ? "short-review" : "ready")
        } else if let quiz, !quiz.tasks.isEmpty {
            quizSession(quiz)
                .accessibilityIdentifier(reviewStarted ? "short-review" : "ready")
        } else if lessons.isEmpty {
            Text("Pashto")
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Lapis.background.ignoresSafeArea())
                .accessibilityIdentifier(reviewStarted ? "short-review" : "ready")
        } else {
            lessonList
                .accessibilityIdentifier(reviewStarted ? "short-review" : "ready")
        }
    }

    private func quizSession(_ quiz: LessonSession) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: endSession) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.backward")
                            .accessibilityHidden(true)
                        Text("Pashto")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Lapis.text)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Pashto"))
                .accessibilityAddTraits(.isButton)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            QuizScreen(
                session: quiz,
                items: quizItems,
                onAnswer: answerSession,
                onFinish: { celebration = $0; finishSession($0) }
            )
        }
        .background(Lapis.background.ignoresSafeArea())
    }

    private var lessonList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    DailyGoalRing(shown: goalShown, done: goalDone, total: goalTotal)
                    Spacer(minLength: 8)
                    StreakMark(shown: streakShown, count: streakCount, pulse: streakPulse)
                }
                Text("Pashto")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Lapis.text)
                CoursePathList(
                    lessons: lessons,
                    finished: finishedLessonIDs,
                    waitingLessonID: pathWaitingID,
                    startLesson: startLesson
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Lapis.background.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: goalHaptic)
        .task(id: pendingHomeMotion?.id) {
            await playHomeMotion()
        }
    }

    private var streakShown: Int {
        playingValue(from: pendingHomeMotion?.streakFrom, final: streakCount, atFinal: streakAtFinal)
    }

    private var goalShown: Int {
        playingValue(from: pendingHomeMotion?.goalFrom, final: goalDone, atFinal: goalAtFinal)
    }

    /// The finished lesson whose path segment has not filled yet.
    private var pathWaitingID: LessonID? {
        guard !reduceMotion, !voiceOver, let pending = pendingHomeMotion else { return nil }
        guard heldMotion?.id != pending.id || !pathAtFinal else { return nil }
        return pending.lessonID
    }

    /// The from-value while `pending` is the cue still being played.
    ///
    /// Reduce Motion and VoiceOver return the live count. Once the cue is
    /// consumed, the live count stays.
    private func playingValue(from: Int?, final: Int, atFinal: Bool) -> Int {
        guard !reduceMotion, !voiceOver, let pending = pendingHomeMotion, let from else { return final }
        if heldMotion?.id != pending.id || !atFinal { return from }
        return final
    }

    /// Starts at the from-values already on screen, then moves to the live counts.
    ///
    /// Reduce Motion does not animate. VoiceOver shows the final value at once.
    /// The goal haptic plays only when the count crosses the limit. The cue is
    /// then dropped, so a later visit does not play it again.
    private func playHomeMotion() async {
        guard let pending = pendingHomeMotion else { return }
        let crossed = DailyGoalCrossing.reached(from: pending.goalFrom, to: goalDone, limit: goalTotal)
        let streakChanges = pending.streakFrom != streakCount
        if reduceMotion || voiceOver {
            heldMotion = pending
            streakAtFinal = true
            goalAtFinal = true
            pathAtFinal = true
        } else {
            heldMotion = pending
            streakAtFinal = false
            goalAtFinal = false
            pathAtFinal = false
            await Task.yield()
            guard !Task.isCancelled, pendingHomeMotion?.id == pending.id else { return }
            if streakChanges { streakPulse += 1 }
            withAnimation(.easeOut(duration: CelebrationMotion.streakPulse)) {
                streakAtFinal = true
            }
            withAnimation(Motion.goalRing) {
                goalAtFinal = true
            }
            withAnimation(Motion.pathFill) {
                pathAtFinal = true
            }
        }
        if crossed { goalHaptic += 1 }
        consumeHomeMotion()
    }
}

/// Saffron octagram, girih behind it, and the first-try numbers.
///
/// The pieces start together and finish within the girih's 0.8 s. A tap skips
/// to the end. Continue stays outside that tap and is never disabled.
/// Titles, praise, and captions that are not already in the catalog are omitted.
private struct LessonFinishedView: View {
    var session: LessonSession
    var onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.colorScheme) private var colorScheme
    @State private var starShown = false
    @State private var girihShown = false
    @State private var skipped = false
    @State private var skipToken = 0
    @State private var correctShown = 0
    @State private var answeredShown = 0

    private var stats: LessonFinishStats { LessonFinishStats.measure(session) }

    var body: some View {
        LapisScreen {
            VStack(spacing: 20) {
                ZStack {
                    GirihPattern()
                        .opacity(girihShown ? 1 : 0)
                    Octagram()
                        .fill(Lapis.saffron)
                        .frame(width: 104, height: 104)
                        .overlay {
                            if colorScheme == .light {
                                Octagram().strokeBorder(Lapis.ring, lineWidth: 1)
                            }
                        }
                        .overlay {
                            Image(systemName: "checkmark")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(Lapis.saffronInk)
                        }
                        .scaleEffect(reduceMotion ? 1 : (starShown ? 1 : 0.3))
                        .rotationEffect(.degrees(reduceMotion ? 0 : (starShown ? 0 : -45)))
                        .opacity(starShown ? 1 : 0)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .background(Lapis.heroGradient)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .accessibilityHidden(true)

                HStack(spacing: 28) {
                    Text(answeredShown, format: .number)
                    HStack(spacing: 0) {
                        Text(correctShown, format: .number)
                        Text(verbatim: "/\(stats.answered)")
                    }
                }
                .font(.largeTitle.weight(.bold).monospacedDigit())
                .foregroundStyle(Lapis.text)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, minHeight: 420, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture(perform: skip)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(stats.correct)/\(stats.answered)"))
        } footer: {
            Button(action: onContinue) {
                Text("quiz.continue.button")
            }
            .buttonStyle(SaffronButtonStyle())
        }
        .onAppear(perform: play)
        .task(id: skipToken) { await count() }
    }

    private func play() {
        let girih = GirihEntrance.style(reduceMotion: reduceMotion)
        if girih == .still {
            girihShown = true
        } else if let animation = Motion.girihAnimation(reduceMotion: reduceMotion) {
            withAnimation(animation) { girihShown = true }
        }
        withAnimation(Motion.lessonStarAnimation(reduceMotion: reduceMotion)) {
            starShown = true
        }
    }

    private func skip() {
        guard !skipped else { return }
        skipped = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            starShown = true
            girihShown = true
            correctShown = stats.correct
            answeredShown = stats.answered
        }
        skipToken += 1
    }

    private func count() async {
        let correct = CounterPlan.plan(
            target: stats.correct,
            reduceMotion: reduceMotion,
            voiceOver: voiceOver,
            skipped: skipped
        )
        let answered = CounterPlan.plan(
            target: stats.answered,
            reduceMotion: reduceMotion,
            voiceOver: voiceOver,
            skipped: skipped
        )
        correctShown = correct.start
        answeredShown = answered.start
        guard correct.animates || answered.animates else { return }
        let steps = max(correct.end, answered.end)
        guard steps > 0 else { return }
        let slice = CelebrationMotion.countUp / Double(steps)
        for step in 1...steps {
            try? await Task.sleep(for: .seconds(slice))
            if Task.isCancelled || skipped { break }
            if correct.animates { correctShown = min(step, correct.end) }
            if answered.animates { answeredShown = min(step, answered.end) }
        }
        if !Task.isCancelled {
            correctShown = correct.end
            answeredShown = answered.end
        }
    }
}

/// New items today, drawn as a ring around the lapis octagram.
///
/// The fraction is the stored count over the stored limit. Reduce Motion and
/// VoiceOver show the end at once. The check appears when the count reaches the limit.
private struct DailyGoalRing: View {
    var shown: Int
    var done: Int
    var total: Int

    private var fraction: Double {
        DailyGoalCrossing.fraction(shown, limit: total)
    }

    private var showsCheck: Bool { total > 0 && shown >= total }

    private var spoken: String {
        GoalRingPlan.plan(
            from: shown,
            to: done,
            goal: total,
            reduceMotion: true,
            voiceOver: true
        ).spoken
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Lapis.muted, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Lapis.ring, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Octagram()
                    .fill(Lapis.badge)
                    .frame(width: 36, height: 36)
                Image(systemName: "checkmark")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Lapis.correct)
                    .scaleEffect(showsCheck ? 1 : 0.4)
                    .opacity(showsCheck ? 1 : 0)
                    .offset(x: 22, y: 22)
                    .accessibilityHidden(true)
            }
            .frame(width: 64, height: 64)
            HStack(spacing: 0) {
                Text(shown, format: .number)
                    .contentTransition(.numericText())
                Text(verbatim: "/\(max(total, 0))")
            }
            .font(.headline.weight(.bold).monospacedDigit())
            .foregroundStyle(Lapis.text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }
}

/// The streak number and one pulse of the saffron star.
///
/// Reduce Motion fades the star over 0.2 s. VoiceOver and Reduce Motion both show the final number at once.
private struct StreakMark: View {
    var shown: Int
    var count: Int
    var pulse: Int

    var body: some View {
        HStack(spacing: 8) {
            Octagram()
                .fill(Lapis.saffron)
                .frame(width: 28, height: 28)
                .modifier(StreakStarPulse(token: pulse))
                .accessibilityHidden(true)
            Text(shown, format: .number)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(Lapis.text)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(StreakRoll.plan(from: shown, to: count, reduceMotion: true, voiceOver: true).spoken)"))
    }
}

/// Scale 0.6, through 1.25, back to 1. One play, about 0.45 s.
private struct StreakStarPulse: ViewModifier {
    var token: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 1.0, trigger: token) { view, scale in
            view.scaleEffect(token == 0 ? 1 : scale)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0.6, duration: 0.01)
                CubicKeyframe(1.25, duration: CelebrationMotion.streakPulse * 0.59)
                CubicKeyframe(1.0, duration: CelebrationMotion.streakPulse * 0.40)
            }
        }
    }
}

/// Lessons in course order, with a fill between a finished lesson and the next.
///
/// Every row stays tappable. The next lesson pulses, or shows a still ring when Reduce Motion is on.
private struct CoursePathList: View {
    var lessons: [ReleasedLesson]
    var finished: Set<LessonID>
    /// The lesson whose connector stays empty until the fill animation runs.
    var waitingLessonID: LessonID?
    var startLesson: (LessonID) -> Void

    private var nextID: LessonID? {
        CoursePathMotion.next(in: lessons.map(\.id), finished: finished)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                Button {
                    startLesson(lesson.id)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            pathNode(lesson)
                            if index < lessons.count - 1 {
                                pathConnector(filled: segmentFilled(lesson.id))
                            }
                        }
                        Text(verbatim: lesson.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Lapis.text)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(lesson.id.rawValue)
            }
        }
    }

    private func pathNode(_ lesson: ReleasedLesson) -> some View {
        ZStack {
            PathNodeHalo(active: lesson.id == nextID)
            nodeShape(lesson.id)
            nodeMark(lesson.id)
        }
        .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private func nodeMark(_ id: LessonID) -> some View {
        if finished.contains(id) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(Lapis.saffronInk)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func nodeShape(_ id: LessonID) -> some View {
        if finished.contains(id) {
            Octagram()
                .fill(Lapis.ring)
                .frame(width: 36, height: 36)
        } else if id == nextID {
            Octagram()
                .fill(Lapis.badge)
                .frame(width: 36, height: 36)
        } else {
            Octagram()
                .strokeBorder(Lapis.muted, lineWidth: 2)
                .frame(width: 36, height: 36)
        }
    }

    private func pathConnector(filled: Bool) -> some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Lapis.muted)
            Capsule()
                .fill(Lapis.ring)
                .frame(height: filled ? 28 : 0)
        }
        .frame(width: 4, height: 28)
        .accessibilityHidden(true)
    }

    private func segmentFilled(_ id: LessonID) -> Bool {
        guard finished.contains(id) else { return false }
        return id != waitingLessonID
    }
}

/// The 1.6 s pulse on the next lesson. Reduce Motion draws a still ring instead.
///
/// Turning Reduce Motion off starts the pulse again. A pulse that already
/// finished at opacity 0 would otherwise stay invisible.
private struct PathNodeHalo: View {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let style = CoursePathMotion.NodeStyle.style(reduceMotion: reduceMotion)
        ZStack {
            if active, style == .pulse {
                Circle()
                    .stroke(Lapis.badge, lineWidth: 3)
                    .scaleEffect(pulse ? 1.45 : 0.9)
                    .opacity(pulse ? 0 : 0.55)
            } else if active, style == .ring {
                Circle()
                    .strokeBorder(Lapis.badge, lineWidth: 3)
                    .padding(-3)
            }
        }
        .frame(width: 36, height: 36)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: restartPulse)
        .onChange(of: reduceMotion) { _, _ in restartPulse() }
        .onChange(of: active) { _, _ in restartPulse() }
    }

    private func restartPulse() {
        let pulses = active && CoursePathMotion.NodeStyle.style(reduceMotion: reduceMotion) == .pulse
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { pulse = false }
        guard pulses else { return }
        withAnimation(Motion.pathPulse) { pulse = true }
    }
}

#Preview {
    ContentView()
}
