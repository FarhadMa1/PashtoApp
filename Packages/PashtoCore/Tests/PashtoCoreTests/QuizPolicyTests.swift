import Foundation
import Testing
@testable import PashtoCore

struct QuizPolicyTests {
    @Test func pronunciationOnAsksForMeaningAndSkipsThePronunciationTask() {
        let on = courseSession(showsPronunciation: true)
        let off = courseSession(showsPronunciation: false)

        #expect(on.showsPronunciation)
        #expect(!off.showsPronunciation)
        #expect(on.tasks.contains { $0.kind == .meaningPashtoToEnglish })
        #expect(!on.tasks.contains { $0.kind == .transliterationChoice })
        #expect(off.tasks.contains { $0.kind == .transliterationChoice })
    }

    @Test func aRunningSessionKeepsThePronunciationSettingItStartedWith() throws {
        let started = UserSettings.initial
        let session = courseSession(showsPronunciation: started.showTransliteration)
        let changed = UserSettings(dailyGoal: .light, showTransliteration: false, placementTakenDay: nil)
        #expect(session.showsPronunciation)
        #expect(changed.showTransliteration == false)
        #expect(!session.tasks.contains { $0.kind == .transliterationChoice })

        let next = courseSession(showsPronunciation: changed.showTransliteration)
        #expect(next.showsPronunciation == false)
        #expect(next.tasks.contains { $0.kind == .transliterationChoice })

        let stored = Data(#"{"lessonID":"l-one","tasks":[],"answers":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(LessonSession.self, from: stored)
        #expect(decoded.showsPronunciation)
    }

    @Test func letterTasksReplaceTheOldRevealingChoicesWhilePronunciationIsShown() {
        let session = courseSession(showsPronunciation: true)
        let letters = Set(sampleLetters().map(\.id))
        let letterTasks = session.tasks.filter { task in
            guard case .choice(let quiz) = task.payload else { return false }
            return letters.contains(quiz.targetID) || quiz.promptItemID != nil && letters.contains(quiz.targetID)
        }
        #expect(session.tasks.contains { $0.kind == .findLetter })
        #expect(session.tasks.contains { $0.kind == .letterContrast })
        #expect(!letterTasks.contains { $0.kind == .meaningPashtoToEnglish })
        #expect(!letterTasks.contains { $0.kind == .meaningEnglishToPashto })
        #expect(!letterTasks.contains { $0.kind == .transliterationChoice })
    }

    @Test func sameSoundPairsUseTheExactHintsAndStayWhenPronunciationIsOff() {
        #expect(LetterContrasts.entries.map(\.hint) == [
            "da, plain, no ring",
            "da with a ring (tongue curled back)",
            "ta, two dots, no ring",
            "ta with a ring (tongue curled back)",
            "ra, plain, no ring",
            "ra with a ring (tongue curled back)",
            "za, dot on the da shape",
            "za, dot on the ra shape",
        ])

