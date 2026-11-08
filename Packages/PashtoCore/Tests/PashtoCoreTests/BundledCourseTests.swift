import Foundation
import Testing
@testable import PashtoCore

struct BundledCourseTests {
    @Test func installedContentVersionIsTheVersionInContentJson() throws {
        let content = try Data(contentsOf: courseFile("content.json"))
        let release = try Data(contentsOf: courseFile("release-units.json"))
        let loaded = BundledCourseLoader.load(content: content, releaseUnits: release)
        guard case .ready(let course) = loaded else {
            Issue.record("The bundled course did not decode")
            return
        }
        let decoded = try JSONDecoder().decode(ContentBundle.self, from: content)
        #expect(course.installedContentVersion == decoded.contentVersion)
        #expect(!course.installedContentVersion.isEmpty)
        #expect(course.installedContentVersion != "unbundled")
        #expect(loaded.blockingScreen == nil)
        #expect(course.releasedUnitIDs == approvedReleaseUnitIDs)
    }

    @Test func theBundledReleaseListIsUnitsZeroThroughThree() throws {
        guard case .ready(let course) = try loadBundledCourse() else {
            Issue.record("The bundled course did not decode")
            return
        }
        let inCourseOrder = course.bundle.units.map(\.id).filter { approvedReleaseUnitIDs.contains($0) }
        #expect(course.releasedUnitIDs == approvedReleaseUnitIDs)
        #expect(course.releasedUnitIDs == inCourseOrder)

        var rng = SplitMix64(seed: 8)
        let placement = PlacementTestBuilder.build(
            in: course.bundle,
            releasedUnitIDs: course.releasedUnitIDs,
            using: &rng
        )
        #expect(placement.unitIDs.map(\.rawValue) == ["u-greetings", "u-introductions", "u-family"])
        #expect(!placement.unitIDs.contains(unitID("u-sounds")))

        let lessons = RootLessonSession.lessons(
            in: course.bundle,
            releasedUnitIDs: course.releasedUnitIDs
        )
        #expect(!lessons.isEmpty)
        #expect(lessons.allSatisfy { course.releasedUnitIDs.contains($0.unitID) })
        #expect(!lessons.contains { $0.id == lessonID("l-sounds-1") })

        let future = [
            "u-numbers", "u-food", "u-daily-life", "u-town", "u-conversation",
        ].map(unitID)
        #expect(course.bundle.units.map(\.id) == [unitID("u-sounds")] + course.releasedUnitIDs + future)
        let futureLessons = course.bundle.units.filter { future.contains($0.id) }.flatMap(\.lessons)
        #expect(futureLessons.count == 17)
        #expect(Set(lessons.map(\.id)).isDisjoint(with: Set(futureLessons.map(\.id))))
        #expect(futureLessons.allSatisfy { $0.letters.isEmpty })

        let limited = ReleasedCourse.limiting(course.bundle, to: course.releasedUnitIDs)
        let futureIntroduced = Set(futureLessons.flatMap { lesson in
            lesson.items.filter { $0.role == .introduce }.map(\.item)
        })
        let releasedReferences = Set(limited.units.flatMap { unit in
            unit.lessons.flatMap { lesson in
                lesson.items.map(\.item)
                    + lesson.letters
                    + lesson.dialogs.flatMap { $0.turns.map(\.item) }
            }
        })
        let hiddenFromRelease = futureIntroduced.subtracting(releasedReferences)
        #expect(hiddenFromRelease == futureIntroduced)
        #expect(limited.items.allSatisfy { !hiddenFromRelease.contains($0.id) })

        let day = LocalDay(year: 2026, month: 11, day: 8)
        let cards = futureIntroduced.map { ReviewCard.introduced(itemID: $0, on: day) }
        for offset in 0..<40 {
            let word = DailyWordSelection.select(
                cards: cards,
                in: course.bundle,
                releasedUnitIDs: course.releasedUnitIDs,
                on: LocalDay(year: 2026, month: 11, day: 1 + (offset % 28)),
                showsPronunciation: true
            )
            if let word {
                #expect(!hiddenFromRelease.contains(word.itemID))
                #expect(releasedReferences.contains(word.itemID))
            }
        }

        var quiz = RootLessonSession()
        for lesson in lessons {
            var rng = SplitMix64(seed: 3)
            quiz.start(
                lessonID: lesson.id,
                in: course.bundle,
                releasedUnitIDs: course.releasedUnitIDs,
                using: &rng
            )
            #expect(quiz.items.allSatisfy { !hiddenFromRelease.contains($0.id) })
        }
    }

