import PashtoCore
import SwiftUI

/// Root once progress has loaded.
///
/// `reviewStarted` is true after Welcome back's Start review. A lesson quiz
/// is shown when the caller has already built one. The session carries the
/// pronunciation setting it started with. Units that are not in
/// `release-units.json` are not part of that session. The home lists those
/// units in course order. A row opens the unit, and a lesson there starts
/// one. The last answer saves the lesson and shows the
/// celebration. Continue only closes that celebration. Leaving early returns
/// here without it.
/// An empty release list keeps the placeholder.
struct ContentView: View {
    var reviewStarted: Bool = false
    var quiz: LessonSession?
    var quizItems: [ContentItem] = []
    /// Lessons from the release list. Empty keeps the placeholder below.
    var lessons: [ReleasedLesson] = []
    /// Released units in course order, with practice progress. Empty follows `lessons`.
    var menu: MainMenu = MainMenu(categories: [], continueTarget: nil)
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var celebration: LessonSession?
    /// From-values first, then the live counts. Consuming the cue does not change these.
    @State private var playback = HomeMotionPlayback()
    @State private var streakPulse = 0
    @State private var goalHaptic = 0
    /// The freeze star card. Cleared when it finishes, when it is skipped, and when the home goes away.
    @State private var freezeCelebration = false
    /// The open category. Kept here so a lesson does not forget which unit was open.
    @State private var categoryPath: [UnitID] = []

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
        QuizScreen(
            session: quiz,
            items: quizItems,
            lessonTitle: lessons.first { $0.id == quiz.lessonID }?.title ?? "",
            streakCount: streakCount,
            onClose: endSession,
            onAnswer: answerSession,
            onFinish: { celebration = $0; finishSession($0) }
        )
    }

    private var lessonList: some View {
        NavigationStack(path: $categoryPath) {
            VStack(spacing: 0) {
                homeHeader
                lessonScroll
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Lapis.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UnitID.self) { unitID in
                if let category = menu.categories.first(where: { $0.id == unitID }) {
                    categoryPage(category)
                }
            }
        }
        .sensoryFeedback(.success, trigger: goalHaptic)
        .onDisappear { freezeCelebration = false }
        .task(id: pendingHomeMotion?.id) {
            await playHomeMotion()
        }
    }

    /// Pashto, the day streak, and the daily goal. The goal sentence is spoken, not a second line.
    /// The streak and the goal share one row when that row fits, and stack with the streak on top when it does not.
    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pashto")
                .font(.title2.weight(.bold))
                .foregroundStyle(Lapis.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            HomeStatusRow(
                streakShown: streakShown,
                streakCount: streakCount,
                streakPulse: streakPulse,
                animates: animatesHomeMotion,
                pendingEvents: pendingStreakEvents,
                claimEvents: claimStreakEvents,
                onFreezeEarned: { freezeCelebration = true },
                goalShown: goalShown,
                goalTotal: goalTotal,
                goalLabel: ApprovedCopy.dailyGoal,
                goalSpeech: dailyGoalSpeech(done: goalDone)
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QuizChrome.surface.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Lapis.muted.opacity(0.45))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    private var lessonScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if freezeCelebration {
                    FreezeEarnedCelebration(count: streakCount, onDismiss: { freezeCelebration = false })
                }
                if let dailyWord {
                    DailyWordCard(word: dailyWord)
                }
                if let target = menu.continueTarget {
                    continueStrip(target)
                }
                ForEach(menu.categories) { category in
                    categoryRow(category)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Play, the lesson, and the arrow. One button, same two spoken lines.
    ///
    /// Regular sizes keep the row. At accessibility sizes the play square
    /// grows until the words no longer fit beside it, and `ViewThatFits`
    /// puts the square above them so both lines use the width.
    private func continueStrip(_ target: MainMenuContinue) -> some View {
        Button {
            startLesson(target.lessonID)
        } label: {
            if dynamicTypeSize.isAccessibilitySize {
                ViewThatFits(in: .horizontal) {
                    continueRow(target, oneLine: true)
                    continueStacked(target)
                }
            } else {
                continueRow(target, oneLine: false)
            }
        }
        .buttonStyle(SurfaceCardButtonStyle())
        .accessibilityIdentifier("continue-lesson")
    }

    /// Side by side. `oneLine` stops the words wrapping, so `ViewThatFits`
    /// can see that the row is wider than the card.
    private func continueRow(_ target: MainMenuContinue, oneLine: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ContinuePlayMark()
            if oneLine {
                continueWords(target)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 12)
            } else {
                continueWords(target)
            }
            continueArrow
        }
    }

    /// Play square above the words. The arrow stays on the text row.
    private func continueStacked(_ target: MainMenuContinue) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ContinuePlayMark()
            HStack(alignment: .center, spacing: 12) {
                continueWords(target)
                continueArrow
            }
        }
    }

    private func continueWords(_ target: MainMenuContinue) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: String(localized: "quiz.continue.button"))
                .textCase(.uppercase)
                .font(.caption.weight(.bold))
                .foregroundStyle(Lapis.secondaryText)
                .lineLimit(1)
            Text(verbatim: continueTitle(target))
                .font(.body.weight(.semibold))
                .foregroundStyle(Lapis.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var continueArrow: some View {
        Image(systemName: "arrow.right")
            .font(.body.weight(.bold))
            .foregroundStyle(Lapis.primary)
            .accessibilityHidden(true)
    }

    private func categoryRow(_ category: MainMenuCategory) -> some View {
        let colors = Lapis.MenuCard.resolve(category.id)
        let stacks = dynamicTypeSize >= .xxxLarge
        return Button {
            categoryPath.append(category.id)
        } label: {
            Group {
                if stacks {
                    VStack(alignment: .leading, spacing: 8) {
                        categoryLabel(category, hue: colors.hue)
                        practiceRing(category, colors: colors)
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        categoryLabel(category, hue: colors.hue)
                        practiceRing(category, colors: colors)
                    }
                }
            }
        }
        .buttonStyle(MenuHueButtonStyle(fill: colors.fill, hue: colors.hue))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: menuWord(category)))
        .accessibilityValue(Text(category.fraction, format: .percent.precision(.fractionLength(0))))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(category.id.rawValue)
    }

    private func categoryLabel(_ category: MainMenuCategory, hue: Color) -> some View {
        Text(verbatim: menuWord(category))
            .textCase(.uppercase)
            .font(.title3.weight(.semibold))
            .foregroundStyle(hue)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func continueTitle(_ target: MainMenuContinue) -> String {
        let label: String
        if let category = menu.categories.first(where: { $0.id == target.unitID }) {
            label = menuWord(category)
        } else {
            label = target.unitLabel
        }
        return "\(label) · \(target.lessonTitle)"
    }

    /// The stored word. Uppercase is only the drawing, so VoiceOver reads the word.
    private func menuWord(_ category: MainMenuCategory) -> String {
        switch category.catalogKey {
        case "menu.unit.basics": String(localized: "menu.unit.basics")
        case "menu.unit.greetings": String(localized: "menu.unit.greetings")
        case "menu.unit.introduction": String(localized: "menu.unit.introduction")
        case "menu.unit.family": String(localized: "menu.unit.family")
        case "menu.unit.travel": String(localized: "menu.unit.travel")
        case "menu.unit.time": String(localized: "menu.unit.time")
        default: category.label
        }
    }

    private func practiceRing(_ category: MainMenuCategory, colors: Lapis.MenuCard) -> some View {
        let fraction = category.fraction
        let complete = category.isComplete
        return ZStack {
            Circle()
                .stroke(colors.track, lineWidth: 4.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    complete ? Lapis.menuCheck : colors.hue,
                    style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if complete {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Lapis.menuCheck)
            } else {
                Text(verbatim: "\(category.practiceCompleted)/\(category.practiceTotal)")
                    .font(.caption2.weight(.heavy).monospacedDigit())
                    .foregroundStyle(colors.hue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: 48, height: 48)
        .accessibilityHidden(true)
    }

    private func categoryPage(_ category: MainMenuCategory) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(categoryKinds, id: \.self) { kind in
                    categorySection(kind, in: category)
                }
                if !category.wordList.isEmpty {
                    FamilyWordListView(rows: category.wordList)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Lapis.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Lapis.badge, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(verbatim: category.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Lapis.badgeInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                    if category.practiceTotal > 0 {
                        Text(verbatim: "\(category.practiceCompleted)/\(category.practiceTotal)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Lapis.badgeInk)
                            .accessibilityLabel(Text(category.fraction, format: .percent.precision(.fractionLength(0))))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
        }
    }

    private var categoryKinds: [LessonKind] { [.learn, .phrases, .practice] }

    @ViewBuilder
    private func categorySection(_ kind: LessonKind, in category: MainMenuCategory) -> some View {
        let rows = category.lessons.filter { $0.kind == kind }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeading(kind, category: category)
                ForEach(rows) { lesson in
                    categoryLesson(lesson)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeading(_ kind: LessonKind, category: MainMenuCategory) -> some View {
        if kind == .practice, category.practiceTotal > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: sectionTitle(kind))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Lapis.secondaryText)
                Text(verbatim: "\(category.practiceCompleted)/\(category.practiceTotal)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Lapis.secondaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(Text(verbatim: sectionTitle(kind)))
            .accessibilityValue(Text(category.fraction, format: .percent.precision(.fractionLength(0))))
        } else {
            Text(verbatim: sectionTitle(kind))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Lapis.secondaryText)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func categoryLesson(_ lesson: MainMenuLesson) -> some View {
        let mark = lessonMark(lesson.id)
        return Button {
            startLesson(lesson.id)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(verbatim: lesson.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Lapis.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if lesson.kind == .practice, lesson.isComplete {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Lapis.menuCheck)
                        .accessibilityHidden(true)
                }
                if mark == .now {
                    Text(verbatim: ApprovedCopy.now)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Lapis.text)
                } else if mark == .locked {
                    Text(verbatim: ApprovedCopy.locked)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Lapis.secondaryText)
                }
                Image(systemName: "chevron.forward")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Lapis.primary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(SurfaceCardButtonStyle(minHeight: 72))
        .accessibilityLabel(Text(verbatim: lessonAccessibility(lesson, mark: mark)))
        .accessibilityIdentifier(lesson.id.rawValue)
    }

    private func lessonMark(_ id: LessonID) -> CoursePathCopy.Mark {
        let order = menu.categories.flatMap { $0.lessons.map(\.id) }
        let skipping = Set(menu.categories.flatMap { category in
            category.lessons.filter { $0.kind != .practice }.map(\.id)
        })
        return CoursePathCopy.mark(
            id: id,
            order: order,
            finished: finishedLessonIDs,
            locked: [],
            skipping: skipping
        )
    }

    private func lessonAccessibility(_ lesson: MainMenuLesson, mark: CoursePathCopy.Mark) -> String {
        CoursePathCopy.accessibilityLabel(
            title: lesson.title,
            mark: mark,
            now: ApprovedCopy.now,
            locked: ApprovedCopy.locked
        )
    }

    private func sectionTitle(_ kind: LessonKind) -> String {
        switch kind {
        case .learn: ApprovedCopy.learn
        case .phrases: ApprovedCopy.phrases
        case .practice: ApprovedCopy.practice
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

/// Pictured words under the lesson groups. Display only: no tap, no quiz, no progress.
///
/// Light and dark use the same lapis colors as the rest of the page. At the
/// largest type size the row stacks so the Pashto wraps instead of truncating.
private struct FamilyWordListView: View {
    var rows: [FamilyWordList.Row]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                FamilyWordRowView(row: row)
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(Lapis.muted.opacity(0.45))
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// One pictured word. VoiceOver reads the English word and the pronunciation.
///
/// The picture's own label is the English word. The row is one element, so
/// VoiceOver does not also read the Pashto. The row is not a button.
private struct FamilyWordRowView: View {
    var row: FamilyWordList.Row

    @ScaledMetric(relativeTo: .body) private var tileSide: CGFloat = 48

    var body: some View {
        ViewThatFits(in: .horizontal) {
            sideBySide
            stacked
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row.accessibilityLabel))
        .accessibilityIdentifier(row.itemID.rawValue)
    }

    private var sideBySide: some View {
        HStack(alignment: .center, spacing: 12) {
            picture
            words
            Spacer(minLength: 12)
            pashto
        }
    }

    /// Used when the side-by-side row no longer fits. Pashto keeps the full width and wraps.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                picture
                words
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            pashto
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var picture: some View {
        Image(row.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: tileSide, height: tileSide)
            .clipShape(RoundedRectangle(cornerRadius: tileSide * 0.22, style: .continuous))
            .accessibilityLabel(Text(verbatim: row.english))
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let pronunciation = row.pronunciation {
                Text(verbatim: pronunciation)
                    .font(.body.weight(.bold))
                    .foregroundStyle(Lapis.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.layoutDirection, .leftToRight)
            }
            Text(verbatim: row.english)
                .font(.subheadline)
                .foregroundStyle(Lapis.secondaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.layoutDirection, .leftToRight)
        }
    }

    /// Pashto stays right aligned. The system Arabic font is the one the quiz uses.
    /// No line limit, so a long word wraps at the largest Dynamic Type size.
    private var pashto: some View {
        Text(verbatim: row.pashto)
            .font(.body)
            .foregroundStyle(Lapis.secondaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.layoutDirection, .rightToLeft)
            .accessibilityHidden(true)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(verbatim: "/\(max(total, 0))")
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .font(.headline.weight(.bold).monospacedDigit())
            .foregroundStyle(Lapis.text)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        }
        .accessibilityHidden(true)
    }
}

/// Streak and daily goal. Side by side when the row fits, otherwise the streak above the goal.
///
/// The claim lives here, once, so the two `ViewThatFits` branches do not each take the rescue.
private struct HomeStatusRow: View {
    var streakShown: Int
    var streakCount: Int
    var streakPulse: Int
    var animates: Bool
    var pendingEvents: [StreakEventID]
    var claimEvents: (StreakEventID.Kind) -> [StreakEventID]
    var onFreezeEarned: () -> Void
    var goalShown: Int
    var goalTotal: Int
    var goalLabel: String
    var goalSpeech: String

    @State private var showingSnowflake = false
    @State private var rescueToken = 0

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                streakMark
                Spacer(minLength: 8)
                dailyGoal
            }
            VStack(alignment: .leading, spacing: 12) {
                streakMark
                dailyGoal
            }
        }
        .onAppear(perform: claimPending)
        .onChange(of: pendingEvents) { _, _ in claimPending() }
    }

    private var streakMark: some View {
        StreakMark(
            shown: streakShown,
            count: streakCount,
            pulse: streakPulse,
            animates: animates,
            showingSnowflake: showingSnowflake,
            rescueToken: rescueToken
        )
    }

    private var dailyGoal: some View {
        HStack(spacing: 8) {
            DailyGoalRing(
                shown: goalShown,
                total: goalTotal,
                animates: animates
            )
            Text(verbatim: goalLabel)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Lapis.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: goalSpeech))
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
}

/// The play glyph stays in the middle of its ring. Both use the body text style,
/// so a larger Dynamic Type size grows the ring with the glyph.
private struct ContinuePlayMark: View {
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var corner: CGFloat = 12

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(QuizChrome.tint)
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Lapis.primary, lineWidth: 1)
                }
            Image(systemName: "play.fill")
                .font(.body.weight(.bold))
                .foregroundStyle(Lapis.primary)
        }
        .frame(width: side, height: side)
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
    var showingSnowflake: Bool
    var rescueToken: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snowflakeOpacity = 0.0

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
enum ApprovedCopy {
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