        for showsPronunciation in [true, false] {
            let session = courseSession(showsPronunciation: showsPronunciation)
            let contrasts = choiceTasks(in: session, kind: .letterContrast)
            #expect(!contrasts.isEmpty)
            for task in contrasts {
                #expect(Set(task.options.map(\.text)) == ["د", "ډ"])
                let target = sampleLetters().first { $0.id == task.targetID }
                #expect(task.prompt == target.flatMap(LetterContrasts.hint(for:)))
                #expect(task.options.count == 2)
            }
        }
    }

    @Test func findLetterAndFirstLetterHideOptionPronunciationUntilAnswered() throws {
        let session = courseSession(showsPronunciation: true)
        let items = sampleItems()
        let find = try #require(choiceTasks(in: session, kind: .findLetter).first)
        let before = QuizPresentation.face(
            for: find,
            items: items,
            showsPronunciation: true,
            voiceOver: false,
            answered: false
        )
        let after = QuizPresentation.face(
            for: find,
            items: items,
            showsPronunciation: true,
            voiceOver: false,
            answered: true
        )
        #expect(before.options.allSatisfy { $0.pronunciation == nil })
        #expect(after.options.allSatisfy { $0.pronunciation != nil })
        for option in after.options {
            let item = try #require(items.first { $0.id == option.itemID })
            #expect(option.pronunciation == item.pronunciation)
            #expect(option.pronunciation != item.translit)
        }

        let first = try #require(choiceTasks(in: session, kind: .firstLetter).first { $0.prompt == "در" })
        let hidden = QuizPresentation.face(
            for: first,
            items: items,
            showsPronunciation: true,
            voiceOver: false,
            answered: false
        )
        let shown = QuizPresentation.face(
            for: first,
            items: items,
            showsPronunciation: true,
            voiceOver: false,
            answered: true
        )
        #expect(hidden.prompt.pronunciation == "dar")
        #expect(hidden.prompt.pronunciation != "dar-scholar")
        #expect(hidden.options.allSatisfy { $0.pronunciation == nil })
        #expect(shown.options.allSatisfy { $0.pronunciation != nil })
    }

    @Test func sameSoundHighlightAppearsAfterTheAnswer() throws {
        let session = courseSession(showsPronunciation: true)
        let task = try #require(choiceTasks(in: session, kind: .letterContrast).first)
        let before = QuizPresentation.face(
            for: task,
            items: sampleItems(),
            showsPronunciation: true,
            voiceOver: false,
            answered: false
        )
        let after = QuizPresentation.face(
            for: task,
            items: sampleItems(),
            showsPronunciation: true,
            voiceOver: false,
            answered: true
        )
        #expect(before.options.allSatisfy { $0.highlight == nil })
        let ring = try #require(after.options.first { $0.text == "ډ" })
        let plain = try #require(after.options.first { $0.text == "د" })
        #expect(ring.highlight == .ring)
        #expect(plain.highlight == nil)
    }

    @Test func firstLetterSkipsAlefWithMadda() {
        let session = courseSession(showsPronunciation: true)
        let prompts = choiceTasks(in: session, kind: .firstLetter).map(\.prompt)
        #expect(prompts.contains("در"))
        #expect(!prompts.contains { LetterTasks.startsWithAlefMadda($0) })
        #expect(!prompts.contains("آب"))
    }

    @Test func voiceOverUsesMeaningTasksAndKeepsTheirRealLabels() throws {
        let session = courseSession(showsPronunciation: true, voiceOver: true)
        let letters = Set(sampleLetters().map(\.id))
        #expect(!session.tasks.contains { $0.kind == .findLetter })
        #expect(!session.tasks.contains { $0.kind == .letterContrast })
        #expect(!session.tasks.contains { $0.kind == .firstLetter })
        #expect(!session.tasks.contains { task in
            guard case .choice(let quiz) = task.payload else { return false }
            return letters.contains(quiz.targetID)
        })
        #expect(session.tasks.contains { $0.kind == .meaningPashtoToEnglish })

        let meaning = try #require(choiceTasks(in: session, kind: .meaningPashtoToEnglish).first)
        let hidden = QuizPresentation.face(
            for: meaning,
            items: sampleItems(),
            showsPronunciation: true,
            voiceOver: true,
            answered: false
        )
        #expect(hidden.options.map(\.accessibility) == meaning.options.map { .visible($0.text) })
        #expect(hidden.options.allSatisfy {
            if case .optionNumber = $0.accessibility { return false }
            return true
        })
    }

    @Test func onlyReleasedUnitsAreUsed() {
        let releasedWords = [
            policyWord("e-kept-a", "در", "dar", "one"),
            policyWord("e-kept-b", "تب", "tab", "two"),
        ]
        let hiddenWords = [
            policyWord("e-hidden-a", "بر", "bar", "three"),
            policyWord("e-hidden-b", "نو", "no", "four"),
        ]
        let releasedLesson = policyLesson("l-rel", words: releasedWords)
        let hiddenLesson = policyLesson("l-hid", words: hiddenWords)
        let bundle = policyBundle(
            units: [
                policyUnit("u-hid", lessons: [hiddenLesson]),
                policyUnit("u-rel", lessons: [releasedLesson]),
            ],
            items: releasedWords + hiddenWords
        )
        let seen = ["l-rel", "l-hid"]
        let open = policySession(bundle, lesson: "l-rel", seen: seen, released: nil)
        let closed = policySession(bundle, lesson: "l-rel", seen: seen, released: ["u-rel"])
        let blocked = policySession(bundle, lesson: "l-hid", seen: seen, released: ["u-rel"])

        #expect(open.tasks.contains { taskUsesUnreleasedItem($0) })
        #expect(!closed.tasks.contains { taskUsesUnreleasedItem($0) })
        #expect(blocked.tasks.isEmpty)
        #expect(blocked.showsPronunciation)
    }

    @Test func pronunciationStaysHiddenWhenTheSettingIsOff() throws {
        let session = courseSession(showsPronunciation: false)
        let task = try #require(choiceTasks(in: session, kind: .meaningEnglishToPashto).first)
        let face = QuizPresentation.face(
            for: task,
            items: sampleItems(),
            showsPronunciation: session.showsPronunciation,
            voiceOver: false,
            answered: true
        )
        #expect(face.prompt.pronunciation == nil)
        #expect(face.options.allSatisfy { $0.pronunciation == nil })
    }
}

