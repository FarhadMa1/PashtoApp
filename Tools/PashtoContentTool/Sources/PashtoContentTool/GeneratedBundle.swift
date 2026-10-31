import Foundation
import PashtoCore

/// Values the merger writes into `content.json` that the source files do not carry.
///
/// The romanization table and `unstressedWords` come from `course.json`.
/// This file does not invent table rows. `contentVersion` stays fixed until
/// `course.json` has a version field.
enum GeneratedBundle {
    static let contentVersion = "2026.11.0"
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
