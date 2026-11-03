import Foundation
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

    @Test func aLessonWithNoQuestionsIsLeftOffTheHome() {
        let examples = [
            word("e-alef", "ا", "alef"),
            word("e-be", "ب", "be"),
        ]
        let introduced = [
            word("e-door", "در", "door"),
            word("e-fever", "تب", "fever"),
            word("e-on", "بر", "on"),
            word("e-water", "اوبه", "water"),
        ]
        let sounds = Lesson(
            id: lessonID("l-sounds-1"),
            title: "New sounds",
            items: examples.map { LessonItemRef(item: $0.id, role: .soundExample, sound: "a") }
        )
        let home = lesson("l-home", title: "Home lesson", items: introduced)
        let bundle = makeBundle(
            items: examples + introduced,
            units: [
                CourseUnit(id: unitID("u-sounds"), track: "main", title: "Sounds", lessons: [sounds]),
                CourseUnit(id: unitID("u-home"), track: "main", title: "Home", lessons: [home]),
            ]
        )
        let offered = RootLessonSession.lessons(
            in: bundle,
            releasedUnitIDs: [unitID("u-sounds"), unitID("u-home")]
        )
        #expect(offered.map(\.id) == [lessonID("l-home")])
    }

    @Test func bundledCourseLessonsArePlayableOrHidden() throws {
        let bundle = try JSONDecoder().decode(ContentBundle.self, from: Data(contentsOf: bundledCourseURL()))
        let released = ["u-sounds", "u-greetings", "u-introductions", "u-family"].map(unitID)
        let settings = [(true, false), (true, true), (false, false), (false, true)]
        for (showsPronunciation, voiceOver) in settings {
            let offered = RootLessonSession.lessons(
                in: bundle,
                releasedUnitIDs: released,
                showsPronunciation: showsPronunciation,
                voiceOver: voiceOver
            )
            let offeredIDs = Set(offered.map(\.id))
            #expect(!offeredIDs.contains(lessonID("l-sounds-1")))
            var rng = SplitMix64(seed: 1)
            for unit in bundle.units where released.contains(unit.id) {
                for lesson in unit.lessons {
                    let session = LessonSessionBuilder.build(
                        for: lesson.id,
                        in: bundle,
                        seenLessonIDs: [],
                        releasedUnitIDs: released,
                        showsPronunciation: showsPronunciation,
                        voiceOver: voiceOver,
                        using: &rng
                    )
                    if session.tasks.isEmpty {
                        #expect(!offeredIDs.contains(lesson.id))
                    } else {
                        #expect(offeredIDs.contains(lesson.id))
                    }
                }
            }
        }
    }

    @Test func appTargetCopiesTheCourseAndTheReleaseList() throws {
        let root = repositoryRoot()
        let project = try String(contentsOf: root.appendingPathComponent("PashtoApp.xcodeproj/project.pbxproj"), encoding: .utf8)
        let resources = try #require(resourceBuildPhase(in: project) as String?)
        #expect(resources.contains("content.json in Resources"))
        #expect(resources.contains("release-units.json in Resources"))
        let spec = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        #expect(spec.contains("path: content/content.json"))
        #expect(spec.contains("path: content/release-units.json"))
        #expect(spec.contains("buildPhase: resources"))
        #expect(spec.contains("path: scripts/verify-bundled-course.sh"))
        #expect(spec.contains("name: Verify bundled course"))
        #expect(spec.contains("basedOnDependencyAnalysis: false"))
        #expect(spec.contains("ENABLE_USER_SCRIPT_SANDBOXING: YES"))
        #expect(spec.contains("$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/content.json"))
        #expect(spec.contains("$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/release-units.json"))
        #expect(spec.contains("$(DERIVED_FILE_DIR)/course-files-check.stamp"))
        #expect(project.contains("PBXShellScriptBuildPhase"))
        #expect(project.contains("Verify bundled course"))
        #expect(project.contains("alwaysOutOfDate = 1"))
        #expect(project.contains("$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/content.json"))
        #expect(project.contains("$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/release-units.json"))
        #expect(project.contains("$(DERIVED_FILE_DIR)/course-files-check.stamp"))
        #expect(project.contains("content.json"))
        #expect(project.contains("release-units.json"))
        #expect(project.contains("error:"))
        #expect(project.contains("ENABLE_USER_SCRIPT_SANDBOXING = YES"))
        #expect(!project.contains("ENABLE_USER_SCRIPT_SANDBOXING = NO"))
    }

    @Test func cachedLessonsStayPutUntilVoiceOverChanges() {
        let plain = makeItem(
            "e-da",
            kind: .letter,
            pashto: "د",
            translit: "da",
            pronunciation: "da",
            en: "da, plain",
            name: "da"
        )
        let ring = makeItem(
            "e-dda",
            kind: .letter,
            pashto: "ډ",
            translit: "dda",
            pronunciation: "dda",
            en: "da with a ring",
            name: "dda"
        )
        let lesson = Lesson(
            id: lessonID("l-letters"),
            title: "Letters",
            items: [],
            letters: [plain.id, ring.id]
        )
        let bundle = makeBundle(
            items: [plain, ring],
            units: [
                CourseUnit(id: unitID("u-sounds"), track: "main", title: "Sounds", lessons: [lesson]),
            ]
        )
        let released = [unitID("u-sounds")]

        var cache = ReleasedLessonCache()
        cache.refresh(
            course: bundle,
            releasedUnitIDs: released,
            showsPronunciation: true,
            voiceOver: false
        )
        #expect(cache.lessons.map(\.id) == [lessonID("l-letters")])
        #expect(cache.rebuildCount == 1)

        cache.refresh(
            course: bundle,
            releasedUnitIDs: released,
            showsPronunciation: true,
            voiceOver: false
        )
        #expect(cache.rebuildCount == 1)
        #expect(cache.lessons.map(\.id) == [lessonID("l-letters")])

        cache.refresh(
            course: bundle,
            releasedUnitIDs: released,
            showsPronunciation: true,
            voiceOver: true
        )
        #expect(cache.lessons.isEmpty)
        #expect(cache.rebuildCount == 2)

        cache.refresh(course: nil, releasedUnitIDs: [], voiceOver: true)
        #expect(cache.lessons.isEmpty)
        #expect(cache.rebuildCount == 3)
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

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func bundledCourseURL() -> URL {
    repositoryRoot().appendingPathComponent("content").appendingPathComponent("content.json")
}

private func resourceBuildPhase(in project: String) -> String? {
    guard
        let start = project.range(of: "/* Begin PBXResourcesBuildPhase section */"),
        let end = project.range(of: "/* End PBXResourcesBuildPhase section */")
    else { return nil }
    return String(project[start.lowerBound..<end.lowerBound])
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
