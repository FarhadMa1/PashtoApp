import Testing
@testable import PashtoCore

struct ContentFilterTests {
    @Test func devBuildKeepsVerifiedItemsOnly() {
        let verified = makeItem(
            "e-salam",
            verification: Verification(status: .verified, checkedBy: "farhad", checkedOn: "2026-10-27")
        )
        let draft = makeItem("e-draft", pashto: "نه", translit: "na", pronunciation: "na", en: "no")
        let checking = makeItem(
            "e-check",
            pashto: "هو",
            translit: "ho",
            pronunciation: "ho",
            en: "yes",
            verification: Verification(status: .check)
        )
        let lesson = Lesson(
            id: lessonID("l-greetings-1"),
            title: "Hello",
            items: [verified, draft, checking].map { LessonItemRef(item: $0.id, role: .introduce) },
            letters: [draft.id],
            dialogs: [Dialog(id: dialogID("d-greetings-1"), turns: [
                DialogTurn(speaker: "A", item: verified.id),
                DialogTurn(speaker: "B", item: draft.id),
            ])]
        )
        let bundle = makeBundle(
            items: [verified, draft, checking],
            units: [CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [lesson])],
            groups: [[verified.id, draft.id], [verified.id, checking.id]]
        )

        let filtered = ContentFilter.devBuild(bundle)

        #expect(filtered.items.map(\.id.rawValue) == ["e-salam"])
        #expect(filtered.units[0].lessons[0].items.map(\.item.rawValue) == ["e-salam"])
        #expect(filtered.units[0].lessons[0].letters.isEmpty)
        #expect(filtered.units[0].lessons[0].dialogs.count == 1)
        #expect(filtered.units[0].lessons[0].dialogs[0].turns.map(\.item.rawValue) == ["e-salam"])
        #expect(filtered.nonDistractorGroups.isEmpty)
        #expect(bundle.items.count == 3)
    }

    @Test func devBuildLeavesBrokenResponseToAndEmptyLessonsForValidation() {
        let signed = Verification(status: .verified, checkedBy: "farhad", checkedOn: "2026-10-27")
        let prompt = makeItem("e-salam", verification: signed)
        let draft = makeItem("e-draft", pashto: "نه", translit: "na", pronunciation: "na", en: "no")
        let reply = makeItem(
            "e-reply",
            pashto: "هو",
            translit: "ho",
            pronunciation: "ho",
            en: "yes",
            responseTo: "e-draft",
            verification: signed
        )
        let keptLesson = Lesson(
            id: lessonID("l-greetings-1"),
            title: "Kept",
            items: [prompt, reply].map { LessonItemRef(item: $0.id, role: .introduce) }
        )
        let draftLesson = Lesson(
            id: lessonID("l-greetings-2"),
            title: "Drafts",
            items: [LessonItemRef(item: draft.id, role: .introduce)]
        )
        let bundle = makeBundle(
            items: [prompt, draft, reply],
            units: [CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [keptLesson, draftLesson])]
        )
        let filtered = ContentFilter.devBuild(bundle)
        let replyAfter = filtered.items.first { $0.id.rawValue == "e-reply" }

        #expect(replyAfter?.responseTo?.rawValue == "e-draft")
        #expect(filtered.units[0].lessons.map(\.id.rawValue) == ["l-greetings-1", "l-greetings-2"])
        #expect(filtered.units[0].lessons[1].items.isEmpty)
        #expect(bundle.items.first { $0.id.rawValue == "e-reply" }?.responseTo?.rawValue == "e-draft")

        for mode in [ValidationMode.authoring, ValidationMode.release] {
            let issues = validate(filtered, mode: mode)
            let errors = issues.filter { $0.severity == .error }
            #expect(errors.contains { $0.field == "responseTo" && $0.message.contains("e-draft") && $0.message.contains("does not exist") })
            #expect(errors.contains { $0.id == "l-greetings-2" && $0.message.contains("is empty") })
        }
    }
}
