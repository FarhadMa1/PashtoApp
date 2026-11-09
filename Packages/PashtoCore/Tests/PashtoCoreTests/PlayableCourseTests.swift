import Foundation
import Testing
@testable import PashtoCore

struct PlayableCourseTests {
    @Test func unitsOneThroughThreeHideLettersAndKeepTheSource() throws {
        let course = try loadCourse()
        let source = course.bundle
        let letters = source.items.filter { $0.kind == .letter }
        #expect(letters.count == 20)
        #expect(source.units.contains { $0.id.rawValue == "u-sounds" })
        let sounds = try #require(source.units.first { $0.id.rawValue == "u-sounds" })
        #expect(sounds.lessons.contains { lesson in
            lesson.items.contains { $0.role == .soundExample }
        })

        let playable = PlayableCourse.hidingScript(source)
        #expect(playable.contentVersion == source.contentVersion)
        #expect(playable.units.map(\.id) == source.units.map(\.id))
        #expect(!playable.items.contains { $0.kind == .letter })
        for unit in playable.units where PlayableCourse.scriptHiddenUnitIDs.contains(unit.id.rawValue) {
            #expect(unit.lessons.allSatisfy { $0.letters.isEmpty })
            for lesson in unit.lessons {
                let cards = reviewCards(introducedIn: lesson, on: day)
                if lesson.countsForProgress {
                    #expect(!cards.isEmpty)
                    #expect(cards.allSatisfy { card in
                        playable.items.first { $0.id == card.itemID }?.kind != .letter
                    })
                } else {
                    #expect(cards.isEmpty)
                    #expect(lesson.dialogs.isEmpty)
                }
            }
        }
        let future = playable.units.filter { !PlayableCourse.scriptHiddenUnitIDs.contains($0.id.rawValue) && $0.id.rawValue != "u-sounds" }
        #expect(future.allSatisfy { $0.lessons.allSatisfy(\.letters.isEmpty) })
        #expect(PlayableCourse.hidingScript(playable) == playable)
    }

    @Test func releasedQuizzesPlacementAndSkipCardsLeaveLettersOut() throws {
        let course = try loadCourse()
        let released = course.releasedUnitIDs
        #expect(released.map(\.rawValue) == ["u-greetings", "u-introductions", "u-family"])
        var rng = SplitMix64(seed: 4)
        let placement = PlacementTestBuilder.build(in: course.bundle, releasedUnitIDs: released, using: &rng)
        #expect(placement.unitIDs.map(\.rawValue) == ["u-greetings", "u-introductions", "u-family"])
        for unit in placement.units {
            #expect(unit.tasks.count == 5)
            #expect(unit.tasks.allSatisfy { !PlayableCourse.retiredQuizKinds.contains($0.kind) })
            #expect(taskItemIDs(unit.tasks).allSatisfy { !isLetter($0, in: course.bundle) })
        }

        let skipped = placementCommit(
            scores: released.map {
                PlacementUnitScore(unitID: $0, correct: 5, questions: 5, skipped: true)
            },
            in: course.bundle,
            takenOn: day
        )
        #expect(skipped.cards.allSatisfy { !isLetter($0.itemID, in: course.bundle) })
        let known = Set(PlayableCourse.hidingScript(course.bundle).items.map(\.id))
        let letter = ReviewCard.introduced(itemID: itemID("e-letter-alif"), on: day)
        let word = ReviewCard.introduced(itemID: itemID("e-salam"), on: day)
        #expect(newItemsShown(on: day, in: [letter, word]) == 2)
        #expect(playableNewItemsShown(on: day, in: [letter, word], knownItemIDs: known) == 1)

        let lessons = RootLessonSession.lessons(in: course.bundle, releasedUnitIDs: released)
        #expect(lessons.map(\.id.rawValue).first == "l-greetings-learn")
        #expect(!lessons.contains { $0.id.rawValue == "l-sounds-1" })
        for lesson in lessons {
            for showsPronunciation in [true, false] {
                var generator = SplitMix64(seed: 9)
                let session = LessonSessionBuilder.build(
                    for: lesson.id,
                    in: course.bundle,
                    seenLessonIDs: lessons.map(\.id),
                    maxQuestions: nil,
                    releasedUnitIDs: released,
                    showsPronunciation: showsPronunciation,
                    using: &generator
                )
                if lesson.kind == .practice {
                    #expect(!session.tasks.isEmpty)
                    #expect(session.tasks.allSatisfy { !PlayableCourse.retiredQuizKinds.contains($0.kind) })
                    #expect(taskItemIDs(session.tasks).allSatisfy { !isLetter($0, in: course.bundle) })
                    try expectUniquePronunciations(session, in: course.bundle)
                } else {
                    #expect(session.tasks.isEmpty)
                }
            }
        }
    }

    @Test func approvedGhwaaRamStressIsTheStoredPronunciation() throws {
        let bundle = try loadCourse().bundle
        let sorry = try #require(bundle.items.first { $0.id.rawValue == "e-baxana-ghwaram" })
        #expect(sorry.pashto == "بښنه غواړم")
        #expect(sorry.pronunciation == "ba-KHA-na ghwaa-RAM")
        #expect(sorry.translit == "bax̌ə́na ɣwā́ṛəm")
        #expect(sorry.en == "sorry, excuse me")
        let verb = try #require(bundle.items.first { $0.id.rawValue == "e-ghwaa-ram" })
        #expect(verb.pashto == "غواړم")
        #expect(verb.pronunciation == "ghwaa-RAM")
        let phrases = bundle.items.filter { $0.pronunciation.contains("ghwaa-RAM") || $0.pronunciation.contains("GHWAA") }
        #expect(!phrases.isEmpty)
        #expect(phrases.allSatisfy { !$0.pronunciation.contains("GHWAA") })
    }

    @Test func aSavedLetterOrPronunciationChoiceStartsOver() {
        let letter = LessonSession(
            lessonID: lessonID("l-greetings-1"),
            tasks: [SessionTask(payload: .choice(QuizTask(
                kind: .findLetter,
                targetID: itemID("e-letter-alif"),
                prompt: "alif",
                usage: nil,
                options: [QuizOption(itemID: itemID("e-letter-alif"), text: "ا")]
            )))]
        )
        let choice = LessonSession(
            lessonID: lessonID("l-greetings-1"),
            showsPronunciation: false,
            tasks: [SessionTask(payload: .choice(QuizTask(
                kind: .transliterationChoice,
                targetID: itemID("e-salam"),
                prompt: "سلام",
                usage: nil,
                options: [QuizOption(itemID: itemID("e-salam"), text: "sa-LAAM")]
            )))]
        )
        let meaning = LessonSession(
            lessonID: lessonID("l-greetings-1"),
            showsPronunciation: false,
            tasks: [SessionTask(payload: .choice(QuizTask(
                kind: .meaningPashtoToEnglish,
                targetID: itemID("e-salam"),
                prompt: "سلام",
                usage: nil,
                options: [QuizOption(itemID: itemID("e-salam"), text: "hello")]
            )))]
        )
        #expect(resumeContainsUnplayableTask(letter))
        #expect(resumeContainsUnplayableTask(choice))
        #expect(!resumeContainsUnplayableTask(meaning))
        #expect(meaning.showsPronunciation == false)
    }

    private func expectUniquePronunciations(_ session: LessonSession, in bundle: ContentBundle) throws {
        var byID: [ItemID: ContentItem] = [:]
        for item in bundle.items where byID[item.id] == nil {
            byID[item.id] = item
        }
        for task in session.tasks {
            guard case .choice(let quiz) = task.payload, quiz.kind == .meaningEnglishToPashto else { continue }
            var seen: [String] = []
            for option in quiz.options {
                let item = try #require(byID[option.itemID])
                let spoken = item.pronunciation
                #expect(!seen.contains(spoken))
                seen.append(spoken)
                let face = QuizPresentation.face(
                    for: quiz,
                    items: Array(byID.values),
                    showsPronunciation: false,
                    voiceOver: false,
                    answered: false
                )
                let drawn = try #require(face.options.first { $0.itemID == option.itemID })
                #expect(drawn.pronunciation == spoken)
            }
            #expect(QuizPresentation.sentencePronunciation(
                item: byID[quiz.targetID],
                showsPronunciation: true,
                answered: false
            ) == nil)
        }
    }
}

private let day = LocalDay(year: 2026, month: 11, day: 8)

private func loadCourse() throws -> BundledCourse {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let content = try Data(contentsOf: root.appendingPathComponent("content/content.json"))
    let release = try Data(contentsOf: root.appendingPathComponent("content/release-units.json"))
    guard case .ready(let course) = BundledCourseLoader.load(content: content, releaseUnits: release) else {
        Issue.record("The bundled course did not decode")
        throw PlayableCourseTestError.unavailable
    }
    return course
}

private func isLetter(_ id: ItemID, in bundle: ContentBundle) -> Bool {
    bundle.items.first { $0.id == id }?.kind == .letter
}

private func taskItemIDs(_ tasks: [SessionTask]) -> [ItemID] {
    tasks.flatMap { task -> [ItemID] in
        switch task.payload {
        case .choice(let quiz):
            return [quiz.targetID, quiz.promptItemID].compactMap { $0 } + quiz.options.map(\.itemID)
        case .matchPairs(let match):
            return match.pairs.flatMap { [$0.left.itemID, $0.right.itemID] }
        case .orderWords(let order):
            return [order.targetID]
        }
    }
}

private enum PlayableCourseTestError: Error {
    case unavailable
}
