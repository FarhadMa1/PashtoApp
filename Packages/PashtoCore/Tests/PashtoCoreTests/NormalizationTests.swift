import Testing
@testable import PashtoCore

struct NormalizationTests {
    @Test func stringEqualityHidesNonNFC() {
        let composed = "\u{00E9}"
        let decomposed = "e\u{0301}"

        #expect(composed == decomposed)
        #expect(Normalization.unicodeScalars(composed) != Normalization.unicodeScalars(decomposed))
        #expect(Normalization.isNFC(composed))
        #expect(!Normalization.isNFC(decomposed))
        #expect(
            Normalization.unicodeScalars(Normalization.nfc(decomposed))
                == Normalization.unicodeScalars(composed)
        )
    }

    @Test func comparisonKeyFoldsCaseWithoutStrippingDiacritics() {
        #expect(Normalization.comparisonKey("Hello") == "hello")
        #expect(Normalization.comparisonKey("I") == "i")
        #expect(Normalization.comparisonKey("e\u{0301}") == "\u{00E9}")
        #expect(Normalization.unicodeScalars(Normalization.comparisonKey("á")) == ["\u{00E1}"])
        #expect(Normalization.comparisonKey("ṭ") == "ṭ")
    }

    @Test func transliterationKeyDropsOnlyTheAcuteAccent() {
        #expect(Normalization.transliterationKey("á") == "a")
        #expect(Normalization.transliterationKey("a\u{0301}") == "a")
        #expect(Normalization.transliterationKey("Á") == "a")
        #expect(Normalization.transliterationKey("\u{0101}\u{0301}") == "\u{0101}")

        #expect(Normalization.unicodeScalars(Normalization.transliterationKey("\u{01E7}")) == ["\u{01E7}"])
        #expect(Normalization.transliterationKey("\u{01E7}\u{00ED}ra") == "\u{01E7}ira")
        #expect(Normalization.unicodeScalars(Normalization.transliterationKey("\u{1E6D}")) == ["\u{1E6D}"])
        #expect(Normalization.transliterationKey("x\u{030C}") != "x")
        #expect(Normalization.unicodeScalars(Normalization.transliterationKey("X\u{030C}")) == ["x", "\u{030C}"])

        let stressed = "as-sal\u{0101}\u{0301}m alayk\u{00FA}m"
        #expect(Normalization.transliterationKey(stressed) == "as-sal\u{0101}m alaykum")
        #expect(Normalization.transliterationKey(stressed) != "as-salam alaykum")
        #expect(Normalization.transliterationKey("st\u{0259}\u{0301}\u{1E5B}ay ma \u{0161}e") == "st\u{0259}\u{1E5B}ay ma \u{0161}e")
    }
}
