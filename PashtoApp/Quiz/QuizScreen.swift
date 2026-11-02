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
                        Text(result == .correct ? "quiz.feedback.correct" : "quiz.feedback.incorrect")
                            .font(.headline)
                            .foregroundStyle(result == .correct ? Lapis.text : Lapis.destructive)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
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
                    choiceButton(option, correctID: quiz.targetID)
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

    private func choiceButton(_ option: QuizOptionFace, correctID: ItemID) -> some View {
        Button {
            pick(option.itemID)
        } label: {
            HStack {
                PashtoLine(
                    text: option.text,
                    pronunciation: option.pronunciation,
                    arabic: QuizPresentation.containsArabicScript(option.text),
                    mark: option.highlight
                )
                .font(.title3.weight(.semibold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(border(for: option, correctID: correctID), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(Lapis.text)
        .disabled(revealed)
        .accessibilityLabel(QuizCopy.choiceLabel(option))
    }

    private func border(for option: QuizOptionFace, correctID: ItemID) -> Color {
        guard revealed else {
            return pickedChoice == option.itemID ? Lapis.saffron : Lapis.secondaryText.opacity(0.35)
        }
        if option.itemID == correctID { return Lapis.saffron }
        if option.itemID == pickedChoice { return Lapis.destructive }
        return Lapis.secondaryText.opacity(0.25)
    }

    private func matchPairs(_ task: MatchPairsTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(task.pairs, id: \.left.itemID) { pair in
                Button {
                    selectedLeft = pair.left.itemID
                } label: {
                    PashtoLine(
                        text: pair.left.text,
                        pronunciation: pronunciation(for: pair.left.text, itemID: pair.left.itemID),
                        arabic: QuizPresentation.containsArabicScript(pair.left.text)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedLeft == pair.left.itemID ? Lapis.saffron : Lapis.text)
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
                .disabled(revealed)
            }
        }
    }

    private func orderWords(_ task: OrderWordsTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let chosen = placed.compactMap { index in task.tiles.first { $0.index == index } }
            if !chosen.isEmpty || !task.fixedEnding.isEmpty {
                PashtoLine(
                    text: (chosen.map(\.text) + [task.fixedEnding]).filter { !$0.isEmpty }.joined(separator: " "),
                    pronunciation: pronunciation(for: task.tokens.joined(separator: " "), itemID: task.targetID),
                    arabic: true
                )
                .font(.title3.weight(.semibold))
            }
            ForEach(task.tiles.filter { !placed.contains($0.index) }, id: \.index) { tile in
                Button {
                    guard !revealed else { return }
                    placed.append(tile.index)
                } label: {
                    PashtoLine(
                        text: tile.text,
                        pronunciation: nil,
                        arabic: QuizPresentation.containsArabicScript(tile.text)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Lapis.text)
                .disabled(revealed)
            }
        }
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
        links[left] = right
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

    var body: some View {
        VStack(alignment: arabic ? .trailing : .leading, spacing: 2) {
            ZStack(alignment: .top) {
                Text(text)
                    .multilineTextAlignment(arabic ? .trailing : .leading)
                if let mark {
                    LetterMarkView(mark: mark)
                        .offset(y: -6)
                }
            }
            .environment(\.layoutDirection, arabic ? .rightToLeft : .leftToRight)
            if let pronunciation {
                Text(pronunciation)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Lapis.secondaryText)
                    .environment(\.layoutDirection, .leftToRight)
            }
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
                .stroke(Lapis.saffron, lineWidth: 2)
                .frame(width: 14, height: 14)
        case .dot:
            Circle()
                .fill(Lapis.saffron)
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

    static func choiceLabel(_ option: QuizOptionFace) -> String {
        switch option.accessibility {
        case .optionNumber(let number):
            return optionNumber(number)
        case .visible(let text):
            if let pronunciation = option.pronunciation {
                return "\(text), \(pronunciation)"
            }
            return text
        }
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
