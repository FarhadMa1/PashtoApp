import Foundation
import PashtoCore
import Testing
@testable import PashtoContentTool

struct ReleaseGateTests {
    @Test func draftItemsInAReleaseUnitAreErrorsAndStayInTheBundle() {
        let bundle = sampleBundle(itemCount: 6)
        let before = bundle.items.count
        let issues = ReleaseGate.issues(
            in: bundle,
            releaseUnitIDs: ["u-greetings"],
            itemUnits: Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id.rawValue, "u-greetings") }),
            specialSounds: [],
            mode: .release
        )
        #expect(bundle.items.count == before)
        let drafts = issues.filter { $0.field == "verification.status" && $0.severity == .error }
        #expect(drafts.count == 6)
        #expect(drafts.allSatisfy { $0.message.contains("must be verified") })

        let dev = ReleaseGate.issues(
            in: bundle,
            releaseUnitIDs: ["u-greetings"],
            itemUnits: Dictionary(uniqueKeysWithValues: bundle.items.map { ($0.id.rawValue, "u-greetings") }),
            specialSounds: [],
            mode: .dev
        )
        #expect(dev.filter { $0.field == "verification.status" }.allSatisfy { $0.severity == .warning })
    }

    @Test func lessonSizeIsAnErrorBelowFourAndAWarningAtFourOrFive() {
        let three = ReleaseGate.issues(in: sampleBundle(itemCount: 3), releaseUnitIDs: [], itemUnits: [:], specialSounds: [], mode: .release)
        #expect(three.contains { $0.severity == .error && $0.message.contains("has 3 items") })

        let four = ReleaseGate.issues(in: sampleBundle(itemCount: 4), releaseUnitIDs: [], itemUnits: [:], specialSounds: [], mode: .release)
        #expect(four.contains { $0.severity == .warning && $0.message.contains("has 4 items") })
        #expect(!four.contains { $0.severity == .error && $0.field == "items" })

        let five = ReleaseGate.issues(in: sampleBundle(itemCount: 5), releaseUnitIDs: [], itemUnits: [:], specialSounds: [], mode: .release)
        #expect(five.contains { $0.severity == .warning && $0.message.contains("has 5 items") })

        let six = ReleaseGate.issues(in: sampleBundle(itemCount: 6), releaseUnitIDs: [], itemUnits: [:], specialSounds: [], mode: .release)
        #expect(!six.contains { $0.field == "items" })

        let devThree = ReleaseGate.issues(in: sampleBundle(itemCount: 3), releaseUnitIDs: [], itemUnits: [:], specialSounds: [], mode: .dev)
        #expect(devThree.contains { $0.severity == .warning && $0.message.contains("has 3 items") })
        #expect(!devThree.contains { $0.severity == .error })
    }

    @Test func lessonSizeIgnoresSoundExamples() {
        let three = ReleaseGate.issues(
            in: lessonBundle(introduces: 3, soundExamples: 6),
            releaseUnitIDs: [],
            itemUnits: [:],
            specialSounds: [],
            mode: .release
        )
        #expect(three.contains { $0.severity == .error && $0.message.contains("has 3 items") })
        #expect(!three.contains { $0.message.contains("has 9 items") })

        let four = ReleaseGate.issues(
            in: lessonBundle(introduces: 4, soundExamples: 5, letters: 0),
            releaseUnitIDs: [],
            itemUnits: [:],
            specialSounds: [],
            mode: .release
        )
        #expect(four.contains { $0.severity == .warning && $0.message.contains("has 4 items") })
        #expect(!four.contains { $0.severity == .error && $0.field == "items" })

        let withLetters = ReleaseGate.issues(
            in: lessonBundle(introduces: 3, soundExamples: 4, letters: 2),
            releaseUnitIDs: [],
            itemUnits: [:],
            specialSounds: [],
            mode: .release
        )
        #expect(withLetters.contains { $0.severity == .warning && $0.message.contains("has 5 items") })

        let soundsOnly = ReleaseGate.issues(
            in: lessonBundle(introduces: 0, soundExamples: 9),
            releaseUnitIDs: [],
            itemUnits: [:],
            specialSounds: [],
            mode: .release
        )
        #expect(soundsOnly.contains { $0.severity == .error && $0.message.contains("has 0 items") })
    }

    @Test func releaseListRequiresTheSoundsUnitAndThenChecksSpecialSounds() {
        let bundle = sampleBundle(itemCount: 6)
        let sound = SpecialSound(character: "ټ", translit: "ṭ")

        let empty = ReleaseGate.issues(in: bundle, releaseUnitIDs: [], itemUnits: [:], specialSounds: [sound], mode: .release)
        #expect(!empty.contains { $0.field == "release-units.json" && $0.message.contains("u-sounds") })
        #expect(!empty.contains { $0.field == "soundExample" })
        #expect(!empty.contains { $0.severity == .error })

        let greetings = ReleaseGate.issues(in: bundle, releaseUnitIDs: ["u-greetings"], itemUnits: [:], specialSounds: [sound], mode: .release)
        #expect(greetings.contains { $0.severity == .error && $0.field == "release-units.json" && $0.message.contains("does not include u-sounds") })
        #expect(!greetings.contains { $0.field == "soundExample" })

        let covered = bundleWithSoundExample()
        let listed = ReleaseGate.issues(
            in: covered.bundle,
            releaseUnitIDs: ["u-sounds"],
            itemUnits: covered.itemUnits,
            specialSounds: [sound, SpecialSound(character: "ڼ", translit: "ṇ")],
            mode: .release
        )
        #expect(listed.contains { $0.severity == .error && $0.field == "soundExample" && $0.message.contains("ڼ") })
        #expect(!listed.contains { $0.field == "soundExample" && $0.message.contains("ټ") })
        #expect(!listed.contains { $0.message.contains("does not include u-sounds") })

        let dev = ReleaseGate.issues(in: bundle, releaseUnitIDs: [], itemUnits: [:], specialSounds: [sound], mode: .dev)
        #expect(dev.contains { $0.severity == .warning && $0.field == "soundExample" && $0.message.contains("ټ") })
    }

    @Test func aReleasedUnitThatCannotFillPlacementQuestionsFailsTheGate() {
        let sound = word("e-sound", pashto: "ا", translit: "a", pronunciation: "a", en: "alef", status: .draft)
        let thin = word("e-thin", pashto: "ب", translit: "b", pronunciation: "b", en: "be", status: .draft)
        let fat = (1...6).map { index in
            word(
                "e-fat-\(index)",
                pashto: "ف\(index)",
                translit: "fat\(index)",
                pronunciation: "fat\(index)",
                en: "fat \(index)",
                status: .draft
            )
        }
        let hidden = word("e-hidden", pashto: "پ", translit: "p", pronunciation: "p", en: "pe", status: .draft)
        let outside = word("e-outside", pashto: "ت", translit: "t", pronunciation: "t", en: "te", status: .draft)
        let soundsLesson = Lesson(
            id: LessonID(rawValue: "l-sounds")!,
            title: "Sounds",
            items: [LessonItemRef(item: sound.id, role: .soundExample, sound: "a")]
        )
        let thinLesson = Lesson(
            id: LessonID(rawValue: "l-thin")!,
            title: "Thin",
            items: [LessonItemRef(item: thin.id, role: .introduce)]
        )
        let fatLesson = Lesson(
            id: LessonID(rawValue: "l-fat")!,
            title: "Fat",
            items: fat.map { LessonItemRef(item: $0.id, role: .introduce) }
        )
        let hiddenLesson = Lesson(
            id: LessonID(rawValue: "l-hidden")!,
            title: "Hidden",
            items: [LessonItemRef(item: hidden.id, role: .introduce)]
        )
        let outsideLesson = Lesson(
            id: LessonID(rawValue: "l-outside")!,
            title: "Outside",
            items: [LessonItemRef(item: outside.id, role: .introduce)]
        )
        func unit(_ id: String, _ lesson: Lesson) -> CourseUnit {
            CourseUnit(id: UnitID(rawValue: id)!, track: "main", title: id, lessons: [lesson])
        }
        let bundle = ContentBundle(
            contentVersion: "test",
            variant: ContentBundle.kabulVariant,
            romanization: romanization(difficult: []),
            items: [sound, thin, hidden, outside] + fat,
            units: [
                unit("u-sounds", soundsLesson),
                unit("u-greetings", thinLesson),
                unit("u-introductions", fatLesson),
                unit("u-family", hiddenLesson),
                unit("u-extra", outsideLesson),
            ],
            nonDistractorGroups: []
        )
        let released = ["u-sounds", "u-greetings", "u-introductions", "u-extra"]
        let issues = ReleaseGate.issues(in: bundle, releaseUnitIDs: released, itemUnits: [:], specialSounds: [], mode: .release)
        let placement = issues.filter { $0.field == "placement" }
        #expect(placement.map(\.id) == ["u-greetings"])
        #expect(placement.allSatisfy { $0.severity == .error && $0.message.contains("cannot produce 5 placement questions") })

        let dev = ReleaseGate.issues(in: bundle, releaseUnitIDs: released, itemUnits: [:], specialSounds: [], mode: .dev)
        let devPlacement = dev.filter { $0.field == "placement" }
        #expect(devPlacement.map(\.id) == ["u-greetings"])
        #expect(devPlacement.allSatisfy { $0.severity == .warning })

        let empty = ReleaseGate.issues(in: bundle, releaseUnitIDs: [], itemUnits: [:], specialSounds: [], mode: .release)
        #expect(!empty.contains { $0.field == "placement" })
    }

    @Test func audioInV1IsAWarning() {
        let bundle = sampleBundle(itemCount: 6, audioOnFirst: true)
        let issues = ReleaseGate.issues(in: bundle, releaseUnitIDs: [], itemUnits: [:], specialSounds: [], mode: .release)
        #expect(issues.contains { $0.severity == .warning && $0.field == "audio" })
        #expect(!issues.contains { $0.field == "audio" && $0.severity == .error })
    }

    @Test func verifiedWithoutADateIsStillAnError() {
        let item = word("e-na", pashto: "نه", translit: "na", pronunciation: "na", en: "no", status: .verified, checkedBy: "farhad", checkedOn: nil)
        let extras = (1..<6).map { index in
            word(
                "e-extra-\(index)",
                pashto: "ن\(index)",
                translit: "na",
                pronunciation: "na",
                en: "extra \(index)",
                status: .verified,
                checkedBy: "farhad",
                checkedOn: "2026-10-27"
            )
        }
        let ids = ["e-na"] + extras.map(\.id.rawValue)
        let bundle = bundle(items: [item] + extras, lessons: [lesson(itemIDs: ids)])
        let issues = ContentValidator.validate(bundle, mode: .release)
        let missingDate = issues.contains { issue in
            issue.id == "e-na" && issue.field == "verification.checkedOn" && issue.severity == .error
        }
        #expect(missingDate)
    }
}

