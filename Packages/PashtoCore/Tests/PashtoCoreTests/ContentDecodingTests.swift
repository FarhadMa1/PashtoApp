import Foundation
import Testing
@testable import PashtoCore

struct ContentDecodingTests {
    @Test func decodesSampleBundle() throws {
        let bundle = try decodeSample()

        #expect(bundle.schemaVersion == ContentBundle.supportedSchemaVersion)
        #expect(bundle.contentVersion == "2026.11.0")
        #expect(bundle.variant == ContentBundle.kabulVariant)
        #expect(bundle.items.count == 5)
        #expect(bundle.units.map(\.id.rawValue) == ["u-sounds", "u-greetings"])

        let greeting = try #require(bundle.items.first { $0.id.rawValue == "e-assalamu-alaykum" })
        #expect(greeting.kind == .phrase)
        #expect(greeting.pashto == "السلام علیکم")
        #expect(greeting.pronunciation == "as-sa-LAAM a-lay-KOOM")
        #expect(greeting.usage == "formal greeting")
        #expect(greeting.pronunciationNote?.contains("ع") == true)
        #expect(greeting.responseTo == nil)
        #expect(greeting.tokens == ["السلام", "علیکم"])
        #expect(greeting.audio == nil)
        #expect(greeting.hasAudio == false)
        #expect(greeting.verification.status == .draft)
        #expect(Normalization.isNFC(greeting.pashto))
        #expect(Normalization.transliterationKey(greeting.translit) == "as-sal\u{0101}m alaykum")

        let reply = try #require(bundle.items.first { $0.id.rawValue == "e-walaykum-salam" })
        #expect(reply.responseTo == greeting.id)
        #expect(reply.verification.status == .check)
        #expect(reply.verification.comment == "needs a native speaker")

        let tol = try #require(bundle.items.first { $0.id.rawValue == "e-tol" })
        #expect(tol.kind == .word)
        #expect(tol.verification.status == .verified)
        #expect(tol.verification.checkedBy == "farhad")
        #expect(tol.verification.checkedOn == "2026-10-27")

        let stare = try #require(bundle.items.first { $0.id.rawValue == "e-stare-ma-she" })
        #expect(stare.enAlt == ["may you not be tired"])
        #expect(stare.tokens == ["ستړی", "مه", "شې"])
        #expect(stare.acceptedOrders == [[0, 2, 1]])

        let letter = try #require(bundle.items.first { $0.id.rawValue == "e-letter-te-retroflex" })
        #expect(letter.kind == .letter)
        #expect(letter.name == "ټې")
        #expect(letter.sound == "ṭ")
        #expect(letter.forms == LetterForms(isolated: "ټ", initial: "ټ", medial: "ټ", final: "ټ"))

        let sounds = try #require(bundle.units.first { $0.id.rawValue == "u-sounds" })
        #expect(sounds.track == "main")
        #expect(sounds.lessons[0].letters.isEmpty)
        #expect(sounds.lessons[0].dialogs.isEmpty)
        #expect(sounds.lessons[0].items == [
            LessonItemRef(item: tol.id, role: .soundExample, sound: "ṭ"),
        ])

        let greetings = try #require(bundle.units.first { $0.id.rawValue == "u-greetings" })
        #expect(greetings.lessons[0].letters == [letter.id])
        #expect(greetings.lessons[0].items.map(\.role) == [.introduce, .introduce, .introduce, .introduce])
        #expect(greetings.lessons[0].dialogs[0].id.rawValue == "d-greetings-1")
        #expect(greetings.lessons[0].dialogs[0].turns.map(\.speaker) == ["A", "B"])

        #expect(bundle.nonDistractorGroups == [[greeting.id, stare.id]])
        #expect(bundle.romanization.difficultCharacters == [
            "ټ", "ډ", "ړ", "ڼ", "ښ", "ږ", "څ", "ځ", "خ", "غ", "ژ", "ق", "ع",
        ])
        let ghayn = try #require(bundle.romanization.table.first { $0.letter == "ږ" })
        #expect(ghayn.translit == "\u{01E7}")
        #expect(ghayn.ascii == "gy")
        #expect(!Normalization.unicodeScalars(ghayn.translit).contains(Normalization.stressScalar))
        #expect(bundle.romanization.unstressedWords.contains("še"))

        for item in bundle.items {
            #expect(Normalization.isNFC(item.pashto), "\(item.id) pashto is not NFC")
        }
    }

    @Test func roundTripsSampleBundle() throws {
        let data = try fixtureData("sample-content.json")
        let decoded = try JSONDecoder().decode(ContentBundle.self, from: data)
        let encoded = try JSONEncoder().encode(decoded)
        let again = try JSONDecoder().decode(ContentBundle.self, from: encoded)
        #expect(again == decoded)
    }

    @Test func decodesEveryKind() throws {
        for kind in ["word", "phrase", "dialogLine", "letter"] {
            let item = try JSONDecoder().decode(ContentItem.self, from: Data(minimalItem(kind: kind).utf8))
            #expect(item.kind.rawValue == kind)
        }
    }

    @Test func letterFormKeysKeepTheirValues() throws {
        let forms = try JSONDecoder().decode(
            LetterForms.self,
            from: Data(#"{"isolated":"iso","initial":"ini","medial":"med","final":"fin"}"#.utf8)
        )
        #expect(forms.isolated == "iso")
        #expect(forms.initial == "ini")
        #expect(forms.medial == "med")
        #expect(forms.final == "fin")
    }

    @Test func omittedLessonCollectionsDecodeAsEmpty() throws {
        let lesson = try JSONDecoder().decode(
            Lesson.self,
            from: Data(#"{"id":"l-sounds-1","title":"New sounds","items":[]}"#.utf8)
        )
        #expect(lesson.letters.isEmpty)
        #expect(lesson.dialogs.isEmpty)
    }

    @Test func unknownKeysAreRejected() {
        expectFailure(
            ContentItem.self,
            minimalItem(extra: #""pronounciationNote": "x","#),
            mentioning: "pronounciationNote"
        )
        expectFailure(
            ContentItem.self,
            minimalItem(extra: #""usge": null,"#),
            mentioning: "usge"
        )
        expectFailure(
            ContentBundle.self,
            minimalBundle(extra: #","oops": true"#),
            mentioning: "oops"
        )
        expectFailure(
            Verification.self,
            #"{"status":"draft","checkedby":"farhad"}"#,
            mentioning: "checkedby"
        )
        expectFailure(
            LetterForms.self,
            #"{"isolated":"ا","initial":"ا","medial":"ا","final":"ا","isolatd":"ا"}"#,
            mentioning: "isolatd"
        )
        expectFailure(
            Romanization.Entry.self,
            #"{"letter":"ږ","translit":"ǧ","ascii":"gy","pronunciation":"g","description":"g","note":"x"}"#,
            mentioning: "note"
        )
        expectFailure(
            LessonItemRef.self,
            #"{"item":"e-tol","role":"soundExample","sounds":"ṭ"}"#,
            mentioning: "sounds"
        )
        expectFailure(
            DialogTurn.self,
            #"{"speaker":"A","item":"e-salam","line":1}"#,
            mentioning: "line"
        )
    }

    @Test func rejectsIncompleteAudio() {
        expectFailure(AudioRef.self, "{}", mentioning: "normal")
        expectFailure(
            AudioRef.self,
            #"{"normal":"a.m4a","slow":"a-slow.m4a"}"#,
            mentioning: "speaker"
        )
        expectFailure(
            AudioRef.self,
            #"{"normal":" ","slow":"a-slow.m4a","speaker":"kabul-1"}"#,
            mentioning: "non-empty"
        )
        expectFailure(
            AudioRef.self,
            #"{"normal":"a.m4a","slow":"a-slow.m4a","speaker":"kabul-1","fast":"a-fast.m4a"}"#,
            mentioning: "fast"
        )
        expectFailure(
            ContentItem.self,
            minimalItem(extra: #""audio": {},"#),
            mentioning: "normal"
        )
        #expect(AudioRef(normal: "", slow: "a.m4a", speaker: "kabul-1") == nil)
    }

    @Test func completeAudioSetsHasAudio() throws {
        let audio = try #require(AudioRef(normal: "a.m4a", slow: "a-slow.m4a", speaker: "kabul-1"))
        let item = try JSONDecoder().decode(
            ContentItem.self,
            from: Data(minimalItem(extra: #""audio": {"normal":"a.m4a","slow":"a-slow.m4a","speaker":"kabul-1"},"#).utf8)
        )
        #expect(item.audio == audio)
        #expect(item.hasAudio)
        let encoded = try JSONEncoder().encode(item)
        let again = try JSONDecoder().decode(ContentItem.self, from: encoded)
        #expect(again == item)
    }

    @Test func rejectsMalformedIDs() throws {
        #expect(ItemID(rawValue: "e-assalamu-alaykum") != nil)
        #expect(LessonID(rawValue: "l-sounds-1") != nil)
        #expect(UnitID(rawValue: "u-sounds") != nil)
        #expect(DialogID(rawValue: "d-greetings-1") != nil)

        #expect(ItemID(rawValue: "e-") == nil)
        #expect(ItemID(rawValue: "E-salam") == nil)
        #expect(ItemID(rawValue: "e-salam_1") == nil)
        #expect(ItemID(rawValue: "u-sounds") == nil)
        #expect(LessonID(rawValue: "e-sounds") == nil)
        #expect(DialogID(rawValue: "l-greetings-1") == nil)

        expectFailure(ItemID.self, #""e_bad""#, mentioning: "ItemID")
        expectFailure(ContentItem.self, minimalItem(id: "u1-hilsen-03"), mentioning: "ItemID")
        expectFailure(
            LessonItemRef.self,
            #"{"item":"tol","role":"introduce"}"#,
            mentioning: "ItemID"
        )
    }

    @Test func decodesVerificationStatuses() throws {
        let draft = try JSONDecoder().decode(Verification.self, from: Data(#"{"status":"draft"}"#.utf8))
        #expect(draft.status == .draft)
        #expect(draft.checkedBy == nil)
        #expect(draft.checkedOn == nil)

        let verified = try JSONDecoder().decode(
            Verification.self,
            from: Data(#"{"status":"verified","checkedBy":"farhad","checkedOn":"2026-10-27"}"#.utf8)
        )
        #expect(verified.status == .verified)
        #expect(verified.checkedBy == "farhad")

        // `verified` without a signer still decodes. The validator rejects it.
        let unsigned = try JSONDecoder().decode(Verification.self, from: Data(#"{"status":"verified"}"#.utf8))
        #expect(unsigned.status == .verified)
        #expect(unsigned.checkedOn == nil)

        expectFailure(Verification.self, #"{"status":"retired"}"#, mentioning: "retired")
    }

    @Test func rejectsUnsupportedSchemaVersion() {
        expectFailure(ContentBundle.self, minimalBundle(schemaVersion: 2), mentioning: "schemaVersion")
    }

    @Test func missingRoleIsAnError() {
        expectFailure(
            LessonItemRef.self,
            #"{"item":"e-tol","sound":"ṭ"}"#,
            mentioning: "role"
        )
    }
}

private func decodeSample() throws -> ContentBundle {
    try JSONDecoder().decode(ContentBundle.self, from: fixtureData("sample-content.json"))
}

private func fixtureData(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(name)
    return try Data(contentsOf: url)
}

private func minimalItem(id: String = "e-salam", kind: String = "word", extra: String = "") -> String {
    """
    {
      "id": "\(id)",
      "kind": "\(kind)",
      "pashto": "سلام",
      "translit": "salām",
      "pronunciation": "sa-LAAM",
      "en": "hello",
      \(extra)
      "verification": {"status": "draft"}
    }
    """
}

private func minimalBundle(schemaVersion: Int = 1, extra: String = "") -> String {
    """
    {
      "schemaVersion": \(schemaVersion),
      "contentVersion": "2026.11.0",
      "variant": "af-kabul",
      "romanization": {"table": [], "difficultCharacters": [], "unstressedWords": []},
      "items": [],
      "units": [],
      "nonDistractorGroups": []
      \(extra)
    }
    """
}

private func expectFailure<T: Decodable>(
    _ type: T.Type,
    _ json: String,
    mentioning needle: String
) {
    do {
        _ = try JSONDecoder().decode(T.self, from: Data(json.utf8))
        Issue.record("Expected \(T.self) to reject the JSON")
    } catch {
        #expect(String(describing: error).contains(needle), "\(error)")
    }
}
