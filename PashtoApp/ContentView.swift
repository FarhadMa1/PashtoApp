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
    /// Rescue and freeze events not yet claimed. Empty after they play, and empty on a relaunch.
    var pendingStreakEvents: [StreakEventID] = []
    var claimStreakEvents: (StreakEventID.Kind) -> [StreakEventID] = { _ in [] }
    var startLesson: (LessonID) -> Void = { _ in }
    var endSession: () -> Void = {}
    var answerSession: (LessonSession) -> Void = { _ in }
    var finishSession: (LessonSession) -> Void = { _ in }
    /// Learned word for the local date. Nil omits the card. There is no empty-state line.
    var dailyWord: DailyWord? = nil
    /// Learn or phrases cards. Nil keeps the quiz or the home. Closing it does not end a quiz.
    var study: StudyDeck? = nil
    var studyNext: () -> StudyStep = { .ignored }
    var studyShowMeaning: () -> StudyStep = { .ignored }
    /// Last learn card. Opens the next lesson. The label stays Next.
    var studyOpenNextLesson: () -> Void = {}
    var studyStartPractice: () -> Void = {}
    var studySkip: () -> Void = {}
    var closeStudy: () -> Void = {}
    /// Learn cards from the released basics unit. The sheet only reads this list.
    var basicsCards: [StudyCard] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var celebration: LessonSession?
    /// From-values first, then the live counts. Consuming the cue does not change these.
    @State private var playback = HomeMotionPlayback()
    @State private var streakPulse = 0
    @State private var goalHaptic = 0
    /// The freeze star card. Cleared when it finishes, when it is skipped, and when the home goes away.
    @State private var freezeCelebration = false
    @State private var basicsOpen = false

    var body: some View {
        if let celebration {
            LessonFinishedView(session: celebration) {
                self.celebration = nil
            }
            .accessibilityIdentifier(reviewStarted ? "short-review" : "ready")
        } else if let study {
            StudyCardScreen(
                deck: study,
                onNext: studyNext,
                onShowMeaning: studyShowMeaning,
                onOpenNextLesson: studyOpenNextLesson,
                onStartPractice: studyStartPractice,
                onSkip: studySkip,
                onBack: closeStudy
            )
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
        VStack(spacing: 0) {
            homeHeader
            lessonScroll
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Lapis.background.ignoresSafeArea())
        .sheet(isPresented: $basicsOpen) {
            BasicsSheet(cards: basicsCards)
        }
        .sensoryFeedback(.success, trigger: goalHaptic)
        .onDisappear { freezeCelebration = false }
        .task(id: pendingHomeMotion?.id) {
            await playHomeMotion()
        }
    }

    /// Stays on screen while the path scrolls, including through the middle of a unit.
    private var homeHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Pashto")
                .font(.title3.weight(.bold))
                .foregroundStyle(Lapis.badgeInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button {
                basicsOpen = true
            } label: {
                Text(verbatim: ApprovedBasicsCopy.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Lapis.badgeInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Lapis.badgeInk, lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("basics-button")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 0,
                    bottomLeading: 26,
                    bottomTrailing: 26,
                    topTrailing: 0
                ),
                style: .continuous
            )
            .fill(Lapis.badge)
            .ignoresSafeArea(edges: .top)
        }
    }

    private var lessonScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    DailyGoalRing(
                        shown: goalShown,
                        total: goalTotal,
                        animates: animatesHomeMotion
                    )
                    Spacer(minLength: 8)
                    StreakMark(
                        shown: streakShown,
                        count: streakCount,
                        pulse: streakPulse,
                        animates: animatesHomeMotion,
                        pendingEvents: pendingStreakEvents,
                        claimEvents: claimStreakEvents,
                        onFreezeEarned: { freezeCelebration = true }
                    )
                }
                if freezeCelebration {
                    FreezeEarnedCelebration(count: streakCount, onDismiss: { freezeCelebration = false })
                }
                Text(verbatim: dailyGoalSpeech(done: goalShown))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Lapis.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: dailyGoalSpeech(done: goalDone)))
                if let dailyWord {
                    DailyWordCard(word: dailyWord)
                }
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

    /// New words against the stored limit. `done` is the count this label names.
    private func dailyGoalSpeech(done: Int) -> String {
        CelebrationCopy.dailyGoalSpoken(
            done: done,
            goal: goalTotal,
            title: ApprovedCopy.dailyGoal,
            one: ApprovedCopy.wordOne,
            other: ApprovedCopy.wordOther,
            toGo: ApprovedCopy.toGo,
            goalReached: ApprovedCopy.goalReached
        )
    }
}