struct QuizTypeCoverageTests {
    @Test func aFixtureWithEveryQuizTypePasses() {
        let bundle = coverageBundle(includeDialog: true)
        let release = QuizTypeCoverage.issues(in: bundle, releaseUnitIDs: ["u-coverage"], retiredItemIDs: [], mode: .release)
        let dev = QuizTypeCoverage.issues(in: bundle, releaseUnitIDs: ["u-coverage"], retiredItemIDs: [], mode: .dev)
        #expect(release.isEmpty)
        #expect(dev.isEmpty)
        #expect(!IssueList.hasError(release))
        #expect(!IssueList.hasError(dev))
    }

    @Test func kindCountsDoNotDependOnTheSeed() throws {
        let merged = try #require(ContentMerger.merge(root: try repositoryRoot()).merged)
        let wholeCourse = [
            coverageBundle(includeDialog: true),
            coverageBundle(includeDialog: false),
            merged.bundle,
        ]
        for bundle in wholeCourse {
            let base = QuizTypeCoverage.questionCounts(in: bundle, releaseUnitIDs: nil, retiredItemIDs: [], seed: 1)
            for seed in UInt64(2)...6 {
                let counts = QuizTypeCoverage.questionCounts(in: bundle, releaseUnitIDs: nil, retiredItemIDs: [], seed: seed)
                #expect(counts == base)
            }
        }
        let partial = courseWithDialogOnlyInLaterUnit()
        let released = QuizTypeCoverage.questionCounts(in: partial, releaseUnitIDs: ["u-coverage"], retiredItemIDs: [], seed: 1)
        for seed in UInt64(2)...6 {
            let counts = QuizTypeCoverage.questionCounts(in: partial, releaseUnitIDs: ["u-coverage"], retiredItemIDs: [], seed: seed)
            #expect(counts == released)
        }
    }

    @Test func aFixtureMissingOneQuizTypeFailsReleaseAndPassesDev() {
        let bundle = coverageBundle(includeDialog: false)
        let release = QuizTypeCoverage.issues(in: bundle, releaseUnitIDs: ["u-coverage"], retiredItemIDs: [], mode: .release)
        #expect(release.count == 1)
        #expect(release[0].severity == .error)
        #expect(release[0].id == "dialogResponse")
        #expect(release[0].field == "quizType")
        #expect(release[0].message == "quiz type dialogResponse produces 0 questions in released content")
        #expect(IssueList.hasError(release))

        let dev = QuizTypeCoverage.issues(in: bundle, releaseUnitIDs: ["u-coverage"], retiredItemIDs: [], mode: .dev)
        #expect(dev.count == 1)
        #expect(dev[0].severity == .warning)
        #expect(dev[0].message == release[0].message)
        #expect(!IssueList.hasError(dev))
    }

