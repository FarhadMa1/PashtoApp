/// Ids match `^[uled]-[a-z0-9]+(-[a-z0-9]+)*$`. Each type also requires its own prefix.
enum ContentIDRules {
    /// Body after the prefix: `^[a-z0-9]+(-[a-z0-9]+)*$`. No empty segment and no trailing hyphen.
    static func parse(_ raw: String, prefix: String) -> String? {
        guard raw.hasPrefix(prefix) else { return nil }
        let body = raw[raw.index(raw.startIndex, offsetBy: prefix.count)...]
        var index = body.startIndex
        guard consumeSegment(body, &index) else { return nil }
        while index < body.endIndex {
            guard body[index] == "-" else { return nil }
            index = body.index(after: index)
            guard consumeSegment(body, &index) else { return nil }
        }
        return raw
    }

    static func decode(from decoder: Decoder, prefix: String, name: String) throws -> String {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = parse(raw, prefix: prefix) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "\(name) must match ^\(prefix)[a-z0-9]+(-[a-z0-9]+)*$. Got \"\(raw)\"."
            )
        }
        return parsed
    }

    static func encode(_ raw: String, to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    private static func consumeSegment(_ body: Substring, _ index: inout Substring.Index) -> Bool {
        let start = index
        while index < body.endIndex, isSlugLetterOrDigit(body[index]) {
            index = body.index(after: index)
        }
        return index != start
    }

    private static func isSlugLetterOrDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return false
        }
        switch scalar {
        case "a"..."z", "0"..."9":
            return true
        default:
            return false
        }
    }
}

/// Id of a word, phrase, dialog line, or letter. Prefix `e-`.
public struct ItemID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard let rawValue = ContentIDRules.parse(rawValue, prefix: "e-") else { return nil }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try ContentIDRules.decode(from: decoder, prefix: "e-", name: "ItemID")
    }

    public func encode(to encoder: Encoder) throws {
        try ContentIDRules.encode(rawValue, to: encoder)
    }

    public var description: String { rawValue }
}

/// Id of a lesson. Prefix `l-`.
public struct LessonID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard let rawValue = ContentIDRules.parse(rawValue, prefix: "l-") else { return nil }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try ContentIDRules.decode(from: decoder, prefix: "l-", name: "LessonID")
    }

    public func encode(to encoder: Encoder) throws {
        try ContentIDRules.encode(rawValue, to: encoder)
    }

    public var description: String { rawValue }
}

/// Id of a course unit. Prefix `u-`.
public struct UnitID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard let rawValue = ContentIDRules.parse(rawValue, prefix: "u-") else { return nil }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try ContentIDRules.decode(from: decoder, prefix: "u-", name: "UnitID")
    }

    public func encode(to encoder: Encoder) throws {
        try ContentIDRules.encode(rawValue, to: encoder)
    }

    public var description: String { rawValue }
}

/// Id of a dialog. Prefix `d-`.
public struct DialogID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard let rawValue = ContentIDRules.parse(rawValue, prefix: "d-") else { return nil }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try ContentIDRules.decode(from: decoder, prefix: "d-", name: "DialogID")
    }

    public func encode(to encoder: Encoder) throws {
        try ContentIDRules.encode(rawValue, to: encoder)
    }

    public var description: String { rawValue }
}
