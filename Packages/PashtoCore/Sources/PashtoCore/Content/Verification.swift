/// Review state of one content item.
///
/// `verified` still requires a non-empty `checkedBy` and an ISO-8601 `checkedOn`
/// before a release. That rule belongs to the validator. Decoding keeps the
/// strings so a draft file loads, and so this type does not parse dates.
public enum VerificationStatus: String, Codable, Hashable, Sendable {
    case draft
    case check
    case verified
}

public struct Verification: Codable, Hashable, Sendable {
    public let status: VerificationStatus
    public let checkedBy: String?
    public let checkedOn: String?
    public let comment: String?

    public init(
        status: VerificationStatus,
        checkedBy: String? = nil,
        checkedOn: String? = nil,
        comment: String? = nil
    ) {
        self.status = status
        self.checkedBy = checkedBy
        self.checkedOn = checkedOn
        self.comment = comment
    }

    public init(from decoder: Decoder) throws {
        let container = try StrictJSON.container(from: decoder, keyedBy: CodingKeys.self)
        status = try StrictJSON.decode(VerificationStatus.self, forKey: CodingKeys.status, from: container)
        checkedBy = try StrictJSON.decodeIfPresent(String.self, forKey: CodingKeys.checkedBy, from: container)
        checkedOn = try StrictJSON.decodeIfPresent(String.self, forKey: CodingKeys.checkedOn, from: container)
        comment = try StrictJSON.decodeIfPresent(String.self, forKey: CodingKeys.comment, from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(checkedBy, forKey: .checkedBy)
        try container.encodeIfPresent(checkedOn, forKey: .checkedOn)
        try container.encodeIfPresent(comment, forKey: .comment)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case status
        case checkedBy
        case checkedOn
        case comment
    }
}