    @Test func aFullCoursePassesDevWhenTheReleasedSubsetLacksOneType() {
        let bundle = courseWithDialogOnlyInLaterUnit()
        let release = QuizTypeCoverage.issues(in: bundle, releaseUnitIDs: ["u-coverage"], retiredItemIDs: [], mode: .release)
        #expect(release.map(\.id) == ["dialogResponse"])
        #expect(release.allSatisfy { $0.severity == .error })

        let dev = QuizTypeCoverage.issues(in: bundle, releaseUnitIDs: ["u-coverage"], retiredItemIDs: [], mode: .dev)
        #expect(dev.isEmpty)
    }

    @Test func releaseFileListingOnlySoundsFailsQuizTypeCoverage() throws {
        let source = try repositoryRoot().appendingPathComponent("content")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.copyItem(at: source, to: root.appendingPathComponent("content"))
        try """
        {"units":["u-sounds"]}
        """.write(to: root.appendingPathComponent("content/release-units.json"), atomically: true, encoding: .utf8)

        let release = ContentCheck.issues(root: root, mode: .release)
        let quiz = release.filter { $0.field == "quizType" }
        #expect(quiz.map(\.severity) == Array(repeating: ValidationSeverity.error, count: quiz.count))
        #expect(!quiz.isEmpty)
        let missing = Set(quiz.compactMap(\.id))
        let selected = Set(ReleaseGate.releasedUnits(
            in: try #require(ContentMerger.merge(root: root).merged).bundle,
            releaseUnitIDs: ["u-sounds"]
        ).map(\.id.rawValue))
        #expect(selected == ["u-sounds"])
        let paused = OrderWords.includedInSessions ? Set<String>() : ["orderWords"]
        #expect(missing == Set(TaskKind.allCases.map(\.rawValue)).subtracting(paused))

        let dev = ContentCheck.issues(root: root, mode: .dev).filter { $0.field == "quizType" }
        #expect(dev.isEmpty)
    }
}

struct DialogReplyCoverageTests {
    @Test func realCourseShortagesAreTheTwoGreetingExceptions() throws {
        let merged = try #require(ContentMerger.merge(root: try repositoryRoot()).merged)
        let release = DialogReplyCoverage.issues(in: merged.bundle, retiredItemIDs: [], mode: .release)
        #expect(release.isEmpty)
        let dev = DialogReplyCoverage.issues(in: merged.bundle, retiredItemIDs: [], mode: .dev)
        #expect(dev.isEmpty)

        let open = DialogReplyCoverage.issues(
            in: merged.bundle,
            retiredItemIDs: [],
            mode: .release,
            exceptions: []
        )
        #expect(open.map(\.severity) == [.error, .error])
        #expect(open.map(\.id) == ["e-walaykum-salam", "e-xwar-ma-she"])
        #expect(open.map(\.field) == ["dialogReply", "dialogReply"])
        #expect(open[0].message == "e-walaykum-salam in l-greetings-1 has 1 wrong options of the same type for its dialog reply question. At least 3 are needed.")
        #expect(open[1].message == "e-xwar-ma-she in l-greetings-1 has 0 wrong options of the same type for its dialog reply question. At least 3 are needed.")

        let devOpen = DialogReplyCoverage.issues(
            in: merged.bundle,
            retiredItemIDs: [],
            mode: .dev,
            exceptions: []
        )
        #expect(devOpen.map(\.severity) == [.warning, .warning])
        #expect(devOpen.map(\.message) == open.map(\.message))

        let checked = ContentCheck.issues(root: try repositoryRoot(), mode: .release)
        #expect(!checked.contains { $0.field == "dialogReply" })
    }

    @Test func fewerThanThreeSameTypeOptionsFailsReleaseAndWarnsInDev() {
        let bundle = phraseReplyBundle(extraPhrases: 2)
        let release = DialogReplyCoverage.issues(in: bundle, retiredItemIDs: [], mode: .release, exceptions: [])
        #expect(release.count == 1)
        #expect(release[0].severity == .error)
        #expect(release[0].id == "e-reply")
        #expect(release[0].message == "e-reply in l-one has 2 wrong options of the same type for its dialog reply question. At least 3 are needed.")
        let dev = DialogReplyCoverage.issues(in: bundle, retiredItemIDs: [], mode: .dev, exceptions: [])
        #expect(dev.map(\.severity) == [.warning])
        #expect(dev[0].message == release[0].message)

        let enough = DialogReplyCoverage.issues(
            in: phraseReplyBundle(extraPhrases: 3),
            retiredItemIDs: [],
            mode: .release,
            exceptions: []
        )
        #expect(enough.isEmpty)
    }

    @Test func sharedUsageIsNotReportedAsTooFewOptions() {
        let prompt = dialogWord("e-prompt", pashto: "prompt line", en: "prompt")
        let first = dialogWord("e-reply", pashto: "right answer", en: "formal reply", usage: "formal", responseTo: "e-prompt")
        let second = dialogWord("e-other", pashto: "other answer", en: "other formal", usage: "FORMAL", responseTo: "e-prompt")
        let fillers = (1...4).map {
            dialogWord("e-fill-\($0)", pashto: "phrase \($0) text", en: "filler \($0)")
        }
        let bundle = singleLessonBundle([prompt, first, second] + fillers)
        let release = DialogReplyCoverage.issues(in: bundle, retiredItemIDs: [], mode: .release, exceptions: [])
        #expect(release.map(\.id) == ["e-reply", "e-other"])
        #expect(release.allSatisfy { $0.severity == .error })
        #expect(release.allSatisfy { $0.message.contains("same usage") })
        #expect(!release.contains { $0.message.contains("wrong options") })
    }

    @Test func anExceptionThatAlreadyHasThreeOptionsWarns() {
        let bundle = phraseReplyBundle(extraPhrases: 3)
        let release = DialogReplyCoverage.issues(
            in: bundle,
            retiredItemIDs: [],
            mode: .release,
            exceptions: ["e-reply"]
        )
        #expect(release.count == 1)
        #expect(release[0].severity == .warning)
        #expect(release[0].message == "e-reply in l-one is on the dialog-reply exception list and has 3 wrong options of the same type. The exception is no longer needed.")
    }

    @Test func questionsDoNotCountTowardTheMinimum() {
        let prompt = dialogWord("e-prompt", pashto: "prompt", en: "prompt")
        let reply = dialogWord("e-reply", pashto: "right answer", en: "the reply", responseTo: "e-prompt")
        let questions = (1...3).map {
            dialogWord("e-ask-\($0)", pashto: "question \($0)؟", en: "ask \($0)")
        }
        let phrases = (1...2).map {
            dialogWord("e-fill-\($0)", pashto: "phrase \($0) text", en: "fill \($0)")
        }
        let bundle = singleLessonBundle([prompt, reply] + questions + phrases)
        let issues = DialogReplyCoverage.issues(in: bundle, retiredItemIDs: [], mode: .release, exceptions: [])
        #expect(issues.map(\.message) == [
            "e-reply in l-one has 2 wrong options of the same type for its dialog reply question. At least 3 are needed.",
        ])
    }
}

