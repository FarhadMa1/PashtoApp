import Foundation

/// A complete pronunciation-audio block. v1.0 content leaves this unset.
///
/// `normal`, `slow`, and `speaker` are all required and non-empty.
/// An empty object or a partial block is not a value of this type.
public struct AudioRef: Codable, Hashable, Sendable {
    public let normal: String
    public let slow: String
    public let speaker: String

    public init?(normal: String, slow: String, speaker: String) {
        guard Self.isFilled(normal), Self.isFilled(slow), Self.isFilled(speaker) else {
            return nil
        }
        self.normal = normal
        self.slow = slow
        self.speaker = speaker
    }

    public init(from decoder: Decoder) throws {
        let container = try StrictJSON.container(from: decoder, keyedBy: CodingKeys.self)
        let normal = try StrictJSON.decode(String.self, forKey: CodingKeys.normal, from: container)
        let slow = try StrictJSON.decode(String.self, forKey: CodingKeys.slow, from: container)
        let speaker = try StrictJSON.decode(String.self, forKey: CodingKeys.speaker, from: container)
        guard let audio = AudioRef(normal: normal, slow: slow, speaker: speaker) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "audio requires non-empty normal, slow, and speaker."
                )
            )
        }
        self = audio
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(normal, forKey: .normal)
        try container.encode(slow, forKey: .slow)
        try container.encode(speaker, forKey: .speaker)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case normal
        case slow
        case speaker
    }

    private static func isFilled(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
