import PashtoCore
import SwiftUI

/// One quiz question in Design B.
///
/// The stored pronunciation is the large line. Pashto is smaller beneath it,
/// right to left. The pronunciation stays left to right. Scholarly
/// transliteration is not shown. Noto Naskh Arabic is not in the bundle, so
/// Pashto uses the system Arabic font. Find-letter and first-letter choices
/// keep pronunciation off until the question has been answered. A same-sound
/// choice draws its ring or dot after the answer.
struct QuizScreen: View {
    @State private var session: LessonSession
    @State private var pickedChoice: ItemID?
    @State private var revealed = false
    @State private var result: GradeResult?
    @State private var links: [ItemID: ItemID] = [:]
    @State private var selectedLeft: ItemID?
    @State private var placed: [Int] = []
    @State private var rng = SystemRandomNumberGenerator()
    @State private var correctHaptics = 0
    @State private var wrongHaptics = 0
    /// The card that is fading out. It keeps the question that just left.
    @State private var outgoing: QuestionCardState?
    @State private var outgoingVisible = true
    /// False while the new card is still off to the right, or invisible for Reduce Motion.
    @State private var incomingSettled = true
    @State private var changeToken = 0
    @State private var cardWidth: CGFloat = 0
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private let itemsByID: [ItemID: ContentItem]
    private let lessonTitle: String
    private let streakCount: Int
    private let onClose: () -> Void
    var onAnswer: (LessonSession) -> Void
    var onFinish: (LessonSession) -> Void

