import PashtoCore
import SwiftUI

/// One quiz question: the prompt, the choices, and the feedback after an answer.
///
/// Pashto is drawn right to left, with `pronunciation` underneath. Scholarly
/// transliteration is not shown. B1 and B3 keep pronunciation off the choices
/// until the question has been answered. A same-sound choice draws its ring
/// or dot after the answer.
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
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private let itemsByID: [ItemID: ContentItem]
    var onAnswer: (LessonSession) -> Void
    var onFinish: (LessonSession) -> Void

    init(
        session: LessonSession,
        items: [ContentItem],
        onAnswer: @escaping (LessonSession) -> Void = { _ in },
        onFinish: @escaping (LessonSession) -> Void = { _ in }
    ) {
        _session = State(initialValue: session)
        self.onAnswer = onAnswer
        self.onFinish = onFinish
        var map: [ItemID: ContentItem] = [:]
        for item in items where map[item.id] == nil {
            map[item.id] = item
        }
        itemsByID = map
    }

    var body: some View {
        LapisScreen {
            VStack(alignment: .leading, spacing: 16) {
                LessonProgressBar(bar: lessonBar)
                if let task = session.current {
                    question(task)
                    if revealed, let result {
                        feedback(result)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            .sensoryFeedback(.success, trigger: correctHaptics)
            .sensoryFeedback(.error, trigger: wrongHaptics)
            .onChange(of: result) { _, graded in
                // One announcement for the result. Motion must not post another.
                guard let graded else { return }
                AccessibilityNotification.Announcement(QuizCopy.feedbackSpoken(correct: graded == .correct)).post()
            }
        } footer: {
            Button(action: advance) {
                Text("quiz.continue.button")
            }
            .buttonStyle(SaffronButtonStyle())
            .disabled(!canContinue)
        }
    }

    @ViewBuilder
    private func question(_ task: SessionTask) -> some View {
        switch task.payload {
        case .choice(let quiz):
            choice(quiz)
        case .matchPairs(let match):
            matchPairs(match)
        case .orderWords(let order):
            orderWords(order)
        }
    }

    private func choice(_ quiz: QuizTask) -> some View {
        let face = QuizPresentation.face(
            for: quiz,
            items: Array(itemsByID.values),
            showsPronunciation: session.showsPronunciation,
            voiceOver: voiceOverEnabled,
            answered: revealed
        )
        return VStack(alignment: .leading, spacing: 16) {
            prompt(face.prompt, task: quiz)
            if let usage = face.usage {
                Text(usage)
                    .font(.subheadline)
                    .foregroundStyle(Lapis.secondaryText)
            }
            VStack(spacing: 10) {
                ForEach(face.options, id: \.itemID) { option in
                    choiceButton(option, correctID: quiz.targetID, mark: mark(for: option.itemID, correctID: quiz.targetID))
                }
            }
        }
    }

    @ViewBuilder
    private func prompt(_ prompt: QuizPromptFace, task: QuizTask) -> some View {
        let text = QuizCopy.prompt(prompt)
        if QuizPresentation.containsArabicScript(text) {
            GlyphCard(
                model: GlyphCardModel.make(
                    glyph: text,
                    pronunciation: prompt.pronunciation,
                    meaning: itemsByID[task.promptItemID ?? task.targetID]?.en,
                    kind: task.kind,
                    answered: revealed
                )
            )
            .id(questionToken)
        } else {
            PashtoLine(
                text: text,
                pronunciation: prompt.pronunciation,
                arabic: false
            )
            .font(.title2.weight(.semibold))
            .foregroundStyle(Lapis.text)
        }
    }

    private func choiceButton(_ option: QuizOptionFace, correctID: ItemID, mark: QuizResultMark?) -> some View {
        Button {
            pick(option.itemID)
        } label: {
            HStack(spacing: 10) {
                PashtoLine(
                    text: option.text,
                    pronunciation: option.pronunciation,
                    arabic: QuizPresentation.containsArabicScript(option.text),
                    mark: option.highlight,
                    reservesPronunciation: option.reservesPronunciation,
                    textColor: mark == nil ? nil : Lapis.fillText,
                    pronunciationColor: mark == nil ? Lapis.secondaryText : Lapis.fillPronunciation
                )
                .font(.title3.weight(.semibold))
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
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill(for: mark))
                    .animation(.easeOut(duration: QuizMotion.reduceMotionFade), value: mark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(border(for: option, mark: mark), lineWidth: 2)
                    .animation(.easeOut(duration: QuizMotion.reduceMotionFade), value: mark)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(Lapis.text)
        .disabled(revealed)
        .modifier(ChoiceMotion(mark: mark, moves: pickedChoice == option.itemID))
        .accessibilityLabel(QuizCopy.choiceLabel(option, mark: mark))
        .id("\(questionToken)-\(option.itemID.rawValue)")
    }

    /// Correct stays marked after a wrong pick, so the right glyph is not only a color.
    private func mark(for optionID: ItemID, correctID: ItemID) -> QuizResultMark? {
        guard revealed else { return nil }
        if optionID == correctID { return .correct }
        if optionID == pickedChoice { return .incorrect }
        return nil
    }

    private func border(for option: QuizOptionFace, mark: QuizResultMark?) -> Color {
        switch mark {
        case .correct:
            return Lapis.correct
        case .incorrect:
            return Lapis.destructive
        case nil:
            return pickedChoice == option.itemID ? Lapis.ring : Lapis.secondaryText.opacity(0.35)
        }
    }

    private func fill(for mark: QuizResultMark?) -> Color {
        switch mark {
        case .correct:
            return Lapis.correctFill
        case .incorrect:
            return Lapis.incorrectFill
        case nil:
            return .clear
        }
    }

    private func feedback(_ result: GradeResult) -> some View {
        let mark: QuizResultMark = result == .correct ? .correct : .incorrect
        return HStack(spacing: 8) {
            Image(systemName: mark.symbolName)
                .font(.headline.weight(.bold))
                .foregroundStyle(markColor(mark))
                .accessibilityHidden(true)
            Text(feedbackKey(result))
                .font(.headline)
                .foregroundStyle(result == .correct ? Lapis.correctText : Lapis.destructive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(result == .correct ? Lapis.correctFill : Lapis.incorrectFill)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(feedbackKey(result)))
        .accessibilityAddTraits(.isHeader)
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

    private func matchPairs(_ task: MatchPairsTask) -> some View {
        MatchingBoard(
            task: task,
            links: links,
            selectedLeft: selectedLeft,
            revealed: revealed,
            showsPronunciation: session.showsPronunciation,
            itemsByID: itemsByID,
            onLeft: { id in
                guard !revealed else { return }
                if selectedLeft == id {
                    links = QuizDraft.unlink(links, left: id)
                    selectedLeft = nil
                } else {
                    selectedLeft = id
                }
            },
            onRight: { link($0) }
        )
        .id(questionToken)
    }

    private func orderWords(_ task: OrderWordsTask) -> some View {
        let chosen = placed.compactMap { index in task.tiles.first { $0.index == index } }
        let pool = task.tiles.filter { !placed.contains($0.index) }
        return VStack(alignment: .leading, spacing: 12) {
            if !chosen.isEmpty || !task.fixedEnding.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        ForEach(chosen, id: \.index) { tile in
                            Button {
                                guard !revealed else { return }
                                placed = QuizDraft.place(placed, tile: tile.index)
                            } label: {
                                PashtoLine(
                                    text: tile.text,
                                    pronunciation: tilePronunciation(tile),
                                    arabic: QuizPresentation.containsArabicScript(tile.text)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(revealed)
                            .accessibilityLabel(tileAccessibility(tile))
                        }
                        if !task.fixedEnding.isEmpty {
                            Text(task.fixedEnding)
                        }
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                    if let pronunciation = QuizPresentation.sentencePronunciation(
                        item: itemsByID[task.targetID],
                        showsPronunciation: session.showsPronunciation,
                        answered: revealed
                    ) {
                        Text(pronunciation)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Lapis.secondaryText)
                    }
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(Lapis.text)
            }
            ForEach(pool, id: \.index) { tile in
                Button {
                    guard !revealed else { return }
                    placed = QuizDraft.place(placed, tile: tile.index)
                } label: {
                    PashtoLine(
                        text: tile.text,
                        pronunciation: tilePronunciation(tile),
                        arabic: QuizPresentation.containsArabicScript(tile.text)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Lapis.text)
                .disabled(revealed)
                .accessibilityLabel(tileAccessibility(tile))
            }
        }
    }

    private func tilePronunciation(_ tile: WordTile) -> String? {
        QuizPresentation.tilePronunciation(tile.pronunciation, showsPronunciation: session.showsPronunciation)
    }

    private func tileAccessibility(_ tile: WordTile) -> String {
        if let spoken = tilePronunciation(tile) {
            return "\(tile.text), \(spoken)"
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

    private var questionToken: Int { session.answers.count }

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
        } else {
            onAnswer(session)
        }
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
struct PashtoLine: View {
    var text: String
    var pronunciation: String?
    var arabic: Bool
    var mark: LetterMark?
    var reservesPronunciation = false
    var textColor: Color? = nil
    var pronunciationColor: Color = Lapis.secondaryText
    /// Shrinks one long word so the 56 pt glyph stays inside the card at the largest type size.
    var fitsWidth = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack(alignment: .top) {
                word
                if let mark {
                    LetterMarkView(mark: mark)
                        .offset(y: -6)
                }
            }
            if let pronunciation {
                Text(pronunciation)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(pronunciationColor)
                    .environment(\.layoutDirection, .leftToRight)
            } else if reservesPronunciation {
                Text(" ")
                    .font(.subheadline.weight(.medium))
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
        .environment(\.layoutDirection, arabic ? .rightToLeft : .leftToRight)
    }

    @ViewBuilder private var word: some View {
        let line = Text(text)
            .multilineTextAlignment(.leading)
            .modifier(FitSingleWord(text: text, enabled: fitsWidth))
        if let textColor {
            line.foregroundStyle(textColor)
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
                base = "\(text), \(pronunciation)"
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
