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

    @Test func devBuildDropsResponseToWhenTheTargetIsHidden() {
        let signed = Verification(status: .verified, checkedBy: "farhad", checkedOn: "2026-10-27")
        let prompt = makeItem("e-salam", verification: signed)
        let draft = makeItem("e-draft", pashto: "نه", translit: "na", pronunciation: "na", en: "no")
        let toDraft = makeItem(
            "e-reply",
            pashto: "هو",
            translit: "ho",
            pronunciation: "ho",
            en: "yes",
            responseTo: "e-draft",
            verification: signed
        )
        let toPrompt = makeItem(
            "e-other",
            pashto: "زه",
            translit: "zə",
            pronunciation: "za",
            en: "I",
            responseTo: "e-salam",
            verification: signed
        )
        let bundle = makeBundle(items: [prompt, draft, toDraft, toPrompt])
        let filtered = ContentFilter.devBuild(bundle)
        let byID = Dictionary(uniqueKeysWithValues: filtered.items.map { ($0.id.rawValue, $0) })

        #expect(byID["e-reply"]?.responseTo == nil)
        #expect(byID["e-other"]?.responseTo?.rawValue == "e-salam")
        #expect(bundle.items.first { $0.id.rawValue == "e-reply" }?.responseTo?.rawValue == "e-draft")

        let dangling = makeItem(
            "e-dangling",
            pashto: "دا",
            translit: "da",
            pronunciation: "da",
            en: "this",
            responseTo: "e-missing",
            verification: signed
        )
        let keptLink = ContentFilter.devBuild(makeBundle(items: [prompt, dangling]))
        #expect(keptLink.items.first { $0.id.rawValue == "e-dangling" }?.responseTo?.rawValue == "e-missing")
    }

    @Test func devBuildDropsLessonsThatBecomeEmpty() {
        let signed = Verification(status: .verified, checkedBy: "farhad", checkedOn: "2026-10-27")
        let kept = makeItem("e-salam", verification: signed)
        let draft = makeItem("e-draft", pashto: "نه", translit: "na", pronunciation: "na", en: "no")
        let keptLesson = Lesson(
            id: lessonID("l-greetings-1"),
            title: "Kept",
            items: [LessonItemRef(item: kept.id, role: .introduce)]
        )
        let draftLesson = Lesson(
            id: lessonID("l-greetings-2"),
            title: "Drafts",
            items: [LessonItemRef(item: draft.id, role: .introduce)]
        )
        let bundle = makeBundle(
            items: [kept, draft],
            units: [CourseUnit(id: unitID("u-greetings"), track: "main", title: "Greetings", lessons: [keptLesson, draftLesson])]
        )
        let filtered = ContentFilter.devBuild(bundle)
        #expect(filtered.units[0].lessons.map(\.id.rawValue) == ["l-greetings-1"])
        #expect(bundle.units[0].lessons.count == 2)
    }
}