    @ScaledMetric(relativeTo: .title) private var questionTitleSize: CGFloat = 28
    @ScaledMetric(relativeTo: .title2) private var choicePronunciationSize: CGFloat = 25
    @ScaledMetric(relativeTo: .title3) private var choicePashtoSize: CGFloat = 29
    @ScaledMetric(relativeTo: .title2) private var wordPronunciationSize: CGFloat = 25
    @ScaledMetric(relativeTo: .title3) private var wordPashtoSize: CGFloat = 29
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        session: LessonSession,
        items: [ContentItem],
        lessonTitle: String = "",
        streakCount: Int = 0,
        onClose: @escaping () -> Void = {},
        onAnswer: @escaping (LessonSession) -> Void = { _ in },
        onFinish: @escaping (LessonSession) -> Void = { _ in }
    ) {
        _session = State(initialValue: session)
        self.lessonTitle = lessonTitle
        self.streakCount = streakCount
        self.onClose = onClose
        self.onAnswer = onAnswer
        self.onFinish = onFinish
        var map: [ItemID: ContentItem] = [:]
        for item in items where map[item.id] == nil {
            map[item.id] = item
        }
        itemsByID = map
    }

    var body: some View {
        VStack(spacing: 0) {
            quizHeader
            ScrollView {
                questionStage
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            quizFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(QuizChrome.page.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: correctHaptics)
        .sensoryFeedback(.error, trigger: wrongHaptics)
        .onChange(of: result) { _, graded in
            // One announcement for the result. Motion must not post another.
            guard let graded else { return }
            AccessibilityNotification.Announcement(QuizCopy.feedbackSpoken(correct: graded == .correct)).post()
        }
    }

    private var quizHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Button(action: onClose) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.backward")
                            .accessibilityHidden(true)
                        Text("Pashto")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(QuizChrome.cream)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Pashto"))
                .accessibilityAddTraits(.isButton)
                .accessibilitySortPriority(80)
                if !lessonTitle.isEmpty {
                    Text(verbatim: lessonTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(QuizChrome.cream)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .accessibilitySortPriority(75)
                }
                Spacer(minLength: 8)
                streakMark
            }
            HStack(spacing: 12) {
                LessonProgressBar(bar: lessonBar, chrome: .quizHeader)
                    .accessibilitySortPriority(60)
                Text(verbatim: "\(lessonBar.answered) / \(lessonBar.total)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(QuizChrome.cream)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .fill(QuizChrome.badge)
            .ignoresSafeArea(edges: .top)
        }
    }

    private var streakMark: some View {
        HStack(spacing: 4) {
            Octagram()
                .fill(QuizChrome.saffron)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(streakCount, format: .number)
                .font(.subheadline.weight(.heavy))
            Text(verbatim: ApprovedCopy.dayStreak)
                .font(.caption2.weight(.semibold))
                .fixedSize()
        }
        .foregroundStyle(QuizChrome.cream)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: CelebrationCopy.streakSpoken(streakCount, label: ApprovedCopy.dayStreak)))
        .accessibilitySortPriority(70)
    }

    private var quizFooter: some View {
        VStack(alignment: .leading, spacing: 14) {
            if revealed, let result {
                feedback(result)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            Button(action: advance) {
                HStack(spacing: 10) {
                    Text("quiz.continue.button")
                    if canContinue {
                        Image(systemName: "arrow.right")
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(QuizContinueButtonStyle(enabled: canContinue))
            .disabled(!canContinue)
            .accessibilitySortPriority(10)
        }
        .padding(.horizontal, 20)
        .padding(.top, revealed ? 16 : 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if revealed, let result {
                QuizResultSheet(result: result)
                    .ignoresSafeArea(edges: .bottom)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? Motion.fade : .easeOut(duration: QuizMotion.resultSheet), value: revealed)
    }

    private var questionStage: some View {
        ZStack(alignment: .topLeading) {
            if let outgoing {
                questionCard(outgoing, interactive: false)
                    .opacity(outgoingVisible ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if let live = liveCard {
                questionCard(live, interactive: true)
                    .id(live.identity)
                    .offset(x: incomingOffset)
                    .opacity(incomingOpacity)
                    .zIndex(1)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { cardWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in
                        cardWidth = width
                    }
            }
        }
        .task(id: changeToken) {
            await playQuestionChange()
        }
    }

    private var liveCard: QuestionCardState? {
        guard let task = session.current else { return nil }
        return QuestionCardState(
            identity: QuestionIdentity(answerCount: session.answers.count, isRepeat: task.isRepeat),
            task: task,
            revealed: revealed,
            result: result,
            pickedChoice: pickedChoice,
            links: links,
            selectedLeft: selectedLeft,
            placed: placed,
            showsPronunciation: session.showsPronunciation,
            playsReveal: true
        )
    }

    /// The new card starts at the right, or invisible when Reduce Motion is on.
    private var incomingOffset: CGFloat {
        switch QuestionChange.style(reduceMotion: reduceMotion) {
        case .slideFromRight:
            incomingSettled ? 0 : max(cardWidth, 1)
        case .crossfade:
            0
        }
    }

    private var incomingOpacity: Double {
        switch QuestionChange.style(reduceMotion: reduceMotion) {
        case .slideFromRight:
            1
        case .crossfade:
            incomingSettled ? 1 : 0
        }
    }

    /// Slides the new card and fades the old one. Reduce Motion crossfades.
    /// The sleep only clears the old card. Continue and the new question stay open.
    private func playQuestionChange() async {
        guard changeToken > 0 else { return }
        let reduce = reduceMotion
        withAnimation(Motion.questionAdvance(reduceMotion: reduce)) {
            incomingSettled = true
        }
        withAnimation(reduce ? Motion.fade : .easeOut(duration: QuizMotion.questionSpring)) {
            outgoingVisible = false
        }
        try? await Task.sleep(for: .seconds(QuestionChange.duration(reduceMotion: reduce)))
        if !Task.isCancelled {
            outgoing = nil
        }
    }

    @ViewBuilder
    private func questionCard(_ card: QuestionCardState, interactive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            switch card.task.payload {
            case .choice(let quiz):
                choice(quiz, card: card, interactive: interactive)
            case .matchPairs(let match):
                matchPairs(match, card: card, interactive: interactive)
            case .orderWords(let order):
                orderWords(order, card: card, interactive: interactive)
            }
        }
    }

    private func choice(_ quiz: QuizTask, card: QuestionCardState, interactive: Bool) -> some View {
        let face = QuizPresentation.face(
            for: quiz,
            items: Array(itemsByID.values),
            showsPronunciation: card.showsPronunciation,
            voiceOver: voiceOverEnabled,
            answered: card.revealed
        )
        return VStack(alignment: .leading, spacing: 16) {
            taskTitle(quiz.kind)
            prompt(face.prompt, task: quiz, card: card)
            if let usage = face.usage {
                Text(usage)
                    .font(.subheadline)
                    .foregroundStyle(QuizChrome.pashto)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilitySortPriority(35)
            }
            VStack(spacing: 12) {
                ForEach(Array(face.options.enumerated()), id: \.element.itemID) { index, option in
                    choiceButton(
                        option,
                        number: index + 1,
                        correctID: quiz.targetID,
                        mark: mark(for: option.itemID, correctID: quiz.targetID, card: card),
                        card: card,
                        interactive: interactive
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func prompt(_ prompt: QuizPromptFace, task: QuizTask, card: QuestionCardState) -> some View {
        let text = QuizCopy.prompt(prompt)
        if QuizPresentation.containsArabicScript(text) {
            GlyphCard(
                model: GlyphCardModel.make(
                    glyph: text,
                    pronunciation: prompt.pronunciation,
                    meaning: itemsByID[task.promptItemID ?? task.targetID]?.en,
                    kind: task.kind,
                    answered: card.revealed
                ),
                playsReveal: card.playsReveal
            )
            .id(card.identity)
            .accessibilitySortPriority(50)
        } else {
            Text(verbatim: text)
                .font(.system(size: questionTitleSize, weight: .bold))
                .foregroundStyle(QuizChrome.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilitySortPriority(50)
        }
    }

    @ViewBuilder
    private func taskTitle(_ kind: TaskKind) -> some View {
        if let title = QuizPromptTitle.title(for: kind) {
            Text(verbatim: title)
                .font(.system(size: questionTitleSize, weight: .heavy))
                .foregroundStyle(QuizChrome.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .accessibilitySortPriority(55)
        }
    }

    private func choiceButton(
        _ option: QuizOptionFace,
        number: Int,
        correctID: ItemID,
        mark: QuizResultMark?,
        card: QuestionCardState,
        interactive: Bool
    ) -> some View {
        let colors = answerColors(mark)
        return Button {
            pick(option.itemID)
        } label: {
            HStack(spacing: 10) {
                Text(verbatim: "\(number)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuizChrome.pashto)
                    .frame(minWidth: 24, minHeight: 24)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(QuizChrome.muted, lineWidth: 1)
                    }
                    .accessibilityHidden(true)
                choiceLabel(option, mark: mark)
                Spacer(minLength: 0)
                ZStack {
                    if let mark {
                        Image(systemName: mark.symbolName)
                            .font(.body.weight(.bold))
                            .foregroundStyle(markColor(mark))
                            .transition(.opacity)
                            .accessibilityHidden(true)
                    }
                }
                .animation(.easeOut(duration: QuizMotion.checkFade), value: mark)
            }
        }
        .buttonStyle(
            QuizTactileButtonStyle(
                fill: colors.fill,
                edge: colors.edge,
                lipColor: colors.edge
            )
        )
        .disabled(!interactive || card.revealed)
        .modifier(ChoiceMotion(mark: mark, moves: interactive && card.pickedChoice == option.itemID))
        .accessibilityLabel(QuizCopy.choiceLabel(option, mark: mark))
        .accessibilitySortPriority(30)
        .id("\(card.identity.answerCount)-\(option.itemID.rawValue)")
    }

    @ViewBuilder
    private func choiceLabel(_ option: QuizOptionFace, mark: QuizResultMark?) -> some View {
        let arabic = QuizPresentation.containsArabicScript(option.text)
        if arabic {
            PashtoLine(
                text: option.text,
                pronunciation: option.pronunciation,
                arabic: true,
                mark: option.highlight,
                reservesPronunciation: option.reservesPronunciation,
                pronunciationColor: mark == nil ? QuizChrome.primary : Lapis.fillPronunciation,
                scriptColor: option.pronunciation == nil
                    ? (mark == nil ? QuizChrome.ink : Lapis.fillText)
                    : (mark == nil ? QuizChrome.pashto : Lapis.fillText),
                scriptFont: option.pronunciation == nil ? nil : .system(size: choicePashtoSize, weight: .regular),
                pronunciationLeads: option.pronunciation != nil
            )
            .font(.system(size: option.pronunciation == nil ? 28 : choicePronunciationSize, weight: .bold))
            .foregroundStyle(mark == nil ? QuizChrome.ink : Lapis.fillText)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(verbatim: option.text)
                .font(.body.weight(.semibold))
                .foregroundStyle(mark == nil ? QuizChrome.ink : Lapis.fillText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func answerColors(_ mark: QuizResultMark?) -> (fill: Color, edge: Color) {
        switch mark {
        case .correct:
            (Lapis.correctFill, Lapis.correct)
        case .incorrect:
            (Lapis.incorrectFill, Lapis.destructive)
        case nil:
            (QuizChrome.surface, QuizChrome.primary)
        }
    }

    /// Correct stays marked after a wrong pick, so the right glyph is not only a color.
    private func mark(for optionID: ItemID, correctID: ItemID, card: QuestionCardState) -> QuizResultMark? {
        guard card.revealed else { return nil }
        if optionID == correctID { return .correct }
        if optionID == card.pickedChoice { return .incorrect }
        return nil
    }

    private func feedback(_ result: GradeResult) -> some View {
        let mark: QuizResultMark = result == .correct ? .correct : .incorrect
        let icon = markColor(mark)
        return HStack(spacing: 12) {
            Image(systemName: mark.symbolName)
                .font(.headline.weight(.bold))
                .foregroundStyle(icon)
                .frame(width: 34, height: 34)
                .overlay {
                    Circle().strokeBorder(icon, lineWidth: 2)
                }
                .accessibilityHidden(true)
            Text(feedbackKey(result))
                .font(.title3.weight(.bold))
                .foregroundStyle(result == .correct ? Lapis.correctText : Lapis.destructive)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(feedbackKey(result)))
        .accessibilityAddTraits(.isHeader)
        .accessibilitySortPriority(20)
    }

    /// The check and the cross. Light green is not dark enough for text.
    private func markColor(_ mark: QuizResultMark) -> Color {
        mark == .correct ? Lapis.correct : Lapis.destructive
    }

    private func feedbackKey(_ result: GradeResult) -> LocalizedStringKey {
        switch result {
        case .correct:
            "quiz.feedback.correct"
        case .incorrect:
            "quiz.feedback.incorrect"
        }
    }

    private func matchPairs(_ task: MatchPairsTask, card: QuestionCardState, interactive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            taskTitle(.matchPairs)
            matchBoard(task, card: card, interactive: interactive)
        }
    }

    private func matchBoard(_ task: MatchPairsTask, card: QuestionCardState, interactive: Bool) -> some View {
        MatchingBoard(
            task: task,
            links: card.links,
            selectedLeft: card.selectedLeft,
            revealed: card.revealed,
            showsPronunciation: card.showsPronunciation,
            itemsByID: itemsByID,
            onLeft: { id in
                guard interactive, !revealed else { return }
                if selectedLeft == id {
                    links = QuizDraft.unlink(links, left: id)
                    selectedLeft = nil
                } else {
                    selectedLeft = id
                }
            },
            onRight: { id in
                guard interactive else { return }
                link(id)
            }
        )
        .id(card.identity)
    }

    private func orderWords(_ task: OrderWordsTask, card: QuestionCardState, interactive: Bool) -> some View {
        let chosen = card.placed.compactMap { index in task.tiles.first { $0.index == index } }
        let pool = task.tiles.filter { !card.placed.contains($0.index) }
        return VStack(alignment: .leading, spacing: 16) {
            taskTitle(.orderWords)
            if !chosen.isEmpty || !task.fixedEnding.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    QuizWordWrap(spacing: 8, rtl: true) {
                        ForEach(chosen, id: \.index) { tile in
                            wordButton(tile, showsPronunciation: card.showsPronunciation, expands: false) {
                                guard interactive, !card.revealed else { return }
                                placed = QuizDraft.place(placed, tile: tile.index)
                            }
                            .disabled(!interactive || card.revealed)
                        }
                        if !task.fixedEnding.isEmpty {
                            Text(verbatim: task.fixedEnding)
                                .font(.system(size: 32, weight: .regular))
                                .foregroundStyle(QuizChrome.pashto)
                                .frame(minWidth: 44, minHeight: 44)
                                .environment(\.layoutDirection, .rightToLeft)
                        }
                    }
                    if let pronunciation = QuizPresentation.sentencePronunciation(
                        item: itemsByID[task.targetID],
                        showsPronunciation: card.showsPronunciation,
                        answered: card.revealed
                    ) {
                        Text(verbatim: pronunciation)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(QuizChrome.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(QuizChrome.tint)
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(QuizChrome.primary, lineWidth: 1)
                        }
                }
            }
            ForEach(pool, id: \.index) { tile in
                wordButton(tile, showsPronunciation: card.showsPronunciation, expands: true) {
                    guard interactive, !card.revealed else { return }
                    placed = QuizDraft.place(placed, tile: tile.index)
                }
                .disabled(!interactive || card.revealed)
            }
        }
    }

    private func wordButton(
        _ tile: WordTile,
        showsPronunciation: Bool,
        expands: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let spoken = tilePronunciation(tile, showsPronunciation: showsPronunciation)
        let arabic = QuizPresentation.containsArabicScript(tile.text)
        return Button(action: action) {
            PashtoLine(
                text: tile.text,
                pronunciation: spoken,
                arabic: arabic,
                pronunciationColor: QuizChrome.primary,
                scriptColor: QuizChrome.pashto,
                scriptFont: spoken == nil ? nil : .system(size: wordPashtoSize, weight: .regular),
                centers: true,
                pronunciationLeads: spoken != nil
            )
            .font(.system(size: spoken == nil ? 28 : wordPronunciationSize, weight: .bold))
            .foregroundStyle(QuizChrome.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: expands ? .infinity : nil)
        }
        .buttonStyle(
            QuizTactileButtonStyle(
                fill: QuizChrome.surface,
                edge: QuizChrome.primary,
                lipColor: QuizChrome.primary,
                expands: expands,
                alignment: .center
            )
        )
        .accessibilityLabel(tileAccessibility(tile, showsPronunciation: showsPronunciation))
        .accessibilitySortPriority(30)
    }

    private func tilePronunciation(_ tile: WordTile, showsPronunciation: Bool) -> String? {
        QuizPresentation.tilePronunciation(tile.pronunciation, showsPronunciation: showsPronunciation)
    }

    private func tileAccessibility(_ tile: WordTile, showsPronunciation: Bool) -> String {
        if let spoken = tilePronunciation(tile, showsPronunciation: showsPronunciation) {
            return "\(spoken), \(tile.text)"
        }
        return tile.text
    }

    private var lessonBar: LessonBar {
        LessonBar.measure(
            submitted: session.answers.count,
            remaining: session.tasks.count,
            revealed: revealed ? result : nil,
            currentIsRepeat: session.current?.isRepeat ?? false
        )
    }

    private var canContinue: Bool {
        guard let task = session.current else { return false }
        if revealed { return true }
        return answer(for: task) != nil
    }

    private func pick(_ id: ItemID) {
        guard !revealed, let task = session.current else { return }
        pickedChoice = id
        revealed = true
        let graded = grade(task, .choice(id))
        result = graded
        noteGrade(graded)
    }

    private func link(_ right: ItemID) {
        guard !revealed, let left = selectedLeft else { return }
        links = QuizDraft.link(links, left: left, right: right)
        selectedLeft = nil
    }

    private func advance() {
        guard let task = session.current, let answer = answer(for: task) else { return }
        if !revealed {
            let graded = grade(task, answer)
            result = graded
            revealed = true
            noteGrade(graded)
            return
        }
        let leaving = QuestionCardState(
            identity: QuestionIdentity(answerCount: session.answers.count, isRepeat: task.isRepeat),
            task: task,
            revealed: revealed,
            result: result,
            pickedChoice: pickedChoice,
            links: links,
            selectedLeft: selectedLeft,
            placed: placed,
            showsPronunciation: session.showsPronunciation,
            playsReveal: false
        )
        var generator = rng
        session.submit(answer, using: &generator)
        rng = generator
        pickedChoice = nil
        revealed = false
        result = nil
        links = [:]
        selectedLeft = nil
        placed = []
        if session.isComplete {
            onFinish(session)
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            outgoing = leaving
            outgoingVisible = true
            incomingSettled = false
        }
        changeToken += 1
        onAnswer(session)
    }

    /// One haptic for every task kind. A choice plays it on the tap. Match and word order play it when Continue grades.
    private func noteGrade(_ graded: GradeResult) {
        switch AnswerHaptic.kind(for: graded) {
        case .success:
            correctHaptics += 1
        case .error:
            wrongHaptics += 1
        }
    }

    private func answer(for task: SessionTask) -> QuizAnswer? {
        switch task.payload {
        case .choice:
            guard let pickedChoice else { return nil }
            return .choice(pickedChoice)
        case .matchPairs(let match):
            guard match.pairs.allSatisfy({ links[$0.left.itemID] != nil }) else { return nil }
            return .matches(match.pairs.map { MatchLink(left: $0.left.itemID, right: links[$0.left.itemID]!) })
        case .orderWords(let order):
            guard placed.count == order.tiles.count else { return nil }
            return .tokenOrder(placed)
        }
    }
}

/// Pashto on its own line, right to left, with pronunciation underneath.
/// One question as it looked when it was drawn.
///
/// The card that is leaving keeps this copy. The live card reads the session.
private struct QuestionCardState {
    var identity: QuestionIdentity
    var task: SessionTask
    var revealed: Bool
    var result: GradeResult?
    var pickedChoice: ItemID?
    var links: [ItemID: ItemID]
    var selectedLeft: ItemID?
    var placed: [Int]
    var showsPronunciation: Bool
    var playsReveal: Bool
}

struct PashtoLine: View {
    var text: String
    var pronunciation: String?
    var arabic: Bool
    var mark: LetterMark?
    var reservesPronunciation = false
    var textColor: Color? = nil
    var pronunciationColor: Color = Lapis.secondaryText
    /// Pashto under a leading pronunciation. Nil keeps the colour the parent sets.
    var scriptColor: Color? = nil
    /// Pashto size when pronunciation leads. Nil keeps the smaller subheadline.
    var scriptFont: Font? = nil
    /// Shrinks one long word so the 56 pt glyph stays inside the card at the largest type size.
    var fitsWidth = false
    /// Centers the word and the pronunciation under it. The quiz leaves this off.
    var centers = false
    /// Quiz prompts and answers. Pronunciation is the large line and Pashto is smaller beneath it.
    var pronunciationLeads = false

    var body: some View {
        if centers {
            centeredLine
        } else {
            leadingLine
        }
    }

    private var pronunciationFirst: Bool {
        pronunciationLeads && pronunciation.map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } == true
    }

    private var leadingLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            if pronunciationFirst {
                pronunciationText(alignment: .leading)
                styledScript(alignment: .leading)
            } else {
                styledScript(alignment: .leading)
                if let pronunciation {
                    pronunciationText(alignment: .leading)
                        .font(.subheadline.weight(.medium))
                } else if reservesPronunciation {
                    Text(" ")
                        .font(.subheadline.weight(.medium))
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            }
        }
        .environment(\.layoutDirection, arabic ? .rightToLeft : .leftToRight)
    }

    private var centeredLine: some View {
        VStack(alignment: .center, spacing: 2) {
            if pronunciationFirst {
                pronunciationText(alignment: .center)
                    .multilineTextAlignment(.center)
                styledScript(alignment: .center)
                    .frame(maxWidth: .infinity)
            } else {
                styledScript(alignment: .center)
                    .frame(maxWidth: .infinity)
                if let pronunciation {
                    pronunciationText(alignment: .center)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, arabic ? .rightToLeft : .leftToRight)
    }

    @ViewBuilder
    private func styledScript(alignment: TextAlignment) -> some View {
        let line = script(alignment: alignment)
        if let scriptFont {
            line.font(scriptFont)
        } else if pronunciationFirst {
            line.font(.subheadline.weight(.medium))
        } else {
            line
        }
    }

    @ViewBuilder
    private func pronunciationText(alignment: TextAlignment) -> some View {
        let line = Text(pronunciation ?? "")
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
            .environment(\.layoutDirection, .leftToRight)
        if let textColor, pronunciationFirst {
            line.foregroundStyle(textColor)
        } else {
            line.foregroundStyle(pronunciationColor)
        }
    }

    private func script(alignment: TextAlignment) -> some View {
        ZStack(alignment: .top) {
            word(alignment: alignment)
            if let mark {
                LetterMarkView(mark: mark)
                    .offset(y: -6)
            }
        }
        .environment(\.layoutDirection, arabic ? .rightToLeft : .leftToRight)
    }

    @ViewBuilder private func word(alignment: TextAlignment) -> some View {
        let line = Text(text)
            .multilineTextAlignment(alignment)
            .modifier(FitSingleWord(text: text, enabled: fitsWidth))
        if let textColor {
            line.foregroundStyle(textColor)
        } else if let scriptColor {
            line.foregroundStyle(scriptColor)
        } else {
            line
        }
    }
}

/// One word has no place to wrap, so it scales down instead of clipping. A phrase is unchanged.
private struct FitSingleWord: ViewModifier {
    var text: String
    var enabled: Bool

    private var scales: Bool {
        enabled && !text.contains(where: \.isWhitespace)
    }

    @ViewBuilder func body(content: Content) -> some View {
        if scales {
            content
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .allowsTightening(true)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

/// The ring or the dot, drawn on the letter after the answer.
private struct LetterMarkView: View {
    var mark: LetterMark

    var body: some View {
        switch mark {
        case .ring:
            Circle()
                .stroke(Lapis.ring, lineWidth: 2)
                .frame(width: 14, height: 14)
        case .dot:
            Circle()
                .fill(Lapis.ring)
                .frame(width: 8, height: 8)
        }
    }
}

/// Catalog strings for the quiz. The English matches `LetterContrasts` and `QuizAccessibilityText`.
enum QuizCopy {
    static func prompt(_ prompt: QuizPromptFace) -> String {
        guard let key = prompt.localizationKey else { return prompt.text }
        return localizedHint(key) ?? prompt.text
    }

    static func choiceLabel(_ option: QuizOptionFace, mark: QuizResultMark?) -> String {
        let base: String
        switch option.accessibility {
        case .optionNumber(let number):
            base = optionNumber(number)
        case .visible(let text):
            if let pronunciation = option.pronunciation {
                base = "\(pronunciation), \(text)"
            } else {
                base = text
            }
        }
        guard let mark else { return base }
        return "\(base), \(feedbackSpoken(correct: mark == .correct))"
    }

    static func feedbackSpoken(correct: Bool) -> String {
        correct
            ? String(localized: "quiz.feedback.correct")
            : String(localized: "quiz.feedback.incorrect")
    }

    private static func optionNumber(_ number: Int) -> String {
        switch number {
        case 1: String(localized: "quiz.option.1")
        case 2: String(localized: "quiz.option.2")
        case 3: String(localized: "quiz.option.3")
        case 4: String(localized: "quiz.option.4")
        default: "Option \(number)"
        }
    }

    private static func localizedHint(_ key: String) -> String? {
        switch key {
        case "quiz.letterHint.da.plain": String(localized: "quiz.letterHint.da.plain")
        case "quiz.letterHint.da.ring": String(localized: "quiz.letterHint.da.ring")
        case "quiz.letterHint.ta.plain": String(localized: "quiz.letterHint.ta.plain")
        case "quiz.letterHint.ta.ring": String(localized: "quiz.letterHint.ta.ring")
        case "quiz.letterHint.ra.plain": String(localized: "quiz.letterHint.ra.plain")
        case "quiz.letterHint.ra.ring": String(localized: "quiz.letterHint.ra.ring")
        case "quiz.letterHint.za.dalDot": String(localized: "quiz.letterHint.za.dalDot")
        case "quiz.letterHint.za.raDot": String(localized: "quiz.letterHint.za.raDot")
        default: nil
        }
    }
}

/// Girih sheet behind Correct or Incorrect. It comes in with the grade and does not block Continue.
private struct QuizResultSheet: View {
    var result: GradeResult

    private var fill: Color {
        result == .correct ? Lapis.correctFill : Lapis.incorrectFill
    }

    private var edge: Color {
        result == .correct ? Lapis.correct : Lapis.destructive
    }

    var body: some View {
        shape
            .fill(fill)
            .overlay {
                GirihPattern()
                    .opacity(0.45)
                    .clipShape(shape)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay {
                shape.strokeBorder(edge, lineWidth: 2)
                    .accessibilityHidden(true)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 24,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: 24
            ),
            style: .continuous
        )
    }
}

/// Chosen word tiles, right to left, wrapping so a pronunciation is not clipped.
private struct QuizWordWrap: Layout {
    var spacing: CGFloat = 8
    var rtl = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        let rows = rows(maxWidth: width, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? (rows.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        var index = 0
        for row in rows {
            var x = rtl ? bounds.maxX : bounds.minX
            for size in row.sizes {
                let originX = rtl ? x - size.width : x
                subviews[index].place(
                    at: CGPoint(x: originX, y: y),
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                x += rtl ? -(size.width + spacing) : (size.width + spacing)
                index += 1
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var sizes: [CGSize]
        var width: CGFloat
        var height: CGFloat
    }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let next = width == 0 ? size.width : width + spacing + size.width
            if width > 0, next > maxWidth {
                rows.append(Row(sizes: sizes, width: width, height: height))
                sizes = [size]
                width = size.width
                height = size.height
            } else {
                sizes.append(size)
                width = next
                height = max(height, size.height)
            }
        }
        if !sizes.isEmpty {
            rows.append(Row(sizes: sizes, width: width, height: height))
        }
        return rows
    }
}
