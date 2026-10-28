import Foundation
import PashtoCore

/// Values the merger writes into `content.json`.
///
/// The unit files do not carry the romanization table or `unstressedWords`.
/// The difficult-character list supplies those letters. The unstressed list is
/// the v1.0 list from the content decision, and one table row covers its characters
/// so the validator can check that list. `contentVersion` stays fixed until
/// `course.json` has a version field.
enum GeneratedBundle {
    static let contentVersion = "2026.11.0"
    static let unstressedWords = [
        "ma", "še", "de", "da", "day", "ye", "yəm", "yāst", "na", "ho", "pə", "la", "də", "tsə", "zə", "tə",
    ]

    static func romanization(from list: DifficultCharacterList) -> Romanization {
        var table = list.letters.map { entry in
            Romanization.Entry(
                letter: entry.char,
                translit: entry.translit,
                ascii: entry.translit,
                pronunciation: entry.translit,
                description: "Difficult character."
            )
        }
        table.append(
            Romanization.Entry(
                letter: "a",
                translit: unstressedWords.joined(),
                ascii: "a",
                pronunciation: "a",
                description: "Character coverage for unstressedWords."
            )
        )
        return Romanization(
            table: table,
            difficultCharacters: list.letters.map(\.char),
            unstressedWords: unstressedWords
        )
    }
}

enum BundleJSON {
    static func encode(_ bundle: ContentBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(bundle)
        data.append(0x0A)
        return data
    }
}
