/// Scholarly transliteration table and the lists the validator will use.
public struct Romanization: Codable, Hashable, Sendable {
    public let table: [Entry]
    public let difficultCharacters: [String]
    public let unstressedWords: [String]

    public init(table: [Entry], difficultCharacters: [String], unstressedWords: [String]) {
        self.table = table
        self.difficultCharacters = difficultCharacters
        self.unstressedWords = unstressedWords
    }

    public init(from decoder: Decoder) throws {
        let container = try StrictJSON.container(from: decoder, keyedBy: CodingKeys.self)
        table = try StrictJSON.decode([Entry].self, forKey: CodingKeys.table, from: container)
        difficultCharacters = try StrictJSON.decode([String].self, forKey: CodingKeys.difficultCharacters, from: container)
        unstressedWords = try StrictJSON.decode([String].self, forKey: CodingKeys.unstressedWords, from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(table, forKey: .table)
        try container.encode(difficultCharacters, forKey: .difficultCharacters)
        try container.encode(unstressedWords, forKey: .unstressedWords)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case table
        case difficultCharacters
        case unstressedWords
    }

    public struct Entry: Codable, Hashable, Sendable {
        public let letter: String
        public let translit: String
        public let ascii: String
        public let pronunciation: String
        public let description: String

        public init(letter: String, translit: String, ascii: String, pronunciation: String, description: String) {
            self.letter = letter
            self.translit = translit
            self.ascii = ascii
            self.pronunciation = pronunciation
            self.description = description
        }

        public init(from decoder: Decoder) throws {
            let container = try StrictJSON.container(from: decoder, keyedBy: CodingKeys.self)
            letter = try StrictJSON.decode(String.self, forKey: CodingKeys.letter, from: container)
            translit = try StrictJSON.decode(String.self, forKey: CodingKeys.translit, from: container)
            ascii = try StrictJSON.decode(String.self, forKey: CodingKeys.ascii, from: container)
            pronunciation = try StrictJSON.decode(String.self, forKey: CodingKeys.pronunciation, from: container)
            description = try StrictJSON.decode(String.self, forKey: CodingKeys.description, from: container)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(letter, forKey: .letter)
            try container.encode(translit, forKey: .translit)
            try container.encode(ascii, forKey: .ascii)
            try container.encode(pronunciation, forKey: .pronunciation)
            try container.encode(description, forKey: .description)
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case letter
            case translit
            case ascii
            case pronunciation
            case description
        }
    }
}
