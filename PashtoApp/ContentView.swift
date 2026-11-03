import PashtoCore
import SwiftUI

/// Root once progress has loaded.
///
/// `reviewStarted` is true after Welcome back's Start review. A lesson quiz
/// is shown when the caller has already built one. The session carries the
/// pronunciation setting it started with. Units that are not in
/// `release-units.json` are not part of that session. Tapping a released
/// lesson starts one. Finishing it shows the celebration first. Continue
/// then saves and returns here. Leaving early returns here without it.
/// An empty release list keeps the placeholder.
struct ContentView: View {
    var reviewStarted: Bool = false
    var quiz: LessonSession?
    var quizItems: [ContentItem] = []
    /// Lessons from the release list. Empty keeps the placeholder below.
    var lessons: [ReleasedLesson] = []
    var streakCount: Int = 0
    var streakFrom: Int = 0
    var streakToken: Int = 0
    var goalDone: Int = 0
    var goalFrom: Int = 0
    var goalTotal: Int = 10
    var goalToken: Int = 0
    var finishedLessonIDs: Set<LessonID> = []
    var freshLessonID: LessonID?
    var startLesson: (LessonID) -> Void = { _ in }
    var endSession: () -> Void = {}
    var answerSession: (LessonSession) -> Void = { _ in }
    var finishSession: (LessonSession) -> Void = { _ in }

    @State private var celebration: LessonSession?

    var body: some View {
        if let celebration {
            LessonFinishedView(session: celebration) {
                let finished = celebration
                self.celebration = nil
                finishSession(finished)
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
                onFinish: { celebration = $0 }
            )
        }
        .background(Lapis.background.ignoresSafeArea())
    }

    private var lessonList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    DailyGoalRing(done: goalDone, from: goalFrom, total: goalTotal, token: goalToken)
                    Spacer(minLength: 8)
                    StreakMark(count: streakCount, from: streakFrom, token: streakToken)
                }
                Text("Pashto")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Lapis.text)
                CoursePathList(
                    lessons: lessons,
                    finished: finishedLessonIDs,
                    freshLessonID: freshLessonID,
                    startLesson: startLesson
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Lapis.background.ignoresSafeArea())
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
    @State private var starShown = false
    @State private var girihShown = false
    @State private var skipped = false
    @State private var skipToken = 0
    @State private var correctShown = 0
    @State private var answeredShown = 0
    @State private var successHaptic = 0

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
        .sensoryFeedback(.success, trigger: successHaptic)
        .onAppear(perform: play)
        .task(id: skipToken) { await count() }
    }

    private func play() {
        if successHaptic == 0 { successHaptic = 1 }
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
    var done: Int
    var from: Int
    var total: Int
    var token: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var haptic = 0

    private var plan: GoalRingPlan {
        GoalRingPlan.plan(
            from: from,
            to: done,
            goal: total,
            reduceMotion: reduceMotion,
            voiceOver: voiceOver
        )
    }

    private var moves: Bool { !reduceMotion && !voiceOver }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Lapis.secondaryText.opacity(0.35), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: plan.toFraction)
                    .stroke(Lapis.ring, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(moves ? Motion.goalRing : nil, value: plan.toFraction)
                Octagram()
                    .fill(Lapis.badge)
                    .frame(width: 36, height: 36)
                Image(systemName: "checkmark")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Lapis.correct)
                    .scaleEffect(plan.showsCheck ? 1 : 0.4)
                    .opacity(plan.showsCheck ? 1 : 0)
                    .offset(x: 22, y: 22)
                    .animation(moves ? Motion.goalCheck : nil, value: plan.showsCheck)
                    .accessibilityHidden(true)
            }
            .frame(width: 64, height: 64)
            HStack(spacing: 0) {
                Text(done, format: .number)
                    .contentTransition(.numericText())
                Text(verbatim: "/\(max(total, 0))")
            }
            .font(.headline.weight(.bold).monospacedDigit())
            .foregroundStyle(Lapis.text)
            .animation(moves ? Motion.goalRing : nil, value: done)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: plan.spoken))
        .sensoryFeedback(.success, trigger: haptic)
        .onChange(of: token) { _, new in
            guard new > 0, done > from else { return }
            haptic += 1
        }
    }
}

