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
}
