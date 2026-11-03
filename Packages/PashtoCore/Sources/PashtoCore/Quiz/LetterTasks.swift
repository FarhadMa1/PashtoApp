import Foundation

/// Letter questions for v1.0.
///
/// B1 shows the letter's English description (`en`) and asks for the glyph.
/// The Pashto name and the `sound` field stay off the question: the name
/// starts with the answer, and `sound` is scholarly transliteration.
/// B1 never offers the sound twin. The twin would be a second right answer.
/// B2 shows one shape hint and asks which of two same-sound letters it is.
/// B3 shows a word and asks for its first letter, and the sound twin is one
/// of the wrong glyphs. A word that starts with آ is skipped. Leading
/// diacritics are not the first letter. B1 and B3 option pronunciations are
/// a display rule, not stored on the task.
enum LetterTasks {
    static func findLetter(
        for target: ContentItem,
        in context: QuizContext,
        using rng: inout some RandomNumberGenerator
    ) -> QuizTask? {
        guard target.kind == .letter else { return nil }
        guard let prompt = englishPrompt(for: target) else { return nil }
        guard let options = glyphOptions(correct: target, in: context, includeSoundTwin: false, using: &rng) else {
            return nil
        }
        return QuizTask(
            kind: .findLetter,
            targetID: target.id,
            prompt: prompt,
            usage: blankToNil(target.usage),
            options: options
        )
    }

    static func contrast(
        for target: ContentItem,
        in context: QuizContext,
        using rng: inout some RandomNumberGenerator
    ) -> QuizTask? {
        guard target.kind == .letter else { return nil }
        guard let entry = LetterContrasts.entry(matching: target.pashto) else { return nil }
        guard let hint = LetterContrasts.hint(for: target) else { return nil }
        guard let partner = seenLetter(matching: entry.partnerGlyph, in: context) else { return nil }
        guard partner.id != target.id else { return nil }
        guard let correctGlyph = glyph(of: target), let partnerGlyph = glyph(of: partner) else { return nil }
        guard Normalization.nfc(correctGlyph) != Normalization.nfc(partnerGlyph) else { return nil }
        let options = shuffled(
            [
                QuizOption(itemID: target.id, text: correctGlyph),
                QuizOption(itemID: partner.id, text: partnerGlyph),
            ],
            using: &rng
        )
        return QuizTask(
            kind: .letterContrast,
            targetID: target.id,
            prompt: hint,
            usage: nil,
            options: options
        )
    }

    static func firstLetter(
        of word: ContentItem,
        in context: QuizContext,
        using rng: inout some RandomNumberGenerator
    ) -> QuizTask? {
        guard word.kind != .letter else { return nil }
        guard !startsWithAlefMadda(word.pashto) else { return nil }
        guard let first = firstGlyph(in: word.pashto) else { return nil }
        guard let letter = seenLetter(matching: first, in: context) else { return nil }
        guard let options = glyphOptions(correct: letter, in: context, includeSoundTwin: true, using: &rng) else {
            return nil
        }
        return QuizTask(
            kind: .firstLetter,
            targetID: letter.id,
            prompt: word.pashto,
            usage: blankToNil(word.usage),
            options: options,
            promptItemID: word.id
        )
    }

    /// True when the first letter is آ (U+0622). Spaces and combining marks are skipped.
    static func startsWithAlefMadda(_ pashto: String) -> Bool {
        baseScalar(in: pashto) == alefWithMadda
    }

    private static let alefWithMadda = Unicode.Scalar(0x0622)!

    /// English description only. `name` and `sound` are never the question.
    private static func englishPrompt(for letter: ContentItem) -> String? {
        blankToNil(letter.en)
    }

    /// The first letter, after spaces and combining marks. آ has no glyph question.
    private static func firstGlyph(in pashto: String) -> String? {
        guard let first = baseScalar(in: pashto), first != alefWithMadda else { return nil }
        return String(first)
    }

