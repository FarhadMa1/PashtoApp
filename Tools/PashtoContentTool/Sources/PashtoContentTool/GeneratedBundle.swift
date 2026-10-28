import Foundation
import PashtoCore

/// Values the merger writes into `content.json`.
///
/// The unit files do not carry the romanization table or `unstressedWords`.
/// `unstressedWords` is the v1.0 list from the content decision. The table is
/// left empty until Pashto Expert supplies it. A joined placeholder row would
/// make the unstressed-character check pass without looking at a real table.
/// `contentVersion` stays fixed until `course.json` has a version field.
enum GeneratedBundle {
    static let contentVersion = "2026.11.0"
    static let unstressedWords = [
        "ma", "še", "de", "da", "day", "ye", "yəm", "yāst", "na", "ho", "pə", "la", "də", "tsə", "zə", "tə",
    ]

    static func romanization(from list: DifficultCharacterList) -> Romanization {
        Romanization(
            table: [],
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