struct RegistryTests {
    @Test func emptyRegistryPassesAndMissingOrRetiredIDsFail() {
        let bundle = sampleBundle(itemCount: 6)
        #expect(IDRegistryCheck.issues(entries: [], bundle: bundle).isEmpty)

        let missing = IDRegistryCheck.issues(entries: [RegistryEntry(id: "e-gone", retired: false)], bundle: bundle)
        #expect(missing.count == 1)
        #expect(missing[0].message.contains("not retired"))

        let retired = IDRegistryCheck.issues(entries: [RegistryEntry(id: "e-na", retired: true)], bundle: bundle)
        #expect(retired.count == 1)
        #expect(retired[0].message.contains("used again"))

        let kept = IDRegistryCheck.issues(entries: [RegistryEntry(id: "e-na", retired: false)], bundle: bundle)
        #expect(kept.isEmpty)
    }
}

struct MergeTests {
    @Test func sameInputEncodesToTheSameBytes() throws {
        let root = try writeCourse(itemCount: 6, difficult: false, releaseUnits: [], registry: [])
        let first = ContentMerger.merge(root: root)
        let second = ContentMerger.merge(root: root)
        #expect(first.issues.isEmpty)
        #expect(first.bytes == second.bytes)
        let again = try BundleJSON.encode(#require(first.merged).bundle)
        #expect(again == first.bytes)
    }

    @Test func checkFailsWhenTheCommittedFileDiffers() throws {
        let root = try writeCourse(itemCount: 6, difficult: false, releaseUnits: [], registry: [])
        let outcome = ContentMerger.merge(root: root)
        let bytes = try #require(outcome.bytes)
        try bytes.write(to: ContentRoot(url: root).bundleFile)
        #expect(ContentMerger.checkCommittedBundle(root: root).isEmpty)

        var changed = bytes
        changed.append(contentsOf: [0x20])
        try changed.write(to: ContentRoot(url: root).bundleFile)
        let issues = ContentMerger.checkCommittedBundle(root: root)
        #expect(issues.contains { $0.message.contains("does not match") })
    }

    @Test func duplicateIDsNameBothFiles() throws {
        let root = try writeCourse(itemCount: 6, difficult: false, releaseUnits: [], registry: [])
        let copy = """
        {
          "id": "u-other",
          "track": "main",
          "title": "Other",
          "items": [\(itemJSON("e-na", pashto: "نه", translit: "na", pronunciation: "na", en: "no"))],
          "lessons": [\(lessonJSON("l-other-1", itemIDs: ["e-na"]))]
        }
        """
        try copy.write(to: ContentRoot(url: root).unitFile(named: "u-other"), atomically: true, encoding: .utf8)
        var course = try String(contentsOf: ContentRoot(url: root).courseFile, encoding: .utf8)
        course = course.replacingOccurrences(of: "\"u-greetings\"", with: "\"u-greetings\", \"u-other\"")
        try course.write(to: ContentRoot(url: root).courseFile, atomically: true, encoding: .utf8)

        let issues = ContentMerger.merge(root: root).issues
        #expect(issues.contains { $0.message.contains("e-na") && $0.message.contains("u-greetings.json") && $0.message.contains("u-other.json") })
    }

    @Test func fileNameMustMatchTheUnitID() throws {
        let root = try writeCourse(itemCount: 6, difficult: false, releaseUnits: [], registry: [])
        let file = ContentRoot(url: root).unitFile(named: "u-greetings")
        var text = try String(contentsOf: file, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"id\":\"u-greetings\"", with: "\"id\":\"u-other\"")
        try text.write(to: file, atomically: true, encoding: .utf8)
        let issues = ContentMerger.merge(root: root).issues
        #expect(issues.contains { $0.message.contains("file name must match") })
    }

    @Test func releaseCommandGoesRedForDraftsSmallLessonsAndMissingSounds() throws {
        let drafts = try writeCourse(itemCount: 6, difficult: false, releaseUnits: ["u-greetings"], registry: [])
        let draftIssues = ContentCheck.issues(root: drafts, mode: .release)
        #expect(draftIssues.contains { $0.severity == .error && $0.message.contains("must be verified") })

        let small = try writeCourse(itemCount: 3, difficult: false, releaseUnits: [], registry: [])
        let smallIssues = ContentCheck.issues(root: small, mode: .release)
        #expect(smallIssues.contains { $0.severity == .error && $0.message.contains("has 3 items") })

        let unlisted = try writeCourse(itemCount: 6, difficult: true, releaseUnits: [], registry: [])
        let unlistedRelease = ContentCheck.issues(root: unlisted, mode: .release)
        #expect(!unlistedRelease.contains { $0.field == "soundExample" })
        #expect(!unlistedRelease.contains { $0.message.contains("does not include u-sounds") })

        let withoutSounds = try writeCourse(itemCount: 6, difficult: true, releaseUnits: ["u-greetings"], registry: [])
        let withoutSoundIssues = ContentCheck.issues(root: withoutSounds, mode: .release)
        #expect(withoutSoundIssues.contains { $0.severity == .error && $0.message.contains("does not include u-sounds") })
        #expect(!withoutSoundIssues.contains { $0.field == "soundExample" })

        let sounds = try writeCourse(itemCount: 6, difficult: true, releaseUnits: ["u-sounds"], registry: [], unitID: "u-sounds")
        let soundIssues = ContentCheck.issues(root: sounds, mode: .release)
        #expect(soundIssues.contains { $0.severity == .error && $0.field == "soundExample" })
        let devSounds = ContentCheck.issues(root: sounds, mode: .dev)
        #expect(devSounds.contains { $0.severity == .warning && $0.field == "soundExample" })
        #expect(!devSounds.contains { $0.severity == .error && $0.field == "soundExample" })
    }

    @Test func missingRomanizationTableWarnsInDevAndErrorsInRelease() throws {
        let root = try writeCourse(itemCount: 6, difficult: false, releaseUnits: [], registry: [])
        let merged = try #require(ContentMerger.merge(root: root).merged)
        #expect(merged.bundle.romanization.table.isEmpty)
        #expect(merged.bundle.romanization.unstressedWords.isEmpty)

        let dev = ContentCheck.issues(root: root, mode: .dev)
        #expect(dev.contains { $0.severity == .warning && $0.field == "romanization.table" })

        let release = ContentCheck.issues(root: root, mode: .release)
        #expect(release.contains { $0.severity == .error && $0.field == "romanization.table" })
    }

    @Test func unstressedWordsAreCheckedAgainstTheCourseTable() throws {
        let root = try writeCourse(
            itemCount: 6,
            difficult: false,
            releaseUnits: [],
            registry: [],
            romanization: #"{"table":[],"unstressedWords":["qa","salām"]}"#
        )
        let merged = try #require(ContentMerger.merge(root: root).merged)
        #expect(merged.bundle.romanization.table.isEmpty)
        #expect(merged.bundle.romanization.unstressedWords == ["qa", "salām"])

        let validator = ContentValidator.validate(merged.bundle, mode: .authoring)
        let unstressed = validator.filter { $0.field == "unstressedWords" }
        #expect(unstressed.contains { $0.message.contains("\"qa\"") && $0.message.contains("not in romanization.table") })
        #expect(unstressed.contains { $0.message.contains("\"salām\"") && $0.message.contains("syllables") })

        let dev = ContentCheck.issues(root: root, mode: .dev)
        #expect(dev.contains { $0.field == "unstressedWords" && $0.message.contains("not in romanization.table") })
        #expect(dev.contains { $0.field == "unstressedWords" && $0.message.contains("syllables") })
    }

    @Test func courseTableIsCopiedAndUnstressedChecksPass() throws {
        let root = try repositoryRoot()
        let merged = try #require(ContentMerger.merge(root: root).merged)
        let course = try JSONDecoder().decode(CourseFile.self, from: Data(contentsOf: ContentRoot(url: root).courseFile))
        let source = try #require(course.romanization)
        #expect(source.table.count == 53)
        #expect(merged.bundle.romanization.table == source.table)
        #expect(merged.bundle.romanization.unstressedWords == source.unstressedWords)
        let validator = ContentValidator.validate(merged.bundle, mode: .authoring)
        #expect(validator.filter { $0.field == "unstressedWords" }.isEmpty)
        #expect(!validator.contains { $0.severity == .error })
    }

    @Test func approvedReleaseListIsUnitsZeroThroughThree() throws {
        let root = try repositoryRoot()
        #expect(ContentMerger.checkCommittedBundle(root: root).isEmpty)
        let file = try JSONDecoder().decode(
            ReleaseUnitsFile.self,
            from: Data(contentsOf: ContentRoot(url: root).releaseUnitsFile)
        )
        #expect(file.units == ["u-sounds", "u-greetings", "u-introductions", "u-family"])
        let release = ContentCheck.issues(root: root, mode: .release)
        #expect(!release.contains { $0.message.contains("does not include u-sounds") })
        #expect(!release.contains { $0.severity == .error })
        #expect(!release.contains { $0.field == "soundExample" })
    }

    @Test func releaseListContainingSoundsUnitHasTheSixApprovedExamples() throws {
        let merged = try #require(ContentMerger.merge(root: try repositoryRoot()).merged)
        let issues = ReleaseGate.issues(
            in: merged.bundle,
            releaseUnitIDs: ["u-sounds"],
            itemUnits: merged.itemUnits,
            specialSounds: merged.specialSounds,
            mode: .release
        )
        #expect(!issues.contains { $0.field == "soundExample" })
    }

    @Test func devModeHasNoSoundExampleFindings() throws {
        let root = try repositoryRoot()
        let dev = ContentCheck.issues(root: root, mode: .dev)
        #expect(!dev.contains { $0.field == "soundExample" })
        #expect(!dev.contains { $0.severity == .error })
    }

    @Test func unitsFourThroughEightAreNewWordLessonsWithSixSoundExamples() throws {
        let root = try repositoryRoot()
        let merged = try #require(ContentMerger.merge(root: root).merged)
        let bundle = merged.bundle
        let releaseFile = try JSONDecoder().decode(
            ReleaseUnitsFile.self,
            from: Data(contentsOf: ContentRoot(url: root).releaseUnitsFile)
        )
        let releasedIDs = ["u-sounds", "u-greetings", "u-introductions", "u-family"]
        #expect(releaseFile.units == releasedIDs)
        let futureIDs = ["u-numbers", "u-food", "u-daily-life", "u-town", "u-conversation"]
        #expect(bundle.units.map(\.id.rawValue) == releasedIDs + futureIDs)

        let earlyPashto = Set(bundle.items.compactMap { item -> String? in
            guard let unit = merged.itemUnits[item.id.rawValue], releasedIDs.contains(unit) else { return nil }
            guard item.kind == .word || item.kind == .phrase else { return nil }
            return item.pashto
        })
        let futureUnits = bundle.units.filter { futureIDs.contains($0.id.rawValue) }
        #expect(futureUnits.flatMap(\.lessons).count == 17)
        #expect(futureUnits.allSatisfy { $0.lessons.allSatisfy(\.letters.isEmpty) })
        #expect(!futureUnits.contains { $0.lessons.contains { $0.id.rawValue.contains("letter") } })

        var introducedPashto: [String] = []
        for unit in futureUnits {
            for lesson in unit.lessons {
                let introduced = lesson.items.filter { $0.role == .introduce }
                #expect((4...6).contains(introduced.count), "\(lesson.id.rawValue) has \(introduced.count) new cards")
                #expect(lesson.items.allSatisfy { $0.role == .introduce })
                for reference in introduced {
                    let item = try #require(bundle.items.first { $0.id == reference.item })
                    #expect(item.kind == .word || item.kind == .phrase)
                    #expect(!earlyPashto.contains(item.pashto), "\(item.id.rawValue) repeats units 0–3")
                    #expect(item.responseTo == nil)
                    #expect(item.tokens == nil)
                    introducedPashto.append(item.pashto)
                }
            }
        }
        let bread = bundle.items.filter { $0.pashto == "ډوډۍ" }
        #expect(bread.count == 1)
        #expect(bread[0].id.rawValue == "e-do-day")
        #expect(bread[0].en == "bread")
        #expect(bread[0].pronunciation == "do-DAY")
        #expect(!earlyPashto.contains("ډوډۍ"))

        let examples: [(sound: String, id: String, pashto: String, pronunciation: String, en: String, unit: String)] = [
            ("ǧ", "e-shpag", "شپږ", "shpag", "six", "u-numbers"),
            ("ʿ", "e-o-mar", "عمر", "o-MAR", "age", "u-numbers"),
            ("ṇ", "e-ma-na", "مڼه", "ma-NA", "apple", "u-food"),
            ("q", "e-kah-wa", "قهوه", "kah-WA", "coffee", "u-food"),
            ("ṭ", "e-tak-see", "ټکسي", "tak-SEE", "taxi", "u-town"),
            ("ž", "e-zha-ba", "ژبه", "ZHA-ba", "language", "u-conversation"),
        ]
        let sounds = try #require(bundle.units.first { $0.id.rawValue == "u-sounds" }?.lessons.first { $0.id.rawValue == "l-sounds-1" })
        for example in examples {
            let refs = sounds.items.filter { $0.role == .soundExample && $0.item.rawValue == example.id }
            #expect(refs.count == 1)
            #expect(refs.first?.sound == example.sound)
            let item = try #require(bundle.items.first { $0.id.rawValue == example.id })
            #expect(item.pashto == example.pashto)
            #expect(item.pronunciation == example.pronunciation)
            #expect(item.en == example.en)
            let introductions = bundle.units.flatMap { unit in
                unit.lessons.flatMap { lesson in
                    lesson.items.filter { $0.role == .introduce && $0.item.rawValue == example.id }.map { _ in unit.id.rawValue }
                }
            }
            #expect(introductions == [example.unit])
        }
        #expect(Set(introducedPashto).isSuperset(of: Set(examples.map(\.pashto))))
    }

    @Test func soundsUnitOnlySoundExamplesBypassesSizeRule() {
        // Build a bundle where u-sounds has one lesson with only soundExample refs.
        let items = [
            word("e-a", pashto: "ا", translit: "a", pronunciation: "a", en: "a", status: .draft),
            word("e-b", pashto: "ب", translit: "b", pronunciation: "b", en: "b", status: .draft),
        ]
        let soundsLesson = Lesson(
            id: LessonID(rawValue: "l-sounds-1")!,
            title: "Sounds",
            items: [
                LessonItemRef(item: items[0].id, role: .soundExample, sound: "a"),
                LessonItemRef(item: items[1].id, role: .soundExample, sound: "b"),
            ]
        )
        let bundle = ContentBundle(
            contentVersion: "test",
            variant: ContentBundle.kabulVariant,
            romanization: romanization(difficult: []),
            items: items,
            units: [CourseUnit(id: UnitID(rawValue: "u-sounds")!, track: "main", title: "Sounds", lessons: [soundsLesson])],
            nonDistractorGroups: []
        )
        let issues = ReleaseGate.issues(in: bundle, releaseUnitIDs: [], itemUnits: [:], specialSounds: [], mode: .release)
        // No lesson-size findings for l-sounds-1
        #expect(!issues.contains { $0.field == "items" && $0.id == "l-sounds-1" && $0.message.contains("items") })
    }

    @Test func soundsUnitLessonWithoutASoundExampleIsErrorInDevAndRelease() {
        // Build a bundle where u-sounds has a lesson with no soundExample refs.
        let items = sampleWords(4).map {
            word($0.id, pashto: $0.pashto, translit: $0.translit, pronunciation: $0.pronunciation, en: $0.en, status: .draft)
        }
        let lesson = Lesson(
            id: LessonID(rawValue: "l-sounds-1")!,
            title: "Sounds",
            items: items.map { LessonItemRef(item: ItemID(rawValue: $0.id.rawValue)!, role: .introduce) }
        )
        let bundle = ContentBundle(
            contentVersion: "test",
            variant: ContentBundle.kabulVariant,
            romanization: romanization(difficult: []),
            items: items,
            units: [CourseUnit(id: UnitID(rawValue: "u-sounds")!, track: "main", title: "Sounds", lessons: [lesson])],
            nonDistractorGroups: []
        )
        let dev = ReleaseGate.issues(in: bundle, releaseUnitIDs: [], itemUnits: [:], specialSounds: [], mode: .dev)
        #expect(dev.contains { $0.severity == .error && $0.field == "items" && $0.id == "l-sounds-1" && $0.message.contains("soundExample") })
        let rel = ReleaseGate.issues(in: bundle, releaseUnitIDs: [], itemUnits: [:], specialSounds: [], mode: .release)
        #expect(rel.contains { $0.severity == .error && $0.field == "items" && $0.id == "l-sounds-1" && $0.message.contains("soundExample") })
    }

    @Test func repositorySoundsLessonHasNoSizeFinding() throws {
        let merged = try #require(ContentMerger.merge(root: try repositoryRoot()).merged)
        let issues = ReleaseGate.issues(
            in: merged.bundle,
            releaseUnitIDs: [],
            itemUnits: merged.itemUnits,
            specialSounds: merged.specialSounds,
            mode: .release
        )
        #expect(!issues.contains { $0.field == "items" && $0.id == "l-sounds-1" })
    }
}

private struct Covered {
    var bundle: ContentBundle
    var itemUnits: [String: String]
}

private func bundleWithSoundExample() -> Covered {
    let example = word("e-tol", pashto: "ټول", translit: "ṭol", pronunciation: "tol", en: "all", status: .draft, note: "ټ")
    let others = [
        word("e-na", pashto: "نه", translit: "na", pronunciation: "na", en: "no", status: .draft),
        word("e-ho", pashto: "هو", translit: "ho", pronunciation: "ho", en: "yes", status: .draft),
        word("e-za", pashto: "زه", translit: "zə", pronunciation: "za", en: "I", status: .draft),
        word("e-ta", pashto: "ته", translit: "tə", pronunciation: "ta", en: "you", status: .draft),
        word("e-da", pashto: "دا", translit: "da", pronunciation: "da", en: "this", status: .draft),
    ]
    let sounds = Lesson(
        id: LessonID(rawValue: "l-sounds-1")!,
        title: "Sounds",
        items: [LessonItemRef(item: example.id, role: .soundExample, sound: "ṭ")] + others.map { LessonItemRef(item: $0.id, role: .introduce) }
    )
    let later = Lesson(
        id: LessonID(rawValue: "l-greetings-1")!,
        title: "Later",
        items: ([example] + others).map { LessonItemRef(item: $0.id, role: .introduce) }
    )
    let bundle = ContentBundle(
        contentVersion: "test",
        variant: ContentBundle.kabulVariant,
        romanization: romanization(difficult: ["ټ"]),
        items: [example] + others,
        units: [
            CourseUnit(id: UnitID(rawValue: "u-sounds")!, track: "main", title: "Sounds", lessons: [sounds]),
            CourseUnit(id: UnitID(rawValue: "u-greetings")!, track: "main", title: "Greetings", lessons: [later]),
        ],
        nonDistractorGroups: []
    )
    return Covered(bundle: bundle, itemUnits: ["e-tol": "u-greetings"])
}

private func sampleBundle(itemCount: Int, audioOnFirst: Bool = false) -> ContentBundle {
    let rows = sampleWords(itemCount)
    var items = rows.map { row in
        word(row.id, pashto: row.pashto, translit: row.translit, pronunciation: row.pronunciation, en: row.en, status: .draft)
    }
    if audioOnFirst, let audio = AudioRef(normal: "a", slow: "b", speaker: "c") {
        let first = items[0]
        items[0] = ContentItem(
            id: first.id,
            kind: first.kind,
            pashto: first.pashto,
            translit: first.translit,
            pronunciation: first.pronunciation,
            en: first.en,
            verification: first.verification,
            audio: audio
        )
    }
    return bundle(items: items, lessons: [lesson(itemIDs: items.map(\.id.rawValue))])
}

private func bundle(items: [ContentItem], lessons: [Lesson]) -> ContentBundle {
    ContentBundle(
        contentVersion: "test",
        variant: ContentBundle.kabulVariant,
        romanization: romanization(difficult: []),
        items: items,
        units: [CourseUnit(id: UnitID(rawValue: "u-greetings")!, track: "main", title: "Greetings", lessons: lessons)],
        nonDistractorGroups: []
    )
}

private func lesson(itemIDs: [String]) -> Lesson {
    Lesson(
        id: LessonID(rawValue: "l-greetings-1")!,
        title: "Hello",
        items: itemIDs.map { LessonItemRef(item: ItemID(rawValue: $0)!, role: .introduce) }
    )
}

private let testUnstressedWords = [
    "ma", "še", "de", "da", "day", "ye", "yəm", "yāst", "na", "ho", "pə", "la", "də", "tsə", "zə", "tə",
]

private func romanization(difficult: [String]) -> Romanization {
    Romanization(
        table: [Romanization.Entry(letter: "a", translit: testUnstressedWords.joined(), ascii: "a", pronunciation: "a", description: "Coverage.")],
        difficultCharacters: difficult,
        unstressedWords: testUnstressedWords
    )
}

private struct WordRow {
    var id: String
    var pashto: String
    var translit: String
    var pronunciation: String
    var en: String
}

private func sampleWords(_ count: Int) -> [WordRow] {
    let rows = [
        WordRow(id: "e-na", pashto: "نه", translit: "na", pronunciation: "na", en: "no"),
        WordRow(id: "e-ho", pashto: "هو", translit: "ho", pronunciation: "ho", en: "yes"),
        WordRow(id: "e-za", pashto: "زه", translit: "zə", pronunciation: "za", en: "I"),
        WordRow(id: "e-ta", pashto: "ته", translit: "tə", pronunciation: "ta", en: "you"),
        WordRow(id: "e-da", pashto: "دا", translit: "da", pronunciation: "da", en: "this"),
        WordRow(id: "e-ma", pashto: "مه", translit: "ma", pronunciation: "ma", en: "me"),
    ]
    return Array(rows.prefix(count))
}

private func word(
    _ id: String,
    pashto: String,
    translit: String,
    pronunciation: String,
    en: String,
    status: VerificationStatus,
    checkedBy: String? = nil,
    checkedOn: String? = nil,
    note: String? = nil,
    kind: ContentKind = .word,
    responseTo: String? = nil,
    tokens: [String]? = nil,
    usage: String? = nil,
    name: String? = nil,
    sound: String? = nil,
    forms: LetterForms? = nil
) -> ContentItem {
    ContentItem(
        id: ItemID(rawValue: id)!,
        kind: kind,
        pashto: pashto,
        translit: translit,
        pronunciation: pronunciation,
        en: en,
        verification: Verification(status: status, checkedBy: checkedBy, checkedOn: checkedOn),
        usage: usage,
        pronunciationNote: note,
        responseTo: responseTo.flatMap { ItemID(rawValue: $0) },
        tokens: tokens,
        name: name,
        forms: forms,
        sound: sound
    )
}

/// Words for the choice and match questions, phrases for order and match, and
/// one greeting/reply pair. `includeDialog` is the only switch for dialog response.
/// The reply is one word, so its wrong options are single words.
private func coverageBundle(includeDialog: Bool) -> ContentBundle {
    let items = [
        word("e-na", pashto: "نه", translit: "na", pronunciation: "na-sound", en: "no", status: .draft),
        word("e-ho", pashto: "هو", translit: "ho", pronunciation: "ho-sound", en: "yes", status: .draft),
        word("e-za", pashto: "زه", translit: "za", pronunciation: "za-sound", en: "I", status: .draft),
        word("e-ta", pashto: "ته", translit: "ta", pronunciation: "ta-sound", en: "you", status: .draft),
        word(
            "e-fine",
            pashto: "زه ښه",
            translit: "za kha",
            pronunciation: "za-kha",
            en: "I am well",
            status: .draft,
            kind: .phrase,
            tokens: ["زه", "ښه"]
        ),
        word(
            "e-salam",
            pashto: "سلام",
            translit: "salam",
            pronunciation: "sa-lam",
            en: "hello",
            status: .draft,
            kind: .phrase
        ),
        word(
            "e-welcome",
            pashto: "ښه راغلاست",
            translit: "kha raghlay",
            pronunciation: "kha-ragh-lay",
            en: "welcome",
            status: .draft,
            kind: .phrase
        ),
        word(
            "e-goodbye",
            pashto: "خدای پامان",
            translit: "khuday paman",
            pronunciation: "khu-day-pa-man",
            en: "goodbye",
            status: .draft,
            kind: .phrase
        ),
        word(
            "e-reply",
            pashto: "وعلیکم",
            translit: "walaykum",
            pronunciation: "wa-lay-kum",
            en: "hello reply",
            status: .draft,
            kind: .phrase,
            responseTo: includeDialog ? "e-salam" : nil
        ),
    ]
    let letters = coverageLetters()
    let lesson = Lesson(
        id: LessonID(rawValue: "l-coverage-1")!,
        title: "Coverage",
        items: items.map { LessonItemRef(item: $0.id, role: .introduce) },
        letters: letters.map(\.id)
    )
    return ContentBundle(
        contentVersion: "test",
        variant: ContentBundle.kabulVariant,
        romanization: romanization(difficult: []),
        items: items + letters,
        units: [CourseUnit(id: UnitID(rawValue: "u-coverage")!, track: "main", title: "Coverage", lessons: [lesson])],
        nonDistractorGroups: []
    )
}

/// Three letters, including the ta pair, so find-the-letter, same-sound, and
/// first-letter questions can be built. ته in the word list starts with ت.
private func coverageLetters() -> [ContentItem] {
    func letter(_ id: String, _ pashto: String, _ name: String, _ sound: String, _ pronunciation: String, _ en: String) -> ContentItem {
        word(
            id,
            pashto: pashto,
            translit: sound,
            pronunciation: pronunciation,
            en: en,
            status: .draft,
            kind: .letter,
            name: name,
            sound: sound,
            forms: LetterForms(isolated: pashto, initial: pashto, medial: pashto, final: pashto)
        )
    }
    return [
        letter("e-letter-te", "ت", "تې", "t", "ta", "the letter ta"),
        letter("e-letter-tte", "ټ", "ټې", "ṭ", "tta", "the letter ta with a ring"),
        letter("e-letter-be", "ب", "بې", "b", "ba", "the letter ba"),
    ]
}

/// The first unit can build every type except dialog response. The reply that
/// produces that type is introduced in a later unit.
private func courseWithDialogOnlyInLaterUnit() -> ContentBundle {
    let earlier = coverageBundle(includeDialog: false)
    let reply = word(
        "e-later-reply",
        pashto: "ښه",
        translit: "kha",
        pronunciation: "kha-sound",
        en: "well reply",
        status: .draft,
        kind: .phrase,
        responseTo: "e-salam"
    )
    let lesson = Lesson(
        id: LessonID(rawValue: "l-dialog-1")!,
        title: "Dialog",
        items: [LessonItemRef(item: reply.id, role: .introduce)]
    )
    let later = CourseUnit(id: UnitID(rawValue: "u-dialog")!, track: "main", title: "Dialog", lessons: [lesson])
    return ContentBundle(
        contentVersion: earlier.contentVersion,
        variant: earlier.variant,
        romanization: earlier.romanization,
        items: earlier.items + [reply],
        units: earlier.units + [later],
        nonDistractorGroups: earlier.nonDistractorGroups
    )
}

private func dialogWord(
    _ id: String,
    pashto: String,
    en: String,
    kind: ContentKind = .phrase,
    usage: String? = nil,
    responseTo: String? = nil
) -> ContentItem {
    word(
        id,
        pashto: pashto,
        translit: "t-\(id)",
        pronunciation: "p-\(id)",
        en: en,
        status: .draft,
        kind: kind,
        responseTo: responseTo,
        usage: usage
    )
}

private func phraseReplyBundle(extraPhrases: Int) -> ContentBundle {
    let prompt = dialogWord("e-prompt", pashto: "prompt", en: "prompt")
    let reply = dialogWord("e-reply", pashto: "right answer", en: "the reply", responseTo: "e-prompt")
    let phrases = (1...extraPhrases).map {
        dialogWord("e-fill-\($0)", pashto: "phrase \($0) text", en: "fill \($0)")
    }
    let words = (1...4).map {
        dialogWord("e-word-\($0)", pashto: "word\($0)", en: "word \($0)", kind: .word)
    }
    return singleLessonBundle([prompt, reply] + phrases + words)
}

private func singleLessonBundle(_ items: [ContentItem]) -> ContentBundle {
    let lesson = Lesson(
        id: LessonID(rawValue: "l-one")!,
        title: "One",
        items: items.map { LessonItemRef(item: $0.id, role: .introduce) }
    )
    return ContentBundle(
        contentVersion: "test",
        variant: ContentBundle.kabulVariant,
        romanization: romanization(difficult: []),
        items: items,
        units: [CourseUnit(id: UnitID(rawValue: "u-one")!, track: "main", title: "One", lessons: [lesson])],
        nonDistractorGroups: []
    )
}

private func lessonBundle(introduces: Int, soundExamples: Int, letters: Int = 0) -> ContentBundle {
    let rows = sampleWords(6)
    let items = rows.map { word($0.id, pashto: $0.pashto, translit: $0.translit, pronunciation: $0.pronunciation, en: $0.en, status: .draft) }
    var refs: [LessonItemRef] = []
    for index in 0..<introduces {
        refs.append(LessonItemRef(item: items[index % items.count].id, role: .introduce))
    }
    for _ in 0..<soundExamples {
        refs.append(LessonItemRef(item: items[0].id, role: .soundExample, sound: "a"))
    }
    let letterIDs = (0..<letters).map { items[$0 % items.count].id }
    let lesson = Lesson(id: LessonID(rawValue: "l-greetings-1")!, title: "Hello", items: refs, letters: letterIDs)
    return bundle(items: items, lessons: [lesson])
}

private func writeCourse(
    itemCount: Int,
    difficult: Bool,
    releaseUnits: [String],
    registry: [RegistryEntry],
    unitID: String = "u-greetings",
    romanization: String? = nil
) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let content = root.appendingPathComponent("content", isDirectory: true)
    let units = content.appendingPathComponent("units", isDirectory: true)
    try FileManager.default.createDirectory(at: units, withIntermediateDirectories: true)
    let rows = sampleWords(itemCount)
    let items = rows.map { itemJSON($0.id, pashto: $0.pashto, translit: $0.translit, pronunciation: $0.pronunciation, en: $0.en) }.joined(separator: ",")
    let lesson = lessonJSON("l-greetings-1", itemIDs: rows.map(\.id))
    let unit = """
    {"id":"\(unitID)","track":"main","title":"Greetings","items":[\(items)],"lessons":[\(lesson)]}
    """
    try unit.write(to: units.appendingPathComponent("\(unitID).json"), atomically: true, encoding: .utf8)
    let romanizationField = romanization.map { #","romanization":\#($0)"# } ?? ""
    try """
    {"units":["\(unitID)"],"nonDistractorGroups":[]\(romanizationField)}
    """.write(to: content.appendingPathComponent("course.json"), atomically: true, encoding: .utf8)
    let letters = difficult ? #"[{"char":"ټ","codepoint":"U+067C","translit":"ṭ"}]"# : "[]"
    try """
    {"version":1,"letters":\(letters)}
    """.write(to: content.appendingPathComponent("difficult-characters.json"), atomically: true, encoding: .utf8)
    let release = releaseUnits.map { "\"\($0)\"" }.joined(separator: ",")
    try """
    {"units":[\(release)]}
    """.write(to: content.appendingPathComponent("release-units.json"), atomically: true, encoding: .utf8)
    let entries = registry.map { "{\"id\":\"\($0.id)\",\"retired\":\($0.retired)}" }.joined(separator: ",")
    try """
    {"entries":[\(entries)]}
    """.write(to: content.appendingPathComponent("id-registry.json"), atomically: true, encoding: .utf8)
    return root
}

private func itemJSON(_ id: String, pashto: String, translit: String, pronunciation: String, en: String) -> String {
    """
    {"id":"\(id)","kind":"word","pashto":"\(pashto)","translit":"\(translit)","pronunciation":"\(pronunciation)","en":"\(en)","verification":{"status":"draft"}}
    """
}

private func repositoryRoot() throws -> URL {
    var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let fileManager = FileManager.default
    while url.path != "/" {
        let course = url.appendingPathComponent("content").appendingPathComponent("course.json")
        if fileManager.fileExists(atPath: course.path) {
            return url
        }
        url.deleteLastPathComponent()
    }
    Issue.record("content/course.json was not found from \(#filePath)")
    throw CancellationError()
}

private func lessonJSON(_ id: String, itemIDs: [String]) -> String {
    let refs = itemIDs.map { #"{"item":"\#($0)","role":"introduce"}"# }.joined(separator: ",")
    return #"{"id":"\#(id)","title":"Hello","items":[\#(refs)]}"#
}
