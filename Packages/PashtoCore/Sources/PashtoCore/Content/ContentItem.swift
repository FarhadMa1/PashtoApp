public enum ContentKind: String, Codable, Hashable, Sendable {
    case word
    case phrase
    case dialogLine
    case letter
}

/// The four shapes of one letter. Present only on letter items.
public struct LetterForms: Codable, Hashable, Sendable {
    public let isolated: String
    public let initial: String
    public let medial: String
    public let final: String

    public init(isolated: String, initial: String, medial: String, final: String) {
        self.isolated = isolated
        self.initial = initial
        self.medial = medial
        self.final = final
    }

    public init(from decoder: Decoder) throws {
        let container = try StrictJSON.container(from: decoder, keyedBy: CodingKeys.self)
        isolated = try StrictJSON.decode(String.self, forKey: CodingKeys.isolated, from: container)
        initial = try StrictJSON.decode(String.self, forKey: CodingKeys.initial, from: container)
        medial = try StrictJSON.decode(String.self, forKey: CodingKeys.medial, from: container)
        final = try StrictJSON.decode(String.self, forKey: CodingKeys.final, from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isolated, forKey: .isolated)
        try container.encode(initial, forKey: .initial)
        try container.encode(medial, forKey: .medial)
        try container.encode(final, forKey: .final)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case isolated
        case initial
        case medial
        case final
    }
}

/// One word, phrase, dialog line, or letter. Lessons reference this value; they do not copy it.
public struct ContentItem: Codable, Hashable, Sendable {
    public let id: ItemID
    public let kind: ContentKind
    public let pashto: String
    /// Scholarly transliteration, including stress marks. The JSON key is `translit`.
    public let translit: String
    /// Simple pronunciation shown in the app. Stressed syllables are uppercase.
    public let pronunciation: String
    /// English meaning. Null and a missing key are both nil so the validator can report a missing gloss.
    public let en: String?
    public let enAlt: [String]?
    public let usage: String?
    public let pronunciationNote: String?
    public let responseTo: ItemID?
    public let tokens: [String]?
    public let acceptedOrders: [[Int]]?
    public let audio: AudioRef?
    public let verification: Verification
    /// Letter name. Used when `kind` is `letter`.
    public let name: String?
    public let forms: LetterForms?
    /// Sound of a letter, in transliteration. Distinct from `LessonItemRef.sound`.
    public let sound: String?

    /// True only for a complete audio block. A partial block never decodes.
    public var hasAudio: Bool { audio != nil }

    public init(
        id: ItemID,
        kind: ContentKind,
        pashto: String,
        translit: String,
        pronunciation: String,
        en: String?,
        verification: Verification,
        enAlt: [String]? = nil,
        usage: String? = nil,
        pronunciationNote: String? = nil,
        responseTo: ItemID? = nil,
        tokens: [String]? = nil,
        acceptedOrders: [[Int]]? = nil,
        audio: AudioRef? = nil,
        name: String? = nil,
        forms: LetterForms? = nil,
        sound: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.pashto = pashto
        self.translit = translit
        self.pronunciation = pronunciation
        self.en = en
        self.enAlt = enAlt
        self.usage = usage
        self.pronunciationNote = pronunciationNote
        self.responseTo = responseTo
        self.tokens = tokens
        self.acceptedOrders = acceptedOrders
        self.audio = audio
        self.verification = verification
        self.name = name
        self.forms = forms
        self.sound = sound
    }

    public init(from decoder: Decoder) throws {
        let container = try StrictJSON.container(from: decoder, keyedBy: CodingKeys.self)
        id = try StrictJSON.decode(ItemID.self, forKey: CodingKeys.id, from: container)
        kind = try StrictJSON.decode(ContentKind.self, forKey: CodingKeys.kind, from: container)
        pashto = try StrictJSON.decode(String.self, forKey: CodingKeys.pashto, from: container)
        translit = try StrictJSON.decode(String.self, forKey: CodingKeys.translit, from: container)
        pronunciation = try StrictJSON.decode(String.self, forKey: CodingKeys.pronunciation, from: container)
        en = try StrictJSON.decodeIfPresent(String.self, forKey: CodingKeys.en, from: container)
        enAlt = try StrictJSON.decodeIfPresent([String].self, forKey: CodingKeys.enAlt, from: container)
        usage = try StrictJSON.decodeIfPresent(String.self, forKey: CodingKeys.usage, from: container)
        pronunciationNote = try StrictJSON.decodeIfPresent(String.self, forKey: CodingKeys.pronunciationNote, from: container)
        responseTo = try StrictJSON.decodeIfPresent(ItemID.self, forKey: CodingKeys.responseTo, from: container)
        tokens = try StrictJSON.decodeIfPresent([String].self, forKey: CodingKeys.tokens, from: container)
        acceptedOrders = try StrictJSON.decodeIfPresent([[Int]].self, forKey: CodingKeys.acceptedOrders, from: container)
        audio = try StrictJSON.decodeIfPresent(AudioRef.self, forKey: CodingKeys.audio, from: container)
        verification = try StrictJSON.decode(Verification.self, forKey: CodingKeys.verification, from: container)
        name = try StrictJSON.decodeIfPresent(String.self, forKey: CodingKeys.name, from: container)
        forms = try StrictJSON.decodeIfPresent(LetterForms.self, forKey: CodingKeys.forms, from: container)
        sound = try StrictJSON.decodeIfPresent(String.self, forKey: CodingKeys.sound, from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(pashto, forKey: .pashto)
        try container.encode(translit, forKey: .translit)
        try container.encode(pronunciation, forKey: .pronunciation)
        try container.encodeIfPresent(en, forKey: .en)
        try container.encodeIfPresent(enAlt, forKey: .enAlt)
        try container.encodeIfPresent(usage, forKey: .usage)
        try container.encodeIfPresent(pronunciationNote, forKey: .pronunciationNote)
        try container.encodeIfPresent(responseTo, forKey: .responseTo)
        try container.encodeIfPresent(tokens, forKey: .tokens)
        try container.encodeIfPresent(acceptedOrders, forKey: .acceptedOrders)
        try container.encodeIfPresent(audio, forKey: .audio)
        try container.encode(verification, forKey: .verification)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(forms, forKey: .forms)
        try container.encodeIfPresent(sound, forKey: .sound)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case kind
        case pashto
        case translit
        case pronunciation
        case en
        case enAlt
        case usage
        case pronunciationNote
        case responseTo
        case tokens
        case acceptedOrders
        case audio
        case verification
        case name
        case forms
        case sound
    }
}