/// Saffron octagram, girih behind it, and the first-try numbers.
///
/// The pieces start together and finish within the girih's 0.8 s. A tap skips
/// to the end. Continue stays outside that tap and is never disabled.
/// VoiceOver focuses the result once. That label is the final text, so the
/// count-up is not read and a second announcement is not posted.
private struct LessonFinishedView: View {
    var session: LessonSession
    var onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.colorScheme) private var colorScheme
    @AccessibilityFocusState private var resultFocused: Bool
    @State private var starShown = false
    @State private var girihShown = false
    @State private var skipped = false
    @State private var skipToken = 0
    @State private var correctShown = 0
    @State private var didFocusResult = false

    private var stats: LessonFinishStats { LessonFinishStats.measure(session) }
    private var praise: LessonPraise { LessonPraise.select(lessonID: session.lessonID) }
    private var resultLayout: CelebrationResultLayout {
        CelebrationCopy.resultLayout(
            stats: stats,
            reduceMotion: reduceMotion,
            voiceOver: voiceOver,
            skipped: skipped,
            label: ApprovedCopy.correct
        )
    }

    /// Final correct count, praise, and pronunciation when this session shows it.
    /// The answered total is only the denominator of the labelled fraction.
    private var resultSpeech: String {
        CelebrationCopy.accessibleResult(
            stats: stats,
            praise: praise,
            showsPronunciation: true,
            reduceMotion: reduceMotion,
            voiceOver: voiceOver,
            title: ApprovedCopy.lessonComplete,
            correct: ApprovedCopy.correct
        )
    }

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

                Text(verbatim: ApprovedCopy.lessonComplete)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Lapis.text)
                    .frame(maxWidth: .infinity)
                HStack {
                    Spacer(minLength: 0)
                    PashtoLine(
                        text: praise.pashto,
                        pronunciation: praise.pronunciation,
                        arabic: true
                    )
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Lapis.text)
                    Spacer(minLength: 0)
                }
                VStack(spacing: 2) {
                    HStack(spacing: 0) {
                        Text(correctShown, format: .number)
                        Text(verbatim: "/\(resultLayout.answeredTotal)")
                    }
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                    Text(verbatim: resultLayout.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Lapis.secondaryText)
                }
                .foregroundStyle(Lapis.text)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, minHeight: 420, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture(perform: skip)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: resultSpeech))
            .accessibilityFocused($resultFocused)
        } footer: {
            Button(action: onContinue) {
                Text("quiz.continue.button")
            }
            .buttonStyle(SaffronButtonStyle())
        }
        .onAppear(perform: play)
        .task(id: skipToken) { await count() }
        .task {
            guard !didFocusResult else { return }
            didFocusResult = true
            resultFocused = true
        }
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
        }
        skipToken += 1
    }

    private func count() async {
        let layout = resultLayout
        let correct = layout.correctPlan
        correctShown = correct.start
        guard correct.animates else { return }
        let steps = max(correct.end, layout.answeredTotal)
        guard steps > 0 else { return }
        let slice = CelebrationMotion.countUp / Double(steps)
        for step in 1...steps {
            try? await Task.sleep(for: .seconds(slice))
            if Task.isCancelled || skipped { break }
            correctShown = min(step, correct.end)
        }
        if !Task.isCancelled {
            correctShown = correct.end
        }
    }
}

/// New items today, drawn as a ring around the lapis octagram.
///
/// The fraction is the stored count over the stored limit. Reduce Motion and
/// VoiceOver show the end at once. The check appears when the count reaches the limit.
/// The ring is not an accessibility element. The sentence under it is, and that
/// sentence names the final new-word count rather than each step.
private struct DailyGoalRing: View {
    var shown: Int
    var total: Int
    var animates: Bool

    private var fraction: Double {
        DailyGoalCrossing.fraction(shown, limit: total)
    }

    private var showsCheck: Bool { total > 0 && shown >= total }

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
        .accessibilityHidden(true)
    }
}

