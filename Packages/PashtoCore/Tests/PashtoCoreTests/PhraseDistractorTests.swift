import Foundation
import Testing
@testable import PashtoCore

/// Released practice lessons after Greetings keep a word with words and a phrase with phrases.
///
/// The release list is `release-units.json`, not every unit in the bundle.
/// Greetings stays on the mixed pool from main `1ad227c`. `u-basics` stays out
/// of every other unit's wrong answers. A question whose same-shape pool is
/// still under three after earlier released units is skipped.
struct PhraseDistractorTests {
    /// Practice-lesson sizes, seed 1, lessons seen through that lesson, cap 20.
    /// These are the counts on main `1ad227c`.
    private static let questionCounts: [String: Int] = [
        "l-basics-1": 20,
        "l-greetings-1": 11,
        "l-greetings-2": 17,
        "l-greetings-3": 15,
        "l-introductions-1": 20,
        "l-introductions-2": 20,
        "l-introductions-3": 11,
        "l-family-1": 20,
        "l-family-2": 13,
        "l-family-3": 20,
        "l-travel-1": 17,
        "l-travel-2": 17,
        "l-time-1": 20,
        "l-time-2": 20,
        "l-numbers-1": 20,
        "l-numbers-2": 20,
        "l-numbers-3": 11,
        "l-food-1": 17,
        "l-food-2": 20,
        "l-town-1": 19,
        "l-town-2": 19,
        "l-conversation-1": 15,
        "l-conversation-2": 17,
        "l-conversation-3": 9,
    ]

    @Test func releasedPracticeLessonsMatchMainAndSplitAfterGreetings() throws {
        let course = try loadReleasedCourseForDistractors()
        let released = course.releasedUnitIDs
        let travelIndex = try #require(released.firstIndex { $0.rawValue == "u-travel" })
        let beforeTravel = Set(released.prefix(travelIndex).map(\.rawValue))
        let limited = ReleasedCourse.limiting(course.bundle, to: released)
        var itemsByID: [ItemID: ContentItem] = [:]
        for item in limited.items where itemsByID[item.id] == nil {
            itemsByID[item.id] = item
        }
        let courseOrder = CourseOrder(limited)

        var seen: [LessonID] = []
        var practiceLessons = 0
        for unit in limited.units {
            for lesson in unit.lessons {
                seen.append(lesson.id)
                guard lesson.kind == .practice else { continue }
                practiceLessons += 1
                var rng = SplitMix64(seed: 1)
                let session = LessonSessionBuilder.build(
                    for: lesson.id,
                    in: course.bundle,
                    seenLessonIDs: seen,
                    releasedUnitIDs: released,
                    using: &rng
                )
                #expect(!session.tasks.isEmpty, "\(lesson.id.rawValue) became empty")
                #expect(session.tasks.count == Self.questionCounts[lesson.id.rawValue])

                let context = QuizContext(
                    bundle: limited,
                    seenLessonIDs: seen,
                    releasedUnitIDs: released
                )
                if unit.id.rawValue == "u-greetings" {
                    try expectGreetingsStaysOnTheMixedPool(
                        lesson: lesson,
                        session: session,
                        context: context,
                        itemsByID: itemsByID
                    )
                }
                if answerShapesAreSplit(unit.id, releasedUnitIDs: released) {
                    let missing = try expectSameShapeOrSkipped(
                        lesson: lesson,
                        context: context,
                        itemsByID: itemsByID
                    )
                    if beforeTravel.contains(unit.id.rawValue) {
                        #expect(missing.isEmpty, "\(unit.id.rawValue) skipped \(missing)")
                    }
                    try expectChoiceShapes(
                        session: session,
                        itemsByID: itemsByID
                    )
                }
                try expectNoBasicsLeak(
                    session: session,
                    lessonUnit: unit.id,
                    courseOrder: courseOrder,
                    itemsByID: itemsByID
                )
            }
        }
        #expect(practiceLessons == Self.questionCounts.count)
    }

    @Test func aShortPhrasePoolTakesEarlierReleasedUnitsAndNotBasics() throws {
        let course = try loadReleasedCourseForDistractors()
        let released = course.releasedUnitIDs
        let limited = ReleasedCourse.limiting(course.bundle, to: released)
        var seen: [LessonID] = []
        for unit in limited.units {
            for lesson in unit.lessons {
                seen.append(lesson.id)
                if lesson.id.rawValue == "l-introductions-1" { break }
            }
            if seen.last?.rawValue == "l-introductions-1" { break }
        }
        let context = QuizContext(bundle: limited, seenLessonIDs: seen, releasedUnitIDs: released)
        let order = CourseOrder(limited)
        let phrase = try #require(order.itemsByID[itemID("e-zma-num-ahmad-day")])
        #expect(DialogResponse.replyShape(of: phrase) == .phrase)
        let candidates = Distractors.candidates(for: phrase, in: context)
        let inUnit = candidates.filter { $0.source != .earlierUnit }
        #expect(inUnit.count < 3)
        #expect(candidates.count >= 3)
        #expect(candidates.contains { $0.source == .earlierUnit })
        for candidate in candidates {
            let item = try #require(order.itemsByID[candidate.itemID])
            #expect(DialogResponse.replyShape(of: item) == .phrase)
            #expect(order.introduction(of: candidate.itemID)?.unitID.rawValue != "u-basics")
        }
    }

