public enum LessonItemRole: String, Codable, Hashable, Sendable {
    /// The lesson where the item is learned. This is the reference that later creates a review card.
    case introduce
    /// Shows an item as an example of a sound. Does not create a review card.
    case soundExample
}

/// A lesson's reference to a `ContentItem`.
public struct LessonItemRef: Codable, Hashable, Sendable {
    public let item: ItemID
    public let role: LessonItemRole
    /// Transliteration letter being illustrated, such as `ṭ`. Set for `soundExample`.
    public let sound: String?

    public init(item: ItemID, role: LessonItemRole, sound: String? = nil) {
        self.item = item
        self.role = role
        self.sound = sound
    }

    public init(from decoder: Decoder) throws {
        let container = try StrictJSON.container(from: decoder, keyedBy: CodingKeys.self)
        item = try StrictJSON.decode(ItemID.self, forKey: CodingKeys.item, from: container)
        role = try StrictJSON.decode(LessonItemRole.self, forKey: CodingKeys.role, from: container)
        sound = try StrictJSON.decodeIfPresent(String.self, forKey: CodingKeys.sound, from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(item, forKey: .item)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(sound, forKey: .sound)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case item
        case role
        case sound
    }
}

public struct DialogTurn: Codable, Hashable, Sendable {
    public let speaker: String
    public let item: ItemID

    public init(speaker: String, item: ItemID) {
        self.speaker = speaker
        self.item = item
    }

    public init(from decoder: Decoder) throws {
        let container = try StrictJSON.container(from: decoder, keyedBy: CodingKeys.self)
        speaker = try StrictJSON.decode(String.self, forKey: CodingKeys.speaker, from: container)
        item = try StrictJSON.decode(ItemID.self, forKey: CodingKeys.item, from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(speaker, forKey: .speaker)
        try container.encode(item, forKey: .item)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case speaker
        case item
    }
}

public struct Dialog: Codable, Hashable, Sendable {
    public let id: DialogID
    public let turns: [DialogTurn]

    public init(id: DialogID, turns: [DialogTurn]) {
        self.id = id
        self.turns = turns
    }

    public init(from decoder: Decoder) throws {
        let container = try StrictJSON.container(from: decoder, keyedBy: CodingKeys.self)
        id = try StrictJSON.decode(DialogID.self, forKey: CodingKeys.id, from: container)
        turns = try StrictJSON.decode([DialogTurn].self, forKey: CodingKeys.turns, from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(turns, forKey: .turns)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case turns
    }
}

public struct Lesson: Codable, Hashable, Sendable {
    public let id: LessonID
    public let title: String
    public let items: [LessonItemRef]
    public let letters: [ItemID]
    public let dialogs: [Dialog]

    public init(
        id: LessonID,
        title: String,
        items: [LessonItemRef],
        letters: [ItemID] = [],
        dialogs: [Dialog] = []
    ) {
        self.id = id
        self.title = title
        self.items = items
        self.letters = letters
        self.dialogs = dialogs
    }

    public init(from decoder: Decoder) throws {
        let container = try StrictJSON.container(from: decoder, keyedBy: CodingKeys.self)
        id = try StrictJSON.decode(LessonID.self, forKey: CodingKeys.id, from: container)
        title = try StrictJSON.decode(String.self, forKey: CodingKeys.title, from: container)
        items = try StrictJSON.decode([LessonItemRef].self, forKey: CodingKeys.items, from: container)
        letters = try StrictJSON.decodeIfPresent([ItemID].self, forKey: CodingKeys.letters, from: container) ?? []
        dialogs = try StrictJSON.decodeIfPresent([Dialog].self, forKey: CodingKeys.dialogs, from: container) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(letters, forKey: .letters)
        try container.encode(items, forKey: .items)
        try container.encode(dialogs, forKey: .dialogs)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case title
        case letters
        case items
        case dialogs
    }
}
