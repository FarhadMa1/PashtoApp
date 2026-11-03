import Testing
@testable import PashtoCore

struct RootLessonSessionTests {
    @Test func startingALessonFromTheRootUsesReleasedUnitsOnly() {
        let course = sampleCourse()
        let released = [unitID("u-home")]
        let offered = RootLessonSession.lessons(in: course.bundle, releasedUnitIDs: released)
        #expect(offered.map(\.id) == [lessonID("l-home")])
        #expect(offered.map(\.title) == ["Home lesson"])
        #expect(!offered.contains { $0.unitID == unitID("u-early") })

        var launch = RootLessonSession()
        var rng = SplitMix64(seed: 1)
        let session = launch.start(
            lessonID: lessonID("l-home"),
            in: course.bundle,
            seenLessonIDs: [lessonID("l-early"), lessonID("l-home")],
            releasedUnitIDs: released,
            showsPronunciation: true,
            using: &rng
        )

        #expect(launch.isActive)
        #expect(session.lessonID == lessonID("l-home"))
        #expect(!session.tasks.isEmpty)
        let allowed = Set(course.homeItems.map(\.id))
        #expect(itemIDs(in: session).isSubset(of: allowed))
        #expect(itemIDs(in: session).isDisjoint(with: Set(course.earlyItems.map(\.id))))
        #expect(launch.items.map(\.id).allSatisfy { allowed.contains($0) })

        var blocked = RootLessonSession()
        var blockedRNG = SplitMix64(seed: 1)
        blocked.start(
            lessonID: lessonID("l-early"),
            in: course.bundle,
            seenLessonIDs: [lessonID("l-early")],
            releasedUnitIDs: released,
            using: &blockedRNG
        )
        #expect(!blocked.isActive)
        #expect(blocked.session == nil)
        #expect(blocked.items.isEmpty)
    }

    @Test func returningEndsTheSession() {
        let course = sampleCourse()
        var launch = RootLessonSession()
        var rng = SplitMix64(seed: 4)
        launch.start(
            lessonID: lessonID("l-home"),
            in: course.bundle,
            releasedUnitIDs: [unitID("u-home")],
            using: &rng
        )
        #expect(launch.isActive)

        launch.end()
        #expect(launch.session == nil)
        #expect(!launch.isActive)
        #expect(launch.items.isEmpty)
    }

    @Test func anEmptyReleaseListStartsNothing() {
        let course = sampleCourse()
        #expect(RootLessonSession.lessons(in: course.bundle, releasedUnitIDs: []).isEmpty)

        var launch = RootLessonSession()
        var rng = SplitMix64(seed: 9)
        let session = launch.start(
            lessonID: lessonID("l-home"),
            in: course.bundle,
            seenLessonIDs: [lessonID("l-home")],
            releasedUnitIDs: [],
            using: &rng
        )
        #expect(session.tasks.isEmpty)
        #expect(!launch.isActive)
        #expect(launch.session == nil)
    }

    @Test func releasedLessonsKeepCourseOrderAndSkipUnlistedUnits() {
        let course = sampleCourse()
        let offered = RootLessonSession.lessons(
            in: course.bundle,
            releasedUnitIDs: [unitID("u-later"), unitID("u-home")]
        )
        #expect(offered.map(\.id) == [lessonID("l-home"), lessonID("l-later")])
        #expect(offered.map(\.unitID) == [unitID("u-home"), unitID("u-later")])
    }
}

private struct SampleCourse {
    var bundle: ContentBundle
    var homeItems: [ContentItem]
    var earlyItems: [ContentItem]
}

private func sampleCourse() -> SampleCourse {
    let earlyItems = [
        word("e-cat", "پيشو", "cat"),
        word("e-dog", "سپی", "dog"),
        word("e-bird", "مرغه", "bird"),
    ]
    let homeItems = [
        word("e-door", "در", "door"),
        word("e-fever", "تب", "fever"),
        word("e-on", "بر", "on"),
        word("e-water", "اوبه", "water"),
    ]
    let laterItems = [
        word("e-book", "کتاب", "book"),
        word("e-pen", "قلم", "pen"),
        word("e-house", "کور", "house"),
    ]
    let early = lesson("l-early", title: "Early lesson", items: earlyItems)
    let home = lesson("l-home", title: "Home lesson", items: homeItems)
    let later = lesson("l-later", title: "Later lesson", items: laterItems)
    let bundle = makeBundle(
        items: earlyItems + homeItems + laterItems,
        units: [
            CourseUnit(id: unitID("u-early"), track: "main", title: "Early", lessons: [early]),
            CourseUnit(id: unitID("u-home"), track: "main", title: "Home", lessons: [home]),
            CourseUnit(id: unitID("u-later"), track: "main", title: "Later", lessons: [later]),
        ]
    )
    return SampleCourse(bundle: bundle, homeItems: homeItems, earlyItems: earlyItems)
}

private func lesson(_ id: String, title: String, items: [ContentItem]) -> Lesson {
    Lesson(
        id: lessonID(id),
        title: title,
        items: items.map { LessonItemRef(item: $0.id, role: .introduce) }
    )
}

private func word(_ id: String, _ pashto: String, _ en: String) -> ContentItem {
    makeItem(id, pashto: pashto, translit: en, pronunciation: en, en: en)
}

private func itemIDs(in session: LessonSession) -> Set<ItemID> {
    var ids = Set<ItemID>()
    for task in session.tasks {
        switch task.payload {
        case .choice(let quiz):
            ids.insert(quiz.targetID)
            if let prompt = quiz.promptItemID {
                ids.insert(prompt)
            }
            for option in quiz.options {
                ids.insert(option.itemID)
            }
        case .matchPairs(let match):
            for pair in match.pairs {
                ids.insert(pair.left.itemID)
                ids.insert(pair.right.itemID)
            }
        case .orderWords(let order):
            ids.insert(order.targetID)
        }
    }
    return ids
}