    @Test func basicsItemsAreNotDistractorsForLaterReleasedUnits() throws {
        let course = try loadReleasedCourseForDistractors()
        let released = course.releasedUnitIDs
        let limited = ReleasedCourse.limiting(course.bundle, to: released)
        let seen = limited.units.flatMap(\.lessons).map(\.id)
        let context = QuizContext(
            bundle: limited,
            seenLessonIDs: seen,
            releasedUnitIDs: released
        )
        let courseOrder = CourseOrder(limited)
        for introduction in courseOrder.introductions where introduction.unitID.rawValue != "u-basics" {
            guard let item = courseOrder.itemsByID[introduction.itemID] else { continue }
            let candidates = Distractors.candidates(for: item, in: context)
            for candidate in candidates {
                let source = courseOrder.introduction(of: candidate.itemID)
                #expect(source?.unitID.rawValue != "u-basics")
            }
        }
    }
}

private func expectGreetingsStaysOnTheMixedPool(
    lesson: Lesson,
    session: LessonSession,
    context: QuizContext,
    itemsByID: [ItemID: ContentItem]
) throws {
    let introduced = Distractors.introducedItems(in: lesson.id, bundle: context.bundle)
        .filter { $0.kind != .letter }
    let shapes = Set(introduced.map { DialogResponse.replyShape(of: $0) })
    if shapes.count > 1 {
        var mixed = false
        for task in session.tasks {
            guard case .choice(let quiz) = task.payload else { continue }
            let optionShapes = Set(quiz.options.compactMap { itemsByID[$0.itemID] }.map { DialogResponse.replyShape(of: $0) })
            if optionShapes.count > 1 { mixed = true }
        }
        #expect(mixed, "\(lesson.id.rawValue) no longer mixes a word and a phrase")
    }
    for item in introduced {
        let pool = Distractors.candidates(for: item, in: context)
        guard pool.count >= 2 else { continue }
        var rng = SplitMix64(seed: 1)
        let pashto = PashtoToEnglishChoice().makeTask(for: item, in: context, using: &rng)
        var englishRNG = SplitMix64(seed: 2)
        let english = EnglishToPashtoChoice().makeTask(for: item, in: context, using: &englishRNG)
        #expect(pashto != nil || english != nil, "\(item.id.rawValue) was skipped in \(lesson.id.rawValue)")
    }
}

private func expectSameShapeOrSkipped(
    lesson: Lesson,
    context: QuizContext,
    itemsByID: [ItemID: ContentItem]
) throws -> [String] {
    let introduced = Distractors.introducedItems(in: lesson.id, bundle: context.bundle)
    var skipped: [String] = []
    for item in introduced where item.kind != .letter {
        let pool = Distractors.candidates(for: item, in: context)
        var rng = SplitMix64(seed: 1)
        let pashto = PashtoToEnglishChoice().makeTask(for: item, in: context, using: &rng)
        var englishRNG = SplitMix64(seed: 2)
        let english = EnglishToPashtoChoice().makeTask(for: item, in: context, using: &englishRNG)
        if pool.count < 3 {
            #expect(pashto == nil, "\(item.id.rawValue) in \(lesson.id.rawValue) has \(pool.count) same-shape distractors")
            #expect(english == nil, "\(item.id.rawValue) in \(lesson.id.rawValue) has \(pool.count) same-shape distractors")
            skipped.append(item.id.rawValue)
            continue
        }
        for task in [pashto, english].compactMap({ $0 }) {
            for option in task.options where option.itemID != item.id {
                let distractor = try #require(itemsByID[option.itemID])
                #expect(sameAnswerPool(distractor, item, splitByShape: true))
            }
        }
    }
    return skipped
}

private func expectChoiceShapes(
    session: LessonSession,
    itemsByID: [ItemID: ContentItem]
) throws {
    for task in session.tasks {
        switch task.payload {
        case .choice(let quiz):
            let target = try #require(itemsByID[quiz.targetID])
            for option in quiz.options where option.itemID != quiz.targetID {
                let distractor = try #require(itemsByID[option.itemID])
                #expect(sameAnswerPool(distractor, target, splitByShape: true))
            }
        case .matchPairs(let match) where match.mode == .pashtoEnglish:
            let ids = match.pairs.map(\.left.itemID)
            guard let first = ids.first, let anchor = itemsByID[first] else { continue }
            for id in ids.dropFirst() {
                let item = try #require(itemsByID[id])
                #expect(sameAnswerPool(item, anchor, splitByShape: true))
            }
        case .matchPairs, .orderWords:
            break
        }
    }
}

private func expectNoBasicsLeak(
    session: LessonSession,
    lessonUnit: UnitID,
    courseOrder: CourseOrder,
    itemsByID: [ItemID: ContentItem]
) throws {
    guard lessonUnit.rawValue != "u-basics" else { return }
    for task in session.tasks {
        for id in itemIDs(in: task) {
            if itemsByID[id] == nil { continue }
            let introduction = courseOrder.introduction(of: id)
            #expect(introduction?.unitID.rawValue != "u-basics")
        }
    }
}

private func itemIDs(in task: SessionTask) -> [ItemID] {
    switch task.payload {
    case .choice(let quiz):
        return quiz.options.map(\.itemID)
    case .orderWords(let order):
        return [order.targetID]
    case .matchPairs(let match):
        return match.pairs.flatMap { [$0.left.itemID, $0.right.itemID] }
    }
}

private func loadReleasedCourseForDistractors() throws -> BundledCourse {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let content = try Data(contentsOf: root.appendingPathComponent("content/content.json"))
    let release = try Data(contentsOf: root.appendingPathComponent("content/release-units.json"))
    guard case .ready(let course) = BundledCourseLoader.load(content: content, releaseUnits: release) else {
        throw PhraseDistractorLoadError.unavailable
    }
    return course
}

private enum PhraseDistractorLoadError: Error {
    case unavailable
}
