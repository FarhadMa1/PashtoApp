import PashtoCore
import SwiftUI

/// Builds a lesson quiz from released units only.
///
/// `showsPronunciation` is copied from the settings at the moment the session
/// starts. A later change to `showTransliteration` is used by the next session.
/// `voiceOver` is the value at that same moment: letter tasks are replaced
/// with meaning tasks when it is on.
enum QuizLaunch {
    static func lessonSession(
        for lessonID: LessonID,
        in bundle: ContentBundle,
        seenLessonIDs: [LessonID],
        releasedUnitIDs: [UnitID],
        settings: UserSettings,
        voiceOver: Bool,
        using rng: inout some RandomNumberGenerator
    ) -> LessonSession {
        LessonSessionBuilder.build(
            for: lessonID,
            in: bundle,
            seenLessonIDs: seenLessonIDs,
            releasedUnitIDs: releasedUnitIDs,
            showsPronunciation: settings.showTransliteration,
            voiceOver: voiceOver,
            using: &rng
        )
    }
}

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
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private let itemsByID: [ItemID: ContentItem]
    var onFinish: () -> Void

    init(session: LessonSession, items: [ContentItem], onFinish: @escaping () -> Void = {}) {
        _session = State(initialValue: session)
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
            .onChange(of: result) { _, graded in
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
            prompt(face.prompt)
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

    private func prompt(_ prompt: QuizPromptFace) -> some View {
        PashtoLine(
            text: QuizCopy.prompt(prompt),
            pronunciation: prompt.pronunciation,
            arabic: QuizPresentation.containsArabicScript(prompt.text)
        )
        .font(.title2.weight(.semibold))
        .foregroundStyle(Lapis.text)
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
                if let mark {
                    Image(systemName: mark.symbolName)
                        .font(.body.weight(.bold))
                        .foregroundStyle(markColor(mark))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill(for: mark))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(border(for: option, mark: mark), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(Lapis.text)
        .disabled(revealed)
        .accessibilityLabel(QuizCopy.choiceLabel(option, mark: mark))
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
            return pickedChoice == option.itemID ? Lapis.saffron : Lapis.secondaryText.opacity(0.35)
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
        VStack(alignment: .leading, spacing: 12) {
            ForEach(task.pairs, id: \.left.itemID) { pair in
                let linked = linkedSide(in: task, id: links[pair.left.itemID])
                let spoken = pronunciation(for: pair.left.text, itemID: pair.left.itemID)
                let mark = QuizDraft.pairMark(
                    linkedRight: links[pair.left.itemID],
                    correctRight: pair.right.itemID,
                    revealed: revealed
                )
                Button {
                    guard !revealed else { return }
                    if selectedLeft == pair.left.itemID {
                        links = QuizDraft.unlink(links, left: pair.left.itemID)
                        selectedLeft = nil
                    } else {
                        selectedLeft = pair.left.itemID
                    }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            PashtoLine(
                                text: pair.left.text,
                                pronunciation: spoken,
                                arabic: QuizPresentation.containsArabicScript(pair.left.text),
                                textColor: mark == nil ? nil : Lapis.fillText,
                                pronunciationColor: mark == nil ? Lapis.secondaryText : Lapis.fillPronunciation
                            )
                            if let linked {
                                PashtoLine(
                                    text: linked.text,
                                    pronunciation: pronunciation(for: linked.text, itemID: linked.itemID),
                                    arabic: QuizPresentation.containsArabicScript(linked.text),
                                    textColor: mark == nil ? nil : Lapis.fillText,
                                    pronunciationColor: mark == nil ? Lapis.secondaryText : Lapis.fillPronunciation
                                )
                                .font(.subheadline)
                            }
                        }
                        Spacer(minLength: 0)
                        if let mark {
                            Image(systemName: mark.symbolName)
                                .font(.body.weight(.bold))
                                .foregroundStyle(markColor(mark))
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(fill(for: mark))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                matchBorder(selected: selectedLeft == pair.left.itemID, mark: mark),
                                lineWidth: selectedLeft == pair.left.itemID && mark == nil ? 3 : 2
                            )
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(Lapis.text)
                .accessibilityLabel(matchLabel(text: pair.left.text, pronunciation: spoken, linkedText: linked?.text, mark: mark))
                .accessibilityAddTraits(selectedLeft == pair.left.itemID ? .isSelected : AccessibilityTraits())
            }
            ForEach(task.rightColumn, id: \.itemID) { side in
                Button {
                    link(side.itemID)
                } label: {
                    PashtoLine(
                        text: side.text,
                        pronunciation: pronunciation(for: side.text, itemID: side.itemID),
                        arabic: QuizPresentation.containsArabicScript(side.text)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Lapis.text)
                .disabled(revealed || selectedLeft == nil)
                .accessibilityLabel(
                    QuizPresentation.matchAccessibilityLabel(
                        text: side.text,
                        pronunciation: pronunciation(for: side.text, itemID: side.itemID),
                        linkedText: nil
                    )
                )
            }
        }
    }

    private func matchBorder(selected: Bool, mark: QuizResultMark?) -> Color {
        switch mark {
        case .correct:
            return Lapis.correct
        case .incorrect:
            return Lapis.destructive
        case nil:
            return selected ? Lapis.ring : Lapis.secondaryText.opacity(0.35)
        }
    }

    private func matchLabel(text: String, pronunciation: String?, linkedText: String?, mark: QuizResultMark?) -> String {
        let base = QuizPresentation.matchAccessibilityLabel(
            text: text,
            pronunciation: pronunciation,
            linkedText: linkedText
        )
        guard let mark else { return base }
        return "\(base), \(QuizCopy.feedbackSpoken(correct: mark == .correct))"
    }

    private func linkedSide(in task: MatchPairsTask, id: ItemID?) -> MatchSide? {
        guard let id else { return nil }
        return task.pairs.first { $0.right.itemID == id }?.right
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

    private func pronunciation(for text: String, itemID: ItemID) -> String? {
        QuizPresentation.spokenPronunciation(
            text: text,
            item: itemsByID[itemID],
            showsPronunciation: session.showsPronunciation
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
        result = grade(task, .choice(id))
    }

    private func link(_ right: ItemID) {
        guard !revealed, let left = selectedLeft else { return }
        links = QuizDraft.link(links, left: left, right: right)
        selectedLeft = nil
    }

    private func advance() {
        guard let task = session.current, let answer = answer(for: task) else { return }
        if !revealed {
            result = grade(task, answer)
            revealed = true
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
            onFinish()
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
private struct PashtoLine: View {
    var text: String
    var pronunciation: String?
    var arabic: Bool
    var mark: LetterMark?
    var reservesPronunciation = false
    var textColor: Color? = nil
    var pronunciationColor: Color = Lapis.secondaryText

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
        let line = Text(text).multilineTextAlignment(.leading)
        if let textColor {
            line.foregroundStyle(textColor)
        } else {
            line
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
