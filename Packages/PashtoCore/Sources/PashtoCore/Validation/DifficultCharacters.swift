import Foundation

/// One row of `difficult-characters.json`.
///
/// The bundle stores only the character strings. This type checks the source
/// list itself: one character, and `codepoint` matches that character.
public struct DifficultCharacterEntry: Hashable, Sendable {
    public let char: String
    public let codepoint: String
    public let translit: String

    public init(char: String, codepoint: String, translit: String) {
        self.char = char
        self.codepoint = codepoint
        self.translit = translit
    }
}

extension DifficultCharacterEntry: Codable {
    public init(from decoder: Decoder) throws {
        let container = try StrictJSON.container(from: decoder, keyedBy: CodingKeys.self)
        char = try StrictJSON.decode(String.self, forKey: CodingKeys.char, from: container)
        codepoint = try StrictJSON.decode(String.self, forKey: CodingKeys.codepoint, from: container)
        translit = try StrictJSON.decode(String.self, forKey: CodingKeys.translit, from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(char, forKey: .char)
        try container.encode(codepoint, forKey: .codepoint)
        try container.encode(translit, forKey: .translit)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case char
        case codepoint
        case translit
    }
}

/// The `difficult-characters.json` document.
public struct DifficultCharacterList: Hashable, Sendable {
    public let version: Int
    public let letters: [DifficultCharacterEntry]

    public init(version: Int, letters: [DifficultCharacterEntry]) {
        self.version = version
        self.letters = letters
    }
}

extension DifficultCharacterList: Codable {
    public init(from decoder: Decoder) throws {
        let container = try StrictJSON.container(from: decoder, keyedBy: CodingKeys.self)
        version = try StrictJSON.decode(Int.self, forKey: CodingKeys.version, from: container)
        letters = try StrictJSON.decode([DifficultCharacterEntry].self, forKey: CodingKeys.letters, from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(letters, forKey: .letters)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case version
        case letters
    }
}

public enum DifficultCharacterRules {
    /// Each entry is one Unicode scalar, and `codepoint` is that scalar written as `U+` hex.
    public static func issues(in list: DifficultCharacterList) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var seen: Set<Unicode.Scalar> = []
        for (index, entry) in list.letters.enumerated() {
            let scalars = Normalization.unicodeScalars(entry.char)
            guard scalars.count == 1, let scalar = scalars.first else {
                issues.append(error(
                    "letters[\(index)] char must be one character.",
                    field: "char"
                ))
                continue
            }
            if !seen.insert(scalar).inserted {
                issues.append(error(
                    "letters[\(index)] repeats \(entry.char).",
                    field: "char"
                ))
            }
            guard let parsed = scalarFromCodepoint(entry.codepoint) else {
                issues.append(error(
                    "letters[\(index)] codepoint \"\(entry.codepoint)\" is not a U+ value.",
                    field: "codepoint"
                ))
                continue
            }
            if parsed != scalar {
                issues.append(error(
                    "letters[\(index)] codepoint \(entry.codepoint) does not match \(PashtoScript.code(scalar)).",
                    field: "codepoint"
                ))
            }
        }
        return issues
    }

    private static func scalarFromCodepoint(_ codepoint: String) -> Unicode.Scalar? {
        let scalars = Array(codepoint.unicodeScalars)
        guard scalars.count >= 3 else { return nil }
        let prefix = String(String.UnicodeScalarView(scalars.prefix(2))).lowercased(with: nil)
        guard prefix == "u+" else { return nil }
        let hex = String(String.UnicodeScalarView(scalars.dropFirst(2)))
        guard (1...6).contains(hex.count), let value = UInt32(hex, radix: 16) else { return nil }
        return Unicode.Scalar(value)
    }

    private static func error(_ message: String, field: String) -> ValidationIssue {
        ValidationIssue(id: nil, field: field, message: message, severity: .error)
    }
}