/// The streak number and one pulse of the saffron star.
///
/// Reduce Motion fades the star over 0.2 s. VoiceOver and Reduce Motion both show the final number at once.
private struct StreakMark: View {
    var count: Int
    var from: Int
    var token: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var pulse = 0
    @State private var fade = 0
    @State private var haptic = 0

    private var rolls: Bool { !reduceMotion && !voiceOver }

    var body: some View {
        HStack(spacing: 8) {
            Octagram()
                .fill(Lapis.saffron)
                .frame(width: 28, height: 28)
                .modifier(StreakStarPulse(token: pulse))
                .modifier(StreakStarFade(token: fade))
                .accessibilityHidden(true)
            Text(count, format: .number)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(Lapis.text)
                .contentTransition(.numericText())
                .animation(rolls ? .easeOut(duration: CelebrationMotion.streakPulse) : nil, value: count)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(StreakRoll.plan(from: from, to: count, reduceMotion: true, voiceOver: true).spoken)"))
        .sensoryFeedback(.impact(weight: .light), trigger: haptic)
        .onChange(of: token) { _, new in
            guard new > 0, count != from else { return }
            haptic += 1
            if reduceMotion {
                fade += 1
            } else if !voiceOver {
                pulse += 1
            }
        }
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

/// Reduce Motion: the star fades in over the shared 0.2 s. The number does not move.
private struct StreakStarFade: ViewModifier {
    var token: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 1.0, trigger: token) { view, opacity in
            view.opacity(opacity)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0, duration: 0.01)
                LinearKeyframe(1, duration: QuizMotion.reduceMotionFade)
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
    var freshLessonID: LessonID?
    var startLesson: (LessonID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grownID: LessonID?

    init(
        lessons: [ReleasedLesson],
        finished: Set<LessonID>,
        freshLessonID: LessonID?,
        startLesson: @escaping (LessonID) -> Void
    ) {
        self.lessons = lessons
        self.finished = finished
        self.freshLessonID = freshLessonID
        self.startLesson = startLesson
        // The segment already on screen stays filled. A later finish is what animates.
        _grownID = State(initialValue: freshLessonID)
    }

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
                .modifier(FinishedLessonValue(finished: finished.contains(lesson.id)))
            }
        }
        .onChange(of: freshLessonID) { _, new in
            guard let new, grownID != new else { return }
            if Motion.pathFillAnimation(reduceMotion: reduceMotion) == nil {
                grownID = new
            } else {
                withAnimation(Motion.pathFill) { grownID = new }
            }
        }
    }

    private func pathNode(_ lesson: ReleasedLesson) -> some View {
        ZStack {
            PathNodeHalo(active: lesson.id == nextID)
            Octagram()
                .fill(nodeFill(lesson.id))
                .frame(width: 36, height: 36)
            if finished.contains(lesson.id) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Lapis.saffronInk)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 44, height: 44)
    }

    private func nodeFill(_ id: LessonID) -> Color {
        if finished.contains(id) { return Lapis.ring }
        if id == nextID { return Lapis.badge }
        return Lapis.secondaryText.opacity(0.45)
    }

    private func pathConnector(filled: Bool) -> some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Lapis.secondaryText.opacity(0.35))
            Capsule()
                .fill(Lapis.ring)
                .frame(height: filled ? 28 : 0)
        }
        .frame(width: 4, height: 28)
        .animation(Motion.pathFillAnimation(reduceMotion: reduceMotion), value: filled)
        .accessibilityHidden(true)
    }

    private func segmentFilled(_ id: LessonID) -> Bool {
        guard finished.contains(id) else { return false }
        if id == freshLessonID { return grownID == id }
        return true
    }
}

/// A finished lesson reuses the existing "Correct" value. Unfinished lessons add nothing.
private struct FinishedLessonValue: ViewModifier {
    var finished: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if finished {
            content.accessibilityValue(Text("quiz.feedback.correct"))
        } else {
            content
        }
    }
}

/// The 1.6 s pulse on the next lesson. Reduce Motion draws a still ring instead.
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
                    .onAppear {
                        withAnimation(Motion.pathPulse) { pulse = true }
                    }
            } else if active, style == .ring {
                Circle()
                    .strokeBorder(Lapis.badge, lineWidth: 3)
                    .padding(-3)
            }
        }
        .frame(width: 36, height: 36)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    ContentView()
}
