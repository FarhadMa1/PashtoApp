import Foundation

/// Appearance the learner picks on Profile.
///
/// Stored beside the app, not in the progress file. `system` follows the phone.
public enum AppearanceChoice: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark

    /// Unknown stored text is System, so a bad value does not force a scheme.
    public static func resolved(_ raw: String?) -> AppearanceChoice {
        guard let raw, let choice = AppearanceChoice(rawValue: raw) else { return .system }
        return choice
    }
}

/// Playback speed for clips that already exist.
///
/// Greetings is the only audio today. The Profile label says so.
public enum AudioSpeed: String, CaseIterable, Codable, Sendable {
    case slower
    case normal
    case faster

    /// `AVAudioPlayer.rate`. 1 is the recorded speed.
    public var playbackRate: Double {
        switch self {
        case .slower: 0.75
        case .normal: 1
        case .faster: 1.25
        }
    }

    public static func resolved(_ raw: String?) -> AudioSpeed {
        guard let raw, let speed = AudioSpeed(rawValue: raw) else { return .normal }
        return speed
    }
}

/// One step of the system text-size ladder, from the smallest to the largest.
///
/// The order is the iOS Dynamic Type order. An offset moves along this list.
public enum TextSizeStep: String, CaseIterable, Sendable {
    case xSmall
    case small
    case medium
    case large
    case xLarge
    case xxLarge
    case xxxLarge
    case accessibility1
    case accessibility2
    case accessibility3
    case accessibility4
    case accessibility5
}

/// A small shift on top of the system text size.
///
/// Zero keeps the size the phone already uses. The shift never replaces that
/// size with a fixed one, and it cannot move past either end of the ladder.
public enum TextSizeOffset {
    public static let minimum = -1
    public static let maximum = 1

    public static func clamped(_ raw: Int) -> Int {
        min(maximum, max(minimum, raw))
    }

    public static func shifted(_ step: TextSizeStep, by rawOffset: Int) -> TextSizeStep {
        let steps = TextSizeStep.allCases
        let index = steps.firstIndex(of: step) ?? 0
        let next = index + clamped(rawOffset)
        let bounded = min(steps.count - 1, max(0, next))
        return steps[bounded]
    }
}

/// Profile choices that live outside the progress file.
public struct ProfileSettings: Equatable, Codable, Sendable {
    public var appearance: AppearanceChoice
    public var audioSpeed: AudioSpeed
    public var textSizeOffset: Int

    public static let initial = ProfileSettings(
        appearance: .system,
        audioSpeed: .normal,
        textSizeOffset: 0
    )

    public init(appearance: AppearanceChoice, audioSpeed: AudioSpeed, textSizeOffset: Int) {
        self.appearance = appearance
        self.audioSpeed = audioSpeed
        self.textSizeOffset = TextSizeOffset.clamped(textSizeOffset)
    }
}

/// Reads and writes Profile choices.
///
/// The app uses the same keys with `@AppStorage`. This type is what the tests
/// round-trip. It does not touch lesson progress or `contentVersion`.
public enum ProfileSettingsStore {
    public static let appearanceKey = "profile.appearance"
    public static let audioSpeedKey = "profile.audioSpeed"
    public static let textSizeOffsetKey = "profile.textSizeOffset"

    public static func save(_ settings: ProfileSettings, to defaults: UserDefaults) {
        defaults.set(settings.appearance.rawValue, forKey: appearanceKey)
        defaults.set(settings.audioSpeed.rawValue, forKey: audioSpeedKey)
        defaults.set(TextSizeOffset.clamped(settings.textSizeOffset), forKey: textSizeOffsetKey)
    }

    public static func load(from defaults: UserDefaults) -> ProfileSettings {
        let offset: Int
        if defaults.object(forKey: textSizeOffsetKey) == nil {
            offset = 0
        } else {
            offset = defaults.integer(forKey: textSizeOffsetKey)
        }
        return ProfileSettings(
            appearance: AppearanceChoice.resolved(defaults.string(forKey: appearanceKey)),
            audioSpeed: AudioSpeed.resolved(defaults.string(forKey: audioSpeedKey)),
            textSizeOffset: offset
        )
    }
}

/// What Reset progress does, and the approved 2 Nov confirmation.
///
/// Cancel leaves the snapshot alone. Reset clears learner progress and keeps
/// the daily goal, transliteration, and `contentVersion`. Profile choices are
/// not in the snapshot, so both choices leave them as they were.
public enum ProgressResetChoice: Equatable, Sendable {
    case cancel
    case reset
}

public enum ProgressReset {
    public static func snapshot(
        after choice: ProgressResetChoice,
        from snapshot: ProgressSnapshot
    ) -> ProgressSnapshot {
        switch choice {
        case .cancel:
            return snapshot
        case .reset:
            return ProgressSnapshot(
                snapshotVersion: snapshot.snapshotVersion,
                contentVersion: snapshot.contentVersion,
                cards: [],
                lessonProgress: [],
                streak: .initial,
                settings: UserSettings(
                    dailyGoal: snapshot.settings.dailyGoal,
                    showTransliteration: snapshot.settings.showTransliteration,
                    placementTakenDay: nil
                ),
                activeSession: nil,
                completedSessions: [],
                lastReconciledContentVersion: nil,
                latestObservedDay: nil
            )
        }
    }

    /// Profile appearance, audio speed, and text size are not progress.
    public static func profileSettings(
        after choice: ProgressResetChoice,
        from settings: ProfileSettings
    ) -> ProfileSettings {
        switch choice {
        case .cancel, .reset:
            return settings
        }
    }
}

/// English for the five tabs. VoiceOver reads these words.
public enum TabCopy {
    public static let home = "Home"
    public static let learn = "Learn"
    public static let speak = "Speak"
    public static let practice = "Practice"
    public static let profile = "Profile"

    public static let all = [home, learn, speak, practice, profile]
}

/// Speak has no dialogues yet. The empty state has no button.
public enum SpeakCopy {
    public static let comingSoon = "Coming soon"
}

/// Profile labels. Dialect is only Kabul. There is no empty picker.
public enum ProfileCopy {
    public static let appearance = "Appearance"
    public static let system = "System"
    public static let light = "Light"
    public static let dark = "Dark"
    public static let audioSpeed = "Audio speed"
    public static let slower = "Slower"
    public static let normal = "Normal"
    public static let faster = "Faster"
    public static let audioNote = "Only applies where audio exists."
    public static let textSize = "Text size"
    public static let smaller = "Smaller"
    public static let standard = "Default"
    public static let larger = "Larger"
    public static let textSizeNote = "Adds a small change on top of the iPhone text size."
    public static let dialect = "Dialect"
    public static let kabul = "Kabul"
    public static let moreDialects = "More dialects coming later"
}

/// Reset progress. The dialog reuses the approved 2 Nov Start over copy.
///
/// VoiceOver reads `confirm` and `cancel`. The helper sits under the button.
public enum ProgressResetCopy {
    public static let button = "Reset progress"
    public static let helper = "Asks before anything is deleted."
    public static let title = "Start over?"
    public static let message = "Your lessons, words and streak start from the beginning. Your settings stay the same."
    public static let confirm = "Start over"
    public static let cancel = "Cancel"
}