/// The streak number and one pulse of the saffron star.
///
/// Reduce Motion and VoiceOver show the final number at once and do not pulse the star.
/// A rescued day fades a snowflake inside that star once. The glyph sits on a badge
/// circle, clipped to the icon, so the count beside it stays clear. A new freeze asks
/// the home to play the larger star below this row. The star card carries the earned line.
private struct StreakMark: View {
    var shown: Int
    var count: Int
    var pulse: Int
    var animates: Bool
    var pendingEvents: [StreakEventID]
    var claimEvents: (StreakEventID.Kind) -> [StreakEventID]
    var onFreezeEarned: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingSnowflake = false
    @State private var snowflakeOpacity = 0.0
    @State private var rescueToken = 0

    private var iconSide: CGFloat { CGFloat(FreezeCelebrationLayout.streakIconSide) }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Octagram()
                    .fill(Lapis.saffron)
                    .frame(width: iconSide, height: iconSide)
                    .modifier(StreakStarPulse(token: pulse))
            }
            .frame(width: iconSide, height: iconSide)
            .overlay { snowflake }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(shown, format: .number)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(Lapis.text)
                    .contentTransition(.numericText())
                    .animation(animates ? .easeOut(duration: CelebrationMotion.streakPulse) : nil, value: shown)
                    .accessibilityHidden(true)
                Text(verbatim: ApprovedCopy.dayStreak)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Lapis.secondaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: CelebrationCopy.streakSpoken(count, label: ApprovedCopy.dayStreak)))
        .onAppear(perform: claimPending)
        .onChange(of: pendingEvents) { _, _ in claimPending() }
        .task(id: rescueToken) { await playRescue() }
    }

    @ViewBuilder private var snowflake: some View {
        if showingSnowflake {
            let badge = CGFloat(FreezeCelebrationLayout.rescueBadgeSide)
            ZStack {
                Circle()
                    .fill(Lapis.badge)
                    .frame(width: badge, height: badge)
                Image(systemName: "snowflake")
                    .font(.system(size: CGFloat(FreezeCelebrationLayout.rescueGlyphSide), weight: .bold))
                    .foregroundStyle(Lapis.badgeInk)
            }
            .frame(width: iconSide, height: iconSide)
            .opacity(snowflakeOpacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Claims each stored day once. A second call, and a later visit, get nothing.
    private func claimPending() {
        let rescues = claimEvents(.rescuedDay)
        if !rescues.isEmpty {
            showingSnowflake = true
            rescueToken += 1
        }
        let earned = claimEvents(.freezeEarned)
        if !earned.isEmpty {
            onFreezeEarned()
        }
    }

    /// Opacity only. Reduce Motion uses the shorter fade and still starts from zero.
    private func playRescue() async {
        guard rescueToken > 0, showingSnowflake else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { snowflakeOpacity = 0 }
        await Task.yield()
        guard !Task.isCancelled else { return }
        withAnimation(Motion.rescueFade(reduceMotion: reduceMotion)) { snowflakeOpacity = 1 }
    }
}

/// The new-freeze star, in its own card under the streak row.
///
/// It is larger than the lesson-finish star, with girih behind it and a lapis ring.
/// Motion unfolds, holds, then shrinks and fades upward toward the streak icon.
/// Reduce Motion only changes opacity: fade in, hold, fade out. Without VoiceOver,
/// the end of that timeline removes the card. With VoiceOver the card stays at
/// the held frame until a tap or leaving the home. Speech finishing does not
/// remove it. The count stays in the row above. VoiceOver reads one final
/// sentence for this event and does not speak the phases.
private struct FreezeEarnedCelebration: View {
    var count: Int
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.layoutDirection) private var layoutDirection
    @AccessibilityFocusState private var freezeFocused: Bool
    @State private var frame = FreezeStarFrame(
        opacity: 0, scale: 0.3, rotationDegrees: -45, offsetTowardIcon: 0, girihOpacity: 0
    )
    @State private var skipped = false
    @State private var didFocusFreeze = false

    private var speech: String {
        FreezeStarSpeech.label(count: count, dayStreak: ApprovedCopy.dayStreak)
    }

    var body: some View {
        let side = CGFloat(FreezeCelebrationLayout.starSide)
        VStack(spacing: 0) {
            ZStack {
                Octagram()
                    .fill(Lapis.saffron)
                    .overlay {
                        Octagram().strokeBorder(Lapis.ring, lineWidth: 1)
                    }
                    .frame(width: side, height: side)
                    .scaleEffect(frame.scale)
                    .rotationEffect(.degrees(frame.rotationDegrees))
                    .opacity(frame.opacity)
                    .offset(travel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(verbatim: ApprovedCopy.streakFreezeEarned)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Lapis.badgeInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .opacity(frame.opacity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: CGFloat(FreezeCelebrationLayout.cardHeight))
        .background {
            Lapis.heroGradient
            GirihPattern()
                .opacity(frame.girihOpacity)
        }
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(FreezeCelebrationLayout.cornerRadius), style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: skip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: speech))
        .accessibilityFocused($freezeFocused)
        .transition(.identity)
        .task { await play() }
        .task {
            guard !didFocusFreeze else { return }
            didFocusFreeze = true
            freezeFocused = true
        }
    }

    /// Up, and toward the trailing streak icon. The card is clipped, so this cannot cover the count.
    private var travel: CGSize {
        let amount = CGFloat(frame.offsetTowardIcon)
        let towardTrailing: CGFloat = layoutDirection == .rightToLeft ? -1 : 1
        return CGSize(width: amount * 0.65 * towardTrailing, height: -amount)
    }

    private func play() async {
        let plan = FreezeStarPlan.make(reduceMotion: reduceMotion, voiceOver: voiceOver, skipped: false)
        guard let first = plan.phases.first else {
            onDismiss()
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { frame = first.starts }
        await Task.yield()
        for phase in plan.phases {
            if Task.isCancelled || skipped { return }
            if let animation = Motion.freezePhase(phase) {
                withAnimation(animation) { frame = phase.ends }
            } else {
                frame = phase.ends
            }
            if phase.duration > 0 {
                try? await Task.sleep(for: .seconds(phase.duration))
            }
            if Task.isCancelled || skipped { return }
        }
        if Task.isCancelled || skipped { return }
        guard plan.removesOverlay else { return }
        onDismiss()
    }

    private func skip() {
        skipped = true
        onDismiss()
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
    /// Lessons that cannot be opened. The home list passes none.
    var locked: Set<LessonID> = []
    var animates: Bool
    var startLesson: (LessonID) -> Void

    private var order: [LessonID] { lessons.map(\.id) }

    private var skipping: Set<LessonID> {
        Set(lessons.filter { $0.kind != .practice }.map(\.id))
    }

    private var nextID: LessonID? {
        CoursePathMotion.next(in: order, finished: finished, skipping: skipping)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                if showsSection(at: index) {
                    Text(verbatim: sectionTitle(lesson.kind))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Lapis.secondaryText)
                        .padding(.top, index == 0 ? 0 : 16)
                        .padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)
                }
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: lesson.title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Lapis.text)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if mark(lesson.id) == .now {
                                Text(verbatim: ApprovedCopy.now)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Lapis.text)
                            } else if mark(lesson.id) == .locked {
                                Text(verbatim: ApprovedCopy.locked)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Lapis.secondaryText)
                            }
                        }
                        .padding(.top, 10)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(lesson.id.rawValue)
                .accessibilityLabel(Text(verbatim: pathLabel(lesson)))
            }
        }
    }

    private func showsSection(at index: Int) -> Bool {
        guard lessons.indices.contains(index) else { return false }
        if index == 0 { return true }
        let previous = lessons[index - 1]
        let lesson = lessons[index]
        return previous.kind != lesson.kind || previous.unitID != lesson.unitID
    }

    private func sectionTitle(_ kind: LessonKind) -> String {
        switch kind {
        case .learn: ApprovedCopy.learn
        case .phrases: ApprovedCopy.phrases
        case .practice: ApprovedCopy.practice
        }
    }

    private func mark(_ id: LessonID) -> CoursePathCopy.Mark {
        CoursePathCopy.mark(
            id: id,
            order: order,
            finished: finished,
            locked: locked,
            skipping: skipping
        )
    }

    private func pathLabel(_ lesson: ReleasedLesson) -> String {
        CoursePathCopy.accessibilityLabel(
            title: lesson.title,
            mark: mark(lesson.id),
            now: ApprovedCopy.now,
            locked: ApprovedCopy.locked
        )
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

/// Today's learned word. The front is the Pashto word. The back is the English meaning.
///
/// The border is the same 1 pt lapis outline as the lesson bar, on the Today surface.
/// Pronunciation uses the body text colour and sits under the word. Reduce Motion
/// crossfades. A turn counter-rotates the meaning so it is not mirrored. Only the
/// face that is showing is accessible. The back is the meaning itself: no second
/// label was approved for turning back to the word.
private struct DailyWordCard: View {
    var word: DailyWord

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var face: DailyWordFace = .front

    private var presentation: DailyWordPresentation {
        DailyWordPresentation(face: face, reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: ApprovedCopy.wordOfTheDay)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Lapis.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                frontFace
                backFace
            }
            .frame(maxWidth: .infinity)
            if presentation.showsFront {
                Button(action: showMeaning) {
                    Text(verbatim: ApprovedCopy.showMeaning)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Lapis.text)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Lapis.background)
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(DailyWordLayout.cornerRadius), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CGFloat(DailyWordLayout.cornerRadius), style: .continuous)
                .strokeBorder(Lapis.primary, lineWidth: CGFloat(DailyWordLayout.borderWidth))
        }
    }

    private var frontFace: some View {
        pashtoLine
            .padding(.vertical, 8)
            .modifier(DailyWordSpin(
                angle: presentation.frontAngle,
                shown: presentation.showsFront,
                spins: presentation.flip.rotates
            ))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: DailyWordSpeech.active(word: word, face: .front)))
            .accessibilityHidden(!presentation.showsFront)
            .allowsHitTesting(false)
    }

    private var backFace: some View {
        Button(action: showWord) {
            Text(verbatim: word.meaning)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Lapis.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .environment(\.layoutDirection, .leftToRight)
        }
        .buttonStyle(.plain)
        .modifier(DailyWordSpin(
            angle: presentation.backAngle,
            shown: presentation.showsBack,
            spins: presentation.flip.rotates
        ))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: DailyWordSpeech.active(word: word, face: .back)))
        .accessibilityAddTraits(.isButton)
        .accessibilityHidden(!presentation.showsBack)
        .allowsHitTesting(presentation.showsBack)
    }

    private var pashtoLine: some View {
        PashtoLine(
            text: word.pashto,
            pronunciation: word.pronunciation,
            arabic: QuizPresentation.containsArabicScript(word.pashto),
            pronunciationColor: Lapis.text,
            fitsWidth: true,
            centers: true
        )
        .font(.largeTitle.weight(.medium))
        .foregroundStyle(Lapis.text)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func showMeaning() {
        flip(to: .back)
    }

    /// Returns to the word. The control's name is the meaning. No extra label.
    private func showWord() {
        flip(to: .front)
    }

    private func flip(to next: DailyWordFace) {
        withAnimation(Motion.dailyWordFlip(reduceMotion: reduceMotion)) {
            face = next
        }
    }
}

