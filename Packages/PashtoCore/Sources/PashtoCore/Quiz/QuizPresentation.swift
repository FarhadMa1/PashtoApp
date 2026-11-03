import Foundation

/// What VoiceOver should speak for one answer choice.
public enum QuizAccessibilityText: Hashable, Sendable {
    /// The text on the screen. Used after the question is answered, and when VoiceOver is off.
    case visible(String)
    /// "Option 1" through "Option 4", before the question is answered.
    case optionNumber(Int)

    /// The English label. The app catalog uses the same words.
    public var spokenEnglish: String {
        switch self {
        case .visible(let text):
            return text
        case .optionNumber(let number):
            return "Option \(number)"
        }
    }
}

/// The prompt line, with pronunciation only when it should be on screen.
public struct QuizPromptFace: Hashable, Sendable {
    public let text: String
    /// Simple pronunciation under Arabic script. Nil when it stays hidden.
    public let pronunciation: String?
    /// String-catalog key when `text` is one of the built-in shape hints.
    public let localizationKey: String?
}

/// One answer choice as the screen draws it.
public struct QuizOptionFace: Hashable, Sendable {
    public let itemID: ItemID
    public let text: String
    public let pronunciation: String?
    /// True for B1 and B3. The line is kept even while `pronunciation` is nil,
    /// so the choice does not grow when the answer is shown.
    public let reservesPronunciation: Bool
    public let accessibility: QuizAccessibilityText
    /// Ring or dot, drawn on a same-sound choice after the answer.
    public let highlight: LetterMark?
}

/// The check or the cross next to Correct / Incorrect.
///
/// Colour is not the only cue. `spokenEnglish` matches the app catalog.
public enum QuizResultMark: Hashable, Sendable {
    case correct
    case incorrect

    public var symbolName: String {
        switch self {
        case .correct: "checkmark"
        case .incorrect: "xmark"
        }
    }

    public var spokenEnglish: String {
        switch self {
        case .correct: "Correct"
        case .incorrect: "Incorrect"
        }
    }
}

/// A multiple-choice question ready to draw.
///
/// `translit` is never copied onto this value. Pronunciation comes from
/// `ContentItem.pronunciation` and only for Arabic script.
public struct QuizFace: Hashable, Sendable {
    public let prompt: QuizPromptFace
    public let options: [QuizOptionFace]
    public let usage: String?
}

/// Turns a stored question into the lines the screen shows.
public enum QuizPresentation {
    public static func face(
        for task: QuizTask,
        items: [ContentItem],
        showsPronunciation: Bool,
        voiceOver: Bool,
        answered: Bool
    ) -> QuizFace {
        var byID: [ItemID: ContentItem] = [:]
        for item in items where byID[item.id] == nil {
            byID[item.id] = item
        }
        let promptItem = byID[task.promptItemID ?? task.targetID]
        let options = task.options.enumerated().map { offset, option -> QuizOptionFace in
            let item = byID[option.itemID]
            let pronunciation = optionPronunciation(
                kind: task.kind,
                text: option.text,
                item: item,
                showsPronunciation: showsPronunciation,
                answered: answered
            )
            let highlight: LetterMark?
            if answered, task.kind == .letterContrast, let glyph = item?.pashto {
                highlight = LetterContrasts.entry(matching: glyph)?.mark
            } else {
                highlight = nil
            }
            let accessibility: QuizAccessibilityText
            let number = offset + 1
            // Option N is only for letter glyphs. Reading those aloud is the answer.
            // Meaning questions and every other task keep the real text.
            let letterGlyph = task.kind == .findLetter || task.kind == .letterContrast || task.kind == .firstLetter
            if voiceOver, !answered, letterGlyph, (1...4).contains(number) {
                accessibility = .optionNumber(number)
            } else {
                accessibility = .visible(option.text)
            }
            let reservesPronunciation = task.kind == .findLetter || task.kind == .firstLetter
            return QuizOptionFace(
                itemID: option.itemID,
                text: option.text,
                pronunciation: pronunciation,
                reservesPronunciation: reservesPronunciation,
                accessibility: accessibility,
                highlight: highlight
            )
        }
        let promptKey = task.kind == .letterContrast ? LetterContrasts.localizationKey(for: task.prompt) : nil
        return QuizFace(
            prompt: QuizPromptFace(
                text: task.prompt,
                pronunciation: spokenPronunciation(
                    text: task.prompt,
                    item: promptItem,
                    showsPronunciation: showsPronunciation
                ),
                localizationKey: promptKey
            ),
            options: options,
            usage: task.usage
        )
    }

    /// Pronunciation under an answer glyph.
    ///
    /// B1 and B3 keep it off until the question is answered, because the
    /// pronunciation would name the letter. Every other Arabic option shows
    /// it whenever the session is showing pronunciation.
    public static func optionPronunciation(
        kind: TaskKind,
        text: String,
        item: ContentItem?,
        showsPronunciation: Bool,
        answered: Bool
    ) -> String? {
        let hidesUntilAnswer = kind == .findLetter || kind == .firstLetter
        if hidesUntilAnswer, !answered { return nil }
        return spokenPronunciation(text: text, item: item, showsPronunciation: showsPronunciation)
    }

    /// Pronunciation under one word tile.
    ///
    /// Shown before the answer, whenever the session is showing pronunciation.
    /// The whole sentence stays hidden until `sentencePronunciation`.
    public static func tilePronunciation(_ pronunciation: String?, showsPronunciation: Bool) -> String? {
        guard showsPronunciation, let pronunciation, !Text.isBlank(pronunciation) else { return nil }
        return pronunciation
    }

    /// Pronunciation of a whole ordered sentence.
    ///
    /// Hidden until the learner has answered. Before that, the pronunciation
    /// is the sentence in the right order.
    public static func sentencePronunciation(
        item: ContentItem?,
        showsPronunciation: Bool,
        answered: Bool
    ) -> String? {
        guard answered, let item else { return nil }
        return spokenPronunciation(text: item.pashto, item: item, showsPronunciation: showsPronunciation)
    }

    /// What VoiceOver reads for one side of a match, including a link the learner made.
    public static func matchAccessibilityLabel(
        text: String,
        pronunciation: String?,
        linkedText: String?
    ) -> String {
        var parts = [text]
        if let pronunciation, !Text.isBlank(pronunciation) {
            parts.append(pronunciation)
        }
        if let linkedText, !Text.isBlank(linkedText) {
            parts.append(linkedText)
        }
        return parts.joined(separator: ", ")
    }

    /// The pronunciation field under Arabic script, or nil.
    ///
    /// This never reads `translit`.
    public static func spokenPronunciation(
        text: String,
        item: ContentItem?,
        showsPronunciation: Bool
    ) -> String? {
        guard showsPronunciation, containsArabicScript(text) else { return nil }
        guard let pronunciation = item?.pronunciation, !Text.isBlank(pronunciation) else { return nil }
        return pronunciation
    }

    public static func containsArabicScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
                return true
            default:
                return false
            }
        }
    }
}