private func courseSession(showsPronunciation: Bool, voiceOver: Bool = false) -> LessonSession {
    let items = sampleItems()
    let lesson = policyLesson("l-letters", words: sampleWords(), letters: sampleLetters())
    let bundle = policyBundle(
        units: [policyUnit("u-letters", lessons: [lesson])],
        items: items
    )
    return policySession(
        bundle,
        lesson: "l-letters",
        seen: ["l-letters"],
        released: ["u-letters"],
        showsPronunciation: showsPronunciation,
        voiceOver: voiceOver
    )
}

private func sampleWords() -> [ContentItem] {
    [
        policyWord("e-dar", "در", "dar", "door", translit: "dar-scholar"),
        policyWord("e-tab", "تب", "tab", "fever", translit: "tab-scholar"),
        policyWord("e-bar", "بر", "bar", "on", translit: "bar-scholar"),
        policyWord("e-aab", "آب", "aab", "water", translit: "ab-scholar"),
    ]
}

private func sampleLetters() -> [ContentItem] {
    [
        policyLetter("e-dal", "د", pronunciation: "da", translit: "dal-scholar", name: "دال", sound: "d"),
        policyLetter("e-ddal", "ډ", pronunciation: "da", translit: "ddal-scholar", name: "ډال", sound: "ḍ"),
        policyLetter("e-te", "ت", pronunciation: "ta", translit: "te-scholar", name: "تې", sound: "t"),
        policyLetter("e-be", "ب", pronunciation: "ba", translit: "be-scholar", name: "بې", sound: "b"),
    ]
}

private func sampleItems() -> [ContentItem] {
    sampleWords() + sampleLetters()
}

private func choiceTasks(in session: LessonSession, kind: TaskKind) -> [QuizTask] {
    session.tasks.compactMap { task in
        guard case .choice(let quiz) = task.payload, quiz.kind == kind else { return nil }
        return quiz
    }
}

private func taskUsesUnreleasedItem(_ task: SessionTask) -> Bool {
    let hidden: Set<String> = ["e-hidden-a", "e-hidden-b"]
    switch task.payload {
    case .choice(let quiz):
        if hidden.contains(quiz.targetID.rawValue) || hidden.contains(quiz.promptItemID?.rawValue ?? "") {
            return true
        }
        return quiz.options.contains { hidden.contains($0.itemID.rawValue) }
    case .matchPairs(let match):
        return match.pairs.contains { hidden.contains($0.left.itemID.rawValue) || hidden.contains($0.right.itemID.rawValue) }
    case .orderWords(let order):
        return hidden.contains(order.targetID.rawValue)
    }
}

private func policySession(
    _ bundle: ContentBundle,
    lesson: String,
    seen: [String],
    released: [String]?,
    showsPronunciation: Bool = true,
    voiceOver: Bool = false
) -> LessonSession {
    var rng = PolicyRNG(seed: 1)
    return LessonSessionBuilder.build(
        for: lessonID(lesson),
        in: bundle,
        seenLessonIDs: seen.map(lessonID),
        maxQuestions: nil,
        releasedUnitIDs: released?.map(unitID),
        showsPronunciation: showsPronunciation,
        voiceOver: voiceOver,
        using: &rng
    )
}

private func policyWord(
    _ id: String,
    _ pashto: String,
    _ pronunciation: String,
    _ en: String,
    translit: String? = nil
) -> ContentItem {
    makeItem(id, pashto: pashto, translit: translit ?? pronunciation, pronunciation: pronunciation, en: en)
}

private func policyLetter(
    _ id: String,
    _ pashto: String,
    pronunciation: String,
    translit: String,
    name: String,
    sound: String
) -> ContentItem {
    makeItem(
        id,
        kind: .letter,
        pashto: pashto,
        translit: translit,
        pronunciation: pronunciation,
        en: "the letter \(sound)",
        name: name,
        forms: LetterForms(isolated: pashto, initial: pashto, medial: pashto, final: pashto),
        sound: sound
    )
}

private func policyLesson(_ id: String, words: [ContentItem], letters: [ContentItem] = []) -> Lesson {
    Lesson(
        id: lessonID(id),
        title: id,
        items: words.map { LessonItemRef(item: $0.id, role: .introduce) },
        letters: letters.map(\.id)
    )
}

private func policyUnit(_ id: String, lessons: [Lesson]) -> CourseUnit {
    CourseUnit(id: unitID(id), track: "main", title: id, lessons: lessons)
}

private func policyBundle(units: [CourseUnit], items: [ContentItem]) -> ContentBundle {
    makeBundle(items: items, units: units)
}

private struct PolicyRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