/// Hides a daily-word face once it has turned past the edge, so the meaning is not mirrored.
///
/// Reduce Motion leaves the angle at 0 and only changes opacity. The face does not scale or travel.
private struct DailyWordSpin: ViewModifier, Animatable {
    var angle: Double
    var shown: Bool
    var spins: Bool

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(spins ? angle : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: spins ? 0.6 : 0
            )
            .opacity(visible ? 1 : 0)
            .accessibilityHidden(!visible)
    }

    private var visible: Bool {
        guard spins else { return shown }
        return DailyWordFlipVisibility.showsFace(angle: angle)
    }
}

/// Catalog strings for the celebration. The English matches `CelebrationCopy`.
private enum ApprovedCopy {
    static var lessonComplete: String { String(localized: "celebration.lessonComplete") }
    static var correct: String { String(localized: "celebration.correct") }
    static var dayStreak: String { String(localized: "celebration.dayStreak") }
    static var streakFreezeEarned: String { String(localized: "celebration.streakFreezeEarned") }
    static var wordOfTheDay: String { String(localized: "today.wordOfTheDay") }
    static var showMeaning: String { String(localized: "today.showMeaning") }
    static var dailyGoal: String { String(localized: "celebration.dailyGoal") }
    static var toGo: String { String(localized: "celebration.toGo") }
    static var goalReached: String { String(localized: "celebration.goalReached") }
    static var wordOne: String { String(localized: "celebration.word.one") }
    static var wordOther: String { String(localized: "celebration.word.other") }
    static var now: String { String(localized: "path.now") }
    static var locked: String { String(localized: "path.locked") }
    static var learn: String { String(localized: "module.section.learn") }
    static var phrases: String { String(localized: "module.section.phrases") }
    static var practice: String { String(localized: "module.section.practice") }
}

#Preview {
    ContentView()
}
