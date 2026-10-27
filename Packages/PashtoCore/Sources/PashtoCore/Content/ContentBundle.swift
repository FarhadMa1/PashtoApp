/// The generated `content.json` bundle. Source files per unit are merged into this before the app sees them.
public struct ContentBundle: Codable, Hashable, Sendable {
    public static let supportedSchemaVersion = 1
    /// Kabul Pashto, the only variant in v1.0. Stored as `variant` on the bundle.
    public static let kabulVariant = "af-kabul"

    public let schemaVersion: Int
    public let contentVersion: String
    public let variant: String
    public let romanization: Romanization
    public let items: [ContentItem]
    public let units: [CourseUnit]
    public let nonDistractorGroups: [[ItemID]]

    public init(
        contentVersion: String,
        variant: String,
        romanization: Romanization,
        items: [ContentItem],
        units: [CourseUnit],
        nonDistractorGroups: [[ItemID]]
    ) {
        self.schemaVersion = Self.supportedSchemaVersion
        self.contentVersion = contentVersion
        self.variant = variant
        self.romanization = romanization
        self.items = items
        self.units = units
        self.nonDistractorGroups = nonDistractorGroups
    }

    public init(from decoder: Decoder) throws {
        let container = try StrictJSON.container(from: decoder, keyedBy: CodingKeys.self)
        let schemaVersion = try StrictJSON.decode(Int.self, forKey: CodingKeys.schemaVersion, from: container)
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath + [AnyCodingKey(CodingKeys.schemaVersion.stringValue)],
                    debugDescription: "Unsupported schemaVersion \(schemaVersion). This build reads \(Self.supportedSchemaVersion)."
                )
            )
        }
        self.schemaVersion = schemaVersion
        contentVersion = try StrictJSON.decode(String.self, forKey: CodingKeys.contentVersion, from: container)
        variant = try StrictJSON.decode(String.self, forKey: CodingKeys.variant, from: container)
        romanization = try StrictJSON.decode(Romanization.self, forKey: CodingKeys.romanization, from: container)
        items = try StrictJSON.decode([ContentItem].self, forKey: CodingKeys.items, from: container)
        units = try StrictJSON.decode([CourseUnit].self, forKey: CodingKeys.units, from: container)
        nonDistractorGroups = try StrictJSON.decode([[ItemID]].self, forKey: CodingKeys.nonDistractorGroups, from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(contentVersion, forKey: .contentVersion)
        try container.encode(variant, forKey: .variant)
        try container.encode(romanization, forKey: .romanization)
        try container.encode(items, forKey: .items)
        try container.encode(units, forKey: .units)
        try container.encode(nonDistractorGroups, forKey: .nonDistractorGroups)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case contentVersion
        case variant
        case romanization
        case items
        case units
        case nonDistractorGroups
    }
}
