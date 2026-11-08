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
    /// From-values first, then the live counts. Consuming the cue does not change these.
    @State private var playback = HomeMotionPlayback()
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
                    DailyGoalRing(
                        shown: goalShown,
                        done: goalDone,
                        total: goalTotal,
                        animates: animatesHomeMotion
                    )
                    Spacer(minLength: 8)
                    StreakMark(
                        shown: streakShown,
                        count: streakCount,
                        pulse: streakPulse,
                        animates: animatesHomeMotion
                    )
                }
                Text("Pashto")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Lapis.text)
                CoursePathList(
                    lessons: lessons,
                    finished: finishedLessonIDs,
                    waitingLessonID: pathWaitingID,
                    animates: animatesHomeMotion,
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
        playback.displayedStreak(
            live: streakCount,
            pending: pendingHomeMotion,
            reduceMotion: reduceMotion,
            voiceOver: voiceOver
        )
    }

    private var goalShown: Int {
        playback.displayedGoal(
            live: goalDone,
            pending: pendingHomeMotion,
            reduceMotion: reduceMotion,
            voiceOver: voiceOver
        )
    }

    /// The finished lesson whose path segment has not filled yet.
    private var pathWaitingID: LessonID? {
        playback.waitingLessonID(
            pending: pendingHomeMotion,
            reduceMotion: reduceMotion,
            voiceOver: voiceOver
        )
    }

    /// Reduce Motion and VoiceOver do not animate. Everyone else does.
    ///
    /// The modifiers stay attached while the from-values are on screen, so the
    /// later change to the live counts has an animation to use. A new cue
    /// already shows its own from-values on the first frame, before this task
    /// runs. Clearing the cue does not change the values those modifiers watch.
    private var animatesHomeMotion: Bool {
        !reduceMotion && !voiceOver
    }

    /// Shows the from-values, lets that frame render, then moves to the live counts.
    ///
    /// The cue stays pending through the from-frame. It is consumed only once
    /// the live values are already what the screen shows, so that clear cannot
    /// jump the animation. A cue that has played is left alone on a later visit.
    /// Reduce Motion and VoiceOver show the live values at once.
    private func playHomeMotion() async {
        let pending = pendingHomeMotion
        var transaction = Transaction()
        transaction.disablesAnimations = true
        let opening = withTransaction(transaction) {
            playback.prepare(pending, reduceMotion: reduceMotion, voiceOver: voiceOver)
        }
        switch opening {
        case .none:
            return
        case .jumpToFinal(let motion):
            noteGoalCrossing(motion)
            consumePlayedCue(motion)
        case .holdFrom(let motion):
            await Task.yield()
            guard !Task.isCancelled, pendingHomeMotion?.id == motion.id else { return }
            let animated = !reduceMotion && !voiceOver
            let next = playback.advance(afterRenderingFrom: motion.id, animated: animated)
            guard next.consumesCue else { return }
            if animated, motion.streakFrom != streakCount { streakPulse += 1 }
            noteGoalCrossing(motion)
            consumePlayedCue(motion)
        case .animateToFinal:
            return
        }
    }

    private func noteGoalCrossing(_ motion: PendingHomeMotion) {
        let crossed = DailyGoalCrossing.reached(from: motion.goalFrom, to: goalDone, limit: goalTotal)
        if crossed { goalHaptic += 1 }
    }

    private func consumePlayedCue(_ motion: PendingHomeMotion) {
        guard pendingHomeMotion?.id == motion.id else { return }
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
    var animates: Bool

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
                    .animation(animates ? Motion.goalRing : nil, value: fraction)
                Octagram()
                    .fill(Lapis.badge)
                    .frame(width: 36, height: 36)
                Image(systemName: "checkmark")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Lapis.correct)
                    .scaleEffect(showsCheck ? 1 : 0.4)
                    .opacity(showsCheck ? 1 : 0)
                    .offset(x: 22, y: 22)
                    .animation(animates ? Motion.goalCheck : nil, value: showsCheck)
                    .accessibilityHidden(true)
            }
            .frame(width: 64, height: 64)
            HStack(spacing: 0) {
                Text(shown, format: .number)
                    .contentTransition(.numericText())
                    .animation(animates ? Motion.goalRing : nil, value: shown)
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
/// Reduce Motion and VoiceOver show the final number at once and do not pulse the star.
private struct StreakMark: View {
    var shown: Int
    var count: Int
    var pulse: Int
    var animates: Bool

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
                .animation(animates ? .easeOut(duration: CelebrationMotion.streakPulse) : nil, value: shown)
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
    var animates: Bool
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
                .animation(animates ? Motion.pathFill : nil, value: filled)
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
