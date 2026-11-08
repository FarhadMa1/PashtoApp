import Foundation

/// Which face of the daily-word card is showing.
public enum DailyWordFace: Equatable, Sendable {
    case front
    case back

    public var other: DailyWordFace {
        switch self {
        case .front: .back
        case .back: .front
        }
    }
}

/// How the daily-word card turns over.
///
/// Motion is a 0.4 s Y-axis turn. Reduce Motion crossfades in 0.2 s and does
/// not rotate, scale, or travel. The quiz card flip is a separate spring.
public enum DailyWordFlip: Equatable, Sendable {
    case rotation
    case crossfade

    public static let rotationDuration: TimeInterval = 0.4
    public static let crossfadeDuration: TimeInterval = QuizMotion.reduceMotionFade

    public static func style(reduceMotion: Bool) -> DailyWordFlip {
        reduceMotion ? .crossfade : .rotation
    }

    public var duration: TimeInterval {
        switch self {
        case .rotation: Self.rotationDuration
        case .crossfade: Self.crossfadeDuration
        }
    }

    public var rotates: Bool { self == .rotation }
    public var scales: Bool { false }
    public var travels: Bool { false }
}

/// One face at rest.
///
/// The back is drawn at -180° while the front is showing, so the meaning is
/// upright when the turn finishes and is not left mirrored. Reduce Motion
/// keeps both angles at 0. Only the active face is accessible. Nothing here
/// posts an announcement or locks input.
public struct DailyWordPresentation: Equatable, Sendable {
    public var face: DailyWordFace
    public var flip: DailyWordFlip

    public init(face: DailyWordFace, reduceMotion: Bool) {
        self.face = face
        self.flip = DailyWordFlip.style(reduceMotion: reduceMotion)
    }

    public var accessibleFace: DailyWordFace { face }
    public var hidesInactiveFace: Bool { true }
    public var postsAnnouncement: Bool { false }
    public var blocksInput: Bool { false }

    public var frontAngle: Double {
        guard flip.rotates else { return 0 }
        return face == .front ? 0 : 180
    }

    /// Counter-rotated while the front is up, so the meaning reads forward after the flip.
    public var backAngle: Double {
        guard flip.rotates else { return 0 }
        return face == .back ? 0 : -180
    }

    public var showsFront: Bool { face == .front }
    public var showsBack: Bool { face == .back }
}

/// True when a Y-axis turn would show the face upright.
///
/// 180° is the mirrored side and stays hidden. The same cut is used while the
/// turn is in progress, so the meaning is not read backwards on the way over.
public enum DailyWordFlipVisibility {
    public static func showsFace(angle: Double) -> Bool {
        var turns = angle.truncatingRemainder(dividingBy: 360)
        if turns < 0 { turns += 360 }
        return turns < 90 || turns > 270
    }
}

/// The card surface. The border is 1 pt in `Lapis.primary`.
public enum DailyWordLayout {
    public static let borderWidth: Double = 1
    public static let cornerRadius: Double = 22
    /// Pronunciation uses the body text colour. The muted track is not text.
    public static let pronunciationUsesBodyText = true
    public static let pronunciationUsesMuted = false
}

/// One side of the daily-word card.
///
/// The front is the Pashto word. Pronunciation sits under it only when the
/// preference already shows pronunciation. The back is the English meaning.
/// Pashto is not repeated there, so the back has no pronunciation line.
public struct DailyWordSide: Equatable, Sendable {
    public var pashto: String?
    public var pronunciation: String?
    public var meaning: String?

    public init(pashto: String?, pronunciation: String?, meaning: String?) {
        self.pashto = pashto
        self.pronunciation = pronunciation
        self.meaning = meaning
    }

    /// A pronunciation line is only present under Pashto.
    public var keepsPronunciationWithPashto: Bool {
        pronunciation == nil || pashto != nil
    }
}

public enum DailyWordFaces {
    public static func sides(of word: DailyWord) -> (front: DailyWordSide, back: DailyWordSide) {
        (
            DailyWordSide(pashto: word.pashto, pronunciation: word.pronunciation, meaning: nil),
            DailyWordSide(pashto: nil, pronunciation: nil, meaning: word.meaning)
        )
    }
}

/// What VoiceOver reads for the face that is showing.
///
/// The other face is not included. Flipping does not add a second sentence.
public enum DailyWordSpeech {
    public static let postsAnnouncement = false

    public static func active(word: DailyWord, face: DailyWordFace) -> String {
        switch face {
        case .front:
            front(pashto: word.pashto, pronunciation: word.pronunciation)
        case .back:
            word.meaning
        }
    }

    public static func front(pashto: String, pronunciation: String?) -> String {
        guard let pronunciation else { return pashto }
        let trimmed = pronunciation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return pashto }
        return "\(pashto), \(pronunciation)"
    }
}
