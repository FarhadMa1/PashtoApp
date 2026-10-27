/// Keyed JSON decoding that fails when a key is not part of the type.
///
/// Synthesized `Codable` ignores unknown keys. Content files must not:
/// a typo such as `pronounciationNote` would otherwise decode as a missing field.
struct AnyCodingKey: CodingKey, Hashable, Sendable {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

enum StrictJSON {
    static func container<Keys: CodingKey & CaseIterable>(
        from decoder: Decoder,
        keyedBy keys: Keys.Type
    ) throws -> KeyedDecodingContainer<AnyCodingKey> {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowed = Set(keys.allCases.map(\.stringValue))
        let unknown = container.allKeys
            .map(\.stringValue)
            .filter { !allowed.contains($0) }
            .sorted()
        if !unknown.isEmpty {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown key(s): \(unknown.joined(separator: ", "))."
                )
            )
        }
        return container
    }

    static func decode<T: Decodable>(
        _ type: T.Type,
        forKey key: some CodingKey,
        from container: KeyedDecodingContainer<AnyCodingKey>
    ) throws -> T {
        try container.decode(T.self, forKey: AnyCodingKey(key.stringValue))
    }

    static func decodeIfPresent<T: Decodable>(
        _ type: T.Type,
        forKey key: some CodingKey,
        from container: KeyedDecodingContainer<AnyCodingKey>
    ) throws -> T? {
        try container.decodeIfPresent(T.self, forKey: AnyCodingKey(key.stringValue))
    }
}