    @Test func placementAndReleasedLessonsUseTheReleaseList() {
        let course = bundleWithAnUnreleasedUnit()
        let released = approvedReleaseUnitIDs
        let fromList = ReleasedCourse.limiting(course.bundle, to: released)
        #expect(fromList.units.map(\.id) == released)
        #expect(course.bundle.units.contains { $0.id == unitID("u-hidden") })
        #expect(!fromList.units.contains { $0.id == unitID("u-hidden") })
        #expect(fromList.items.allSatisfy { !$0.id.rawValue.hasPrefix("e-hidden-") })

        var listedPlacement = SplitMix64(seed: 4)
        let placement = PlacementTestBuilder.build(
            in: course.bundle,
            releasedUnitIDs: released,
            using: &listedPlacement
        )
        #expect(placement.unitIDs.map(\.rawValue) == ["u-greetings"])
        #expect(!placement.unitIDs.contains(unitID("u-hidden")))

        var bundlePlacement = SplitMix64(seed: 4)
        let fromWholeBundle = PlacementTestBuilder.build(
            in: course.bundle,
            releasedUnitIDs: course.bundle.units.map(\.id),
            using: &bundlePlacement
        )
        #expect(fromWholeBundle.unitIDs.map(\.rawValue) == ["u-greetings", "u-hidden", "u-introductions"])

        let lessons = RootLessonSession.lessons(in: course.bundle, releasedUnitIDs: released)
        #expect(lessons.map(\.id) == [
            lessonID("l-greetings-1"),
            lessonID("l-introductions-1"),
            lessonID("l-family-1"),
        ])
        let everyUnit = RootLessonSession.lessons(
            in: course.bundle,
            releasedUnitIDs: course.bundle.units.map(\.id)
        )
        #expect(everyUnit.contains { $0.id == course.hiddenLesson })

        var wholeBundle = SplitMix64(seed: 4)
        let quizzedFromBundle = LessonSessionBuilder.build(
            for: course.hiddenLesson,
            in: course.bundle,
            seenLessonIDs: [],
            releasedUnitIDs: nil,
            using: &wholeBundle
        )
        var heldToList = SplitMix64(seed: 4)
        let quizzedFromList = LessonSessionBuilder.build(
            for: course.hiddenLesson,
            in: course.bundle,
            seenLessonIDs: [],
            releasedUnitIDs: released,
            using: &heldToList
        )
        #expect(!quizzedFromBundle.tasks.isEmpty)
        #expect(quizzedFromList.tasks.isEmpty)
    }

    @Test func missingOrUndecodableFilesUseTheStorageError() throws {
        let content = try JSONEncoder().encode(sampleBundle())
        let release = Data(#"{"units":[],"note":"An empty list is allowed."}"#.utf8)
        let loaded = BundledCourseLoader.load(content: content, releaseUnits: release)
        guard case .ready(let course) = loaded else {
            Issue.record("A decoded course should load")
            return
        }
        #expect(course.installedContentVersion == "test")
        #expect(loaded.blockingScreen == nil)

        let cases: [(Data?, Data?)] = [
            (nil, release),
            (content, nil),
            (nil, nil),
            (Data("[]".utf8), release),
            (Data(#"{"schemaVersion":99}"#.utf8), release),
            (content, Data("[]".utf8)),
            (content, Data(#"{"note":"no units key"}"#.utf8)),
            (content, Data(#"{"units":"u-sounds"}"#.utf8)),
        ]
        for pair in cases {
            let failed = BundledCourseLoader.load(content: pair.0, releaseUnits: pair.1)
            #expect(failed == .unavailable)
            #expect(failed.blockingScreen == .storageError)
        }
    }

    @Test func aDecodedReleaseListDropsIdsThatAreNotUnits() throws {
        let content = try JSONEncoder().encode(sampleBundle())
        let release = Data(#"{"units":["nope","u-sounds","also-bad"],"note":"authors","extra":true}"#.utf8)
        let loaded = BundledCourseLoader.load(content: content, releaseUnits: release)
        guard case .ready(let course) = loaded else {
            Issue.record("A release list with a note should decode")
            return
        }
        #expect(course.releasedUnitIDs == [unitID("u-sounds")])
        #expect(loaded.blockingScreen == nil)
    }

    @Test func buildCheckFailsWhenACourseFileIsMissingFromTheApp() throws {
        let script = repositoryRoot().appendingPathComponent("scripts/verify-bundled-course.sh")
        let source = try String(contentsOf: script, encoding: .utf8)
        #expect(source.contains(BundledCourseLoader.contentFileName))
        #expect(source.contains(BundledCourseLoader.releaseUnitsFileName))
        #expect(source.contains("UNLOCALIZED_RESOURCES_FOLDER_PATH"))
        #expect(source.contains("course-files-check.stamp"))
        #expect(source.contains("error:"))

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pashto-bundle-check-\(UUID().uuidString)", isDirectory: true)
        let app = root.appendingPathComponent("PashtoApp.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bothMissing = try runBundleCheck(script: script, app: app)
        #expect(bothMissing.status != 0)
        #expect(bothMissing.output.contains("error: content.json is missing"))
        #expect(bothMissing.output.contains("error: release-units.json is missing"))
        #expect(!FileManager.default.fileExists(atPath: bothMissing.stamp.path))

        try Data("{}".utf8).write(to: app.appendingPathComponent("release-units.json"))
        let contentMissing = try runBundleCheck(script: script, app: app)
        #expect(contentMissing.status != 0)
        #expect(contentMissing.output.contains("error: content.json is missing"))
        #expect(!contentMissing.output.contains("release-units.json is missing"))
        #expect(!FileManager.default.fileExists(atPath: contentMissing.stamp.path))

        try Data("{}".utf8).write(to: app.appendingPathComponent("content.json"))
        let present = try runBundleCheck(script: script, app: app)
        #expect(present.status == 0)
        #expect(present.output.isEmpty)
        #expect(FileManager.default.fileExists(atPath: present.stamp.path))
    }
}

private let approvedReleaseUnitIDs = [
    "u-greetings",
    "u-introductions",
    "u-family",
].map(unitID)

private func loadBundledCourse() throws -> BundledCourseLoad {
    let content = try Data(contentsOf: courseFile("content.json"))
    let release = try Data(contentsOf: courseFile("release-units.json"))
    return BundledCourseLoader.load(content: content, releaseUnits: release)
}

private struct UnreleasedUnitCourse {
    var bundle: ContentBundle
    var hiddenLesson: LessonID
}

/// Approved units, plus `u-hidden` inside the placement window.
private func bundleWithAnUnreleasedUnit() -> UnreleasedUnitCourse {
    let sound = makeItem("e-sound-a", pashto: "ا", translit: "a", pronunciation: "a", en: "alef")
    let sounds = Lesson(
        id: lessonID("l-sounds-1"),
        title: "Sounds",
        items: [LessonItemRef(item: sound.id, role: .soundExample, sound: "a")]
    )
    let greetings = numberedWords("e-greet", 1...6)
    let hidden = numberedWords("e-hidden", 1...6)
    let introductions = numberedWords("e-intro", 1...6)
    let family = numberedWords("e-family", 1...6)
    let hiddenLesson = introducedLesson("l-hidden-1", items: hidden)
    let bundle = makeBundle(
        items: [sound] + greetings + hidden + introductions + family,
        units: [
            CourseUnit(id: unitID("u-sounds"), track: "main", title: "Sounds", lessons: [sounds]),
            CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [introducedLesson("l-greetings-1", items: greetings)]),
            CourseUnit(id: unitID("u-hidden"), track: "main", title: "Hidden", lessons: [hiddenLesson]),
            CourseUnit(id: unitID("u-introductions"), track: "main", title: "Introductions", lessons: [introducedLesson("l-introductions-1", items: introductions)]),
            CourseUnit(id: unitID("u-family"), track: "main", title: "Family", lessons: [introducedLesson("l-family-1", items: family)]),
        ]
    )
    return UnreleasedUnitCourse(bundle: bundle, hiddenLesson: hiddenLesson.id)
}

private func numberedWords(_ prefix: String, _ range: ClosedRange<Int>) -> [ContentItem] {
    range.map { number in
        makeItem(
            "\(prefix)-\(number)",
            pashto: "\(prefix)\(number)",
            translit: "\(prefix)\(number)",
            pronunciation: "\(prefix)\(number)",
            en: "\(prefix) \(number)"
        )
    }
}

private func introducedLesson(_ id: String, items: [ContentItem]) -> Lesson {
    Lesson(
        id: lessonID(id),
        title: id,
        items: items.map { LessonItemRef(item: $0.id, role: .introduce) }
    )
}

private func sampleBundle() -> ContentBundle {
    makeBundle(
        items: [makeItem()],
        units: [
            CourseUnit(
                id: unitID("u-sounds"),
                track: "main",
                title: "Sounds",
                lessons: [Lesson(id: lessonID("l-sounds-1"), title: "Sounds", items: [])]
            ),
        ]
    )
}

private func courseFile(_ name: String) -> URL {
    repositoryRoot().appendingPathComponent("content").appendingPathComponent(name)
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func runBundleCheck(script: URL, app: URL) throws -> (status: Int32, output: String, stamp: URL) {
    let derived = app.deletingLastPathComponent().appendingPathComponent("Derived", isDirectory: true)
    try FileManager.default.createDirectory(at: derived, withIntermediateDirectories: true)
    let stamp = derived.appendingPathComponent("course-files-check.stamp")
    if FileManager.default.fileExists(atPath: stamp.path) {
        try FileManager.default.removeItem(at: stamp)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [script.path]
    var environment = ProcessInfo.processInfo.environment
    environment["TARGET_BUILD_DIR"] = app.deletingLastPathComponent().path
    environment["UNLOCALIZED_RESOURCES_FOLDER_PATH"] = app.lastPathComponent
    environment["DERIVED_FILE_DIR"] = derived.path
    process.environment = environment
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self), stamp)
}
