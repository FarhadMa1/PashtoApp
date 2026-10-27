public struct CourseUnit: Codable, Hashable, Sendable {
    public let id: UnitID
    /// Course track name. Sample content uses `main`.
    public let track: String
    public let title: String
    public let lessons: [Lesson]

    public init(id: UnitID, track: String, title: String, lessons: [Lesson]) {
        self.id = id
        self.track = track
        self.title = title
        self.lessons = lessons
    }

    public init(from decoder: Decoder) throws {
        let container = try StrictJSON.container(from: decoder, keyedBy: CodingKeys.self)
        id = try StrictJSON.decode(UnitID.self, forKey: CodingKeys.id, from: container)
        track = try StrictJSON.decode(String.self, forKey: CodingKeys.track, from: container)
        title = try StrictJSON.decode(String.self, forKey: CodingKeys.title, from: container)
        lessons = try StrictJSON.decode([Lesson].self, forKey: CodingKeys.lessons, from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(track, forKey: .track)
        try container.encode(title, forKey: .title)
        try container.encode(lessons, forKey: .lessons)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case track
        case title
        case lessons
    }
}