    /// First scalar that is not a space and not a combining mark.
    private static func baseScalar(in pashto: String) -> Unicode.Scalar? {
        pashto.unicodeScalars.first { scalar in
            !scalar.properties.isWhitespace && scalar.properties.canonicalCombiningClass == .notReordered
        }
    }

    private static func seenLetter(matching glyph: String, in context: QuizContext) -> ContentItem? {
        let course = CourseOrder(context.bundle)
        let wanted = Normalization.nfc(glyph)
        let seen = Set(context.seenLessonIDs)
        let retired = Set(context.retiredItemIDs)
        for introduction in course.introductions {
            guard seen.contains(introduction.lessonID), !retired.contains(introduction.itemID) else { continue }
            guard let item = course.itemsByID[introduction.itemID], item.kind == .letter else { continue }
            if Normalization.nfc(item.pashto) == wanted { return item }
            if let isolated = item.forms?.isolated, Normalization.nfc(isolated) == wanted { return item }
        }
        return nil
    }

    /// Same source order as the other choice questions: this lesson, then
    /// earlier lessons, then earlier units. At least three glyphs, at most four.
    ///
    /// B1 passes `includeSoundTwin: false`. The twin sounds the same, so it
    /// would be a second right answer. B3 passes `true` and puts that twin
    /// in the wrong answers when the learner has already seen it.
    private static func glyphOptions(
        correct: ContentItem,
        in context: QuizContext,
        includeSoundTwin: Bool,
        using rng: inout some RandomNumberGenerator
    ) -> [QuizOption]? {
        let course = CourseOrder(context.bundle)
        guard let correctGlyph = glyph(of: correct) else { return nil }
        let twinGlyph = LetterContrasts.entry(matching: correct.pashto)?.partnerGlyph
        let ranked = Distractors.candidates(for: correct, in: context)
        var distractors: [QuizOption] = []
        var seenKeys = [Normalization.nfc(correctGlyph)]
        if includeSoundTwin, let twin = soundTwin(of: correct, glyph: twinGlyph, in: context),
           let text = glyph(of: twin) {
            let key = Normalization.nfc(text)
            if !seenKeys.contains(key) {
                seenKeys.append(key)
                distractors.append(QuizOption(itemID: twin.id, text: text))
            }
        }
        let levels: [DistractorSource] = [.sameLesson, .earlierLessonInUnit, .earlierUnit]
        for level in levels where distractors.count < 3 {
            var pool: [(item: ContentItem, text: String)] = []
            for candidate in ranked where candidate.source == level {
                guard let item = course.itemsByID[candidate.itemID] else { continue }
                guard let text = glyph(of: item) else { continue }
                let key = Normalization.nfc(text)
                guard !seenKeys.contains(key) else { continue }
                if let twinGlyph, Normalization.nfc(twinGlyph) == key, !includeSoundTwin {
                    continue
                }
                pool.append((item, text))
            }
            while distractors.count < 3, !pool.isEmpty {
                let index = Int(rng.next() % UInt64(pool.count))
                let picked = pool.remove(at: index)
                let key = Normalization.nfc(picked.text)
                guard !seenKeys.contains(key) else { continue }
                seenKeys.append(key)
                distractors.append(QuizOption(itemID: picked.item.id, text: picked.text))
            }
        }
        guard distractors.count >= 2 else { return nil }
        var options = [QuizOption(itemID: correct.id, text: correctGlyph)]
        options.append(contentsOf: distractors)
        return shuffled(options, using: &rng)
    }

    private static func glyph(of item: ContentItem) -> String? {
        blankToNil(item.pashto)
    }

    private static func soundTwin(
        of letter: ContentItem,
        glyph: String?,
        in context: QuizContext
    ) -> ContentItem? {
        guard let glyph else { return nil }
        guard let twin = seenLetter(matching: glyph, in: context) else { return nil }
        guard twin.id != letter.id else { return nil }
        return twin
    }
}
