import Foundation
import Testing
@testable import PashtoCore

struct StreakMotionTests {
    private let start = LocalDay(year: 2026, month: 1, day: 1)

    @Test func aCoveredDayIsARescueAndASeventhCountedDayEarnsAFreeze() {
        let six = running(days: 6)
        let seventh = streak(six, after: .completedSession, on: start.adding(days: 6))
        #expect(seventh.current == 7)
        #expect(seventh.freezes == 1)
        #expect(StreakMotion.events(before: six, after: seventh) == [
            StreakEventID(kind: .freezeEarned, day: start.adding(days: 6)),
        ])

        let thirteen = running(days: 13)
        let missed = start.adding(days: 13)
        let fourteenth = streak(thirteen, after: .completedSession, on: start.adding(days: 14))
        #expect(fourteenth.freezeUsedDays == [missed])
        #expect(fourteenth.freezes == thirteen.freezes)
        #expect(StreakMotion.events(before: thirteen, after: fourteenth) == [
            StreakEventID(kind: .rescuedDay, day: missed),
            StreakEventID(kind: .freezeEarned, day: start.adding(days: 14)),
        ])

        let twenty = running(days: 20)
        let twentyFirst = streak(twenty, after: .completedSession, on: start.adding(days: 20))
        #expect(twenty.freezes == 2)
        #expect(twentyFirst.freezes == 2)
        #expect(StreakMotion.events(before: twenty, after: twentyFirst).isEmpty)
    }

    @Test func aFreezeThatOnlyCoversADayDoesNotEarnAndAResetDoesNeither() {
        let earned = running(days: 7)
        let before = streak(earned, after: .completedSession, on: start.adding(days: 7))
        #expect(before.freezes == 1)
        let missed = start.adding(days: 8)
        let covered = streak(before, after: .completedSession, on: start.adding(days: 9))
        #expect(covered.freezes == 0)
        #expect(StreakMotion.events(before: before, after: covered) == [
            StreakEventID(kind: .rescuedDay, day: missed),
        ])

        let short = running(days: 3)
        let reset = streak(short, after: .completedSession, on: start.adding(days: 4))
        #expect(reset.current == 1)
        #expect(StreakMotion.events(before: short, after: reset).isEmpty)

        let opened = streak(before, after: .openedApp, on: start.adding(days: 9))
        #expect(StreakMotion.events(before: before, after: opened).isEmpty)
        #expect(StreakMotion.events(before: covered, after: covered).isEmpty)
    }

    @Test func twoCoveredDaysAreTwoRescueIdentities() {
        let before = running(days: 14)
        #expect(before.freezes == 2)
        let firstMissed = start.adding(days: 14)
        let secondMissed = start.adding(days: 15)
        let after = streak(before, after: .completedSession, on: start.adding(days: 16))
        #expect(StreakMotion.events(before: before, after: after) == [
            StreakEventID(kind: .rescuedDay, day: firstMissed),
            StreakEventID(kind: .rescuedDay, day: secondMissed),
        ])
    }

    @Test func aClaimedDayDoesNotReplayOnReentryOrRelaunch() {
        let missed = start.adding(days: 7)
        let earnedDay = start.adding(days: 14)
        let events = [
            StreakEventID(kind: .rescuedDay, day: missed),
            StreakEventID(kind: .freezeEarned, day: earnedDay),
        ]
        var cue = StreakMotionCue()
        cue.stage(events)
        #expect(cue.claim(.rescuedDay) == [StreakEventID(kind: .rescuedDay, day: missed)])
        #expect(cue.claim(.rescuedDay).isEmpty)
        #expect(cue.pending == [StreakEventID(kind: .freezeEarned, day: earnedDay)])
        #expect(cue.claim(.freezeEarned) == [events[1]])
        #expect(cue.claim(.freezeEarned).isEmpty)
        #expect(cue.pending.isEmpty)

        cue.stage(events)
        #expect(cue.pending.isEmpty)
        #expect(cue.claim(.rescuedDay).isEmpty)
        #expect(cue.claim(.freezeEarned).isEmpty)

        var relaunch = StreakMotionCue()
        #expect(relaunch.pending.isEmpty)
        #expect(relaunch.claim(.rescuedDay).isEmpty)
        relaunch.stage(events)
        #expect(relaunch.claim(.rescuedDay) == [StreakEventID(kind: .rescuedDay, day: missed)])
    }

    @Test func rescueAndFreezeStarFollowReduceMotionAndVoiceOver() {
        #expect(StreakMotion.rescueFade == 0.35)
        #expect(StreakMotion.freezeStar == 0.45)
        #expect(RescueMotion.style(reduceMotion: false) == .fade)
        #expect(RescueMotion.style(reduceMotion: true) == .shown)
        #expect(RescueMotion.style(reduceMotion: false).duration == 0.35)
        #expect(RescueMotion.style(reduceMotion: true).duration == 0)

        #expect(FreezeStarMotion.style(reduceMotion: false, voiceOver: false, skipped: false) == .unfold)
        #expect(FreezeStarMotion.style(reduceMotion: true, voiceOver: false, skipped: false) == .final)
        #expect(FreezeStarMotion.style(reduceMotion: false, voiceOver: true, skipped: false) == .final)
        #expect(FreezeStarMotion.style(reduceMotion: false, voiceOver: false, skipped: true) == .final)
        #expect(FreezeStarMotion.style(reduceMotion: false, voiceOver: false, skipped: false).duration == 0.45)
        #expect(FreezeStarMotion.style(reduceMotion: true, voiceOver: true, skipped: true).duration == 0)

        #expect(FreezeStarSpeech.postsAnnouncement == false)
        #expect(FreezeStarSpeech.label(count: 7) == CelebrationCopy.streakSpoken(7))
        #expect(FreezeStarSpeech.label(count: 7) == "7 day streak")
        #expect(FreezeStarSpeech.label(count: 14, dayStreak: "day streak") == "14 day streak")
    }

    private func running(days: Int) -> StreakState {
        var state = StreakState.initial
        for offset in 0..<days {
            state = streak(state, after: .completedSession, on: start.adding(days: offset))
        }
        return state
    }
}
