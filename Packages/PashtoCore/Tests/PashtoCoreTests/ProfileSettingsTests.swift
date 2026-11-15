import Foundation
import Testing
import PashtoCore

struct ProfileSettingsTests {
    @Test func settingsRoundTripAndIgnoreUnknownValues() {
        let suite = "pashto.profile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ProfileSettingsStore.load(from: defaults) == .initial)

        let saved = ProfileSettings(appearance: .dark, audioSpeed: .slower, textSizeOffset: 1)
        ProfileSettingsStore.save(saved, to: defaults)
        #expect(ProfileSettingsStore.load(from: defaults) == saved)

        defaults.set("nope", forKey: ProfileSettingsStore.appearanceKey)
        defaults.set("nope", forKey: ProfileSettingsStore.audioSpeedKey)
        defaults.set(9, forKey: ProfileSettingsStore.textSizeOffsetKey)
        let fallback = ProfileSettingsStore.load(from: defaults)
        #expect(fallback.appearance == .system)
        #expect(fallback.audioSpeed == .normal)
        #expect(fallback.textSizeOffset == TextSizeOffset.maximum)

        defaults.set(-4, forKey: ProfileSettingsStore.textSizeOffsetKey)
        #expect(ProfileSettingsStore.load(from: defaults).textSizeOffset == TextSizeOffset.minimum)
    }

    @Test func textSizeOffsetMovesAlongTheSystemLadder() {
        #expect(TextSizeOffset.shifted(.large, by: 0) == .large)
        #expect(TextSizeOffset.shifted(.large, by: 1) == .xLarge)
        #expect(TextSizeOffset.shifted(.large, by: -1) == .medium)
        #expect(TextSizeOffset.shifted(.accessibility5, by: 1) == .accessibility5)
        #expect(TextSizeOffset.shifted(.xSmall, by: -1) == .xSmall)
        #expect(TextSizeOffset.shifted(.xxxLarge, by: 4) == .accessibility1)
        #expect(TextSizeOffset.clamped(0) == 0)
        #expect(TextSizeStep.allCases.first == .xSmall)
        #expect(TextSizeStep.allCases.last == .accessibility5)
    }

    @Test func audioSpeedRatesStayOnTheThreeSteps() {
        #expect(AudioSpeed.slower.playbackRate == 0.75)
        #expect(AudioSpeed.normal.playbackRate == 1)
        #expect(AudioSpeed.faster.playbackRate == 1.25)
        #expect(AudioSpeed.resolved(nil) == .normal)
        #expect(AudioSpeed.resolved(AudioSpeed.faster.rawValue) == .faster)
    }

    @Test func cancelKeepsProgressAndResetClearsOnlyProgress() async throws {
        let day = LocalDay(year: 2026, month: 11, day: 2)
        let store = InMemoryProgressStore(contentVersion: "2026.11.0")
        try await store.updateSettings(UserSettings(
            dailyGoal: .light,
            showTransliteration: false,
            placementTakenDay: day
        ))
        let item = try #require(ItemID(rawValue: "e-salam"))
        try await store.applyReconciliation([ReviewCard.introduced(itemID: item, on: day)])
        let before = try await store.load()
        #expect(before.cards.count == 1)
        #expect(before.settings.placementTakenDay == day)
        #expect(before.contentVersion == "2026.11.0")

        #expect(ProgressReset.snapshot(after: .cancel, from: before) == before)
        let loadedAfterCancel = try await store.load()
        #expect(loadedAfterCancel == before)

        let decided = ProgressReset.snapshot(after: .reset, from: before)
        try await store.resetAll()
        let after = try await store.load()
        #expect(after == decided)
        #expect(after.contentVersion == before.contentVersion)
        #expect(after.settings.dailyGoal == .light)
        #expect(after.settings.showTransliteration == false)
        #expect(after.settings.placementTakenDay == nil)
        #expect(after.cards.isEmpty)
        #expect(after.lessonProgress.isEmpty)
        #expect(after.streak == .initial)
        #expect(after.activeSession == nil)
        #expect(after.completedSessions.isEmpty)
        #expect(after.snapshotVersion == before.snapshotVersion)
    }

    @Test func resetLeavesProfileSettingsAndTheDialogNamesBothButtons() {
        let suite = "pashto.profile.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ProfileSettings(appearance: .light, audioSpeed: .faster, textSizeOffset: -1)
        ProfileSettingsStore.save(settings, to: defaults)

        let kept = ProgressReset.profileSettings(after: .reset, from: settings)
        #expect(kept == settings)
        #expect(ProgressReset.profileSettings(after: .cancel, from: settings) == settings)
        #expect(ProfileSettingsStore.load(from: defaults) == settings)

        #expect(ProgressResetCopy.confirm != ProgressResetCopy.cancel)
        #expect(!ProgressResetCopy.confirm.isEmpty)
        #expect(!ProgressResetCopy.cancel.isEmpty)
        #expect(ProgressResetCopy.title == "Start over?")
        #expect(ProgressResetCopy.message == "Your lessons, words and streak start from the beginning. Your settings stay the same.")
        #expect(ProgressResetCopy.confirm == "Start over")
        #expect(ProgressResetCopy.cancel == "Cancel")
        #expect(ProgressResetCopy.helper == "Asks before anything is deleted.")
        #expect(ProgressResetCopy.button == "Reset progress")
    }

    @Test func profileAndTabCopyStayInEnglish() {
        let lines = TabCopy.all + [
            SpeakCopy.comingSoon,
            ProfileCopy.appearance,
            ProfileCopy.system,
            ProfileCopy.light,
            ProfileCopy.dark,
            ProfileCopy.audioSpeed,
            ProfileCopy.slower,
            ProfileCopy.normal,
            ProfileCopy.faster,
            ProfileCopy.audioNote,
            ProfileCopy.textSize,
            ProfileCopy.smaller,
            ProfileCopy.standard,
            ProfileCopy.larger,
            ProfileCopy.textSizeNote,
            ProfileCopy.dialect,
            ProfileCopy.kabul,
            ProfileCopy.moreDialects,
            ProgressResetCopy.button,
            ProgressResetCopy.helper,
            ProgressResetCopy.title,
            ProgressResetCopy.message,
            ProgressResetCopy.confirm,
            ProgressResetCopy.cancel,
        ]
        let banned = ["æ", "ø", "å", "Æ", "Ø", "Å", "Bekreftet", "Innstillinger", "Søk"]
        for line in lines {
            #expect(!line.isEmpty)
            for marker in banned where line.contains(marker) {
                Issue.record("\(line) contains \(marker)")
            }
        }
        #expect(TabCopy.all == ["Home", "Learn", "Speak", "Practice", "Profile"])
        #expect(ProfileCopy.kabul == "Kabul")
        #expect(ProfileCopy.moreDialects == "More dialects coming later")
        #expect(SpeakCopy.comingSoon == "Coming soon")
        #expect(!lines.contains { $0.contains("Eastern") })
    }
}

struct WordBreakPolicyTests {
    @Test func wordsBreakOnlyAtSpacesAndHyphensStayInsideTheWord() {
        let shown = WordBreakPolicy.display("cha-haar shan-BA")
        #expect(WordBreakPolicy.strippingJoiners(shown) == "cha-haar shan-BA")
        let parts = shown.split(separator: " ", omittingEmptySubsequences: false)
        #expect(parts.count == 2)
        #expect(parts[0].contains("-"))
        #expect(parts[0].contains(WordBreakPolicy.wordJoiner))
        #expect(!parts[0].contains(" "))
        #expect(parts[1].contains(WordBreakPolicy.wordJoiner))
        #expect(!shown.contains("\u{2011}"))

        let pashto = WordBreakPolicy.display("څه غواړې")
        #expect(WordBreakPolicy.strippingJoiners(pashto) == "څه غواړې")
        #expect(pashto.split(separator: " ").count == 2)
        #expect(pashto.contains(WordBreakPolicy.wordJoiner))
    }
}
