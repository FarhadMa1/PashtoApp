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

    @Test func rescueFadesAndReduceMotionStaysAShortOpacityFade() {
        #expect(StreakMotion.rescueFade == 0.35)
        #expect(StreakMotion.rescueReduceFade == 0.2)
        #expect(StreakMotion.rescueReduceFade == QuizMotion.reduceMotionFade)
        #expect(RescueMotion.style(reduceMotion: false) == .fade)
        #expect(RescueMotion.style(reduceMotion: true) == .calm)
        #expect(RescueMotion.style(reduceMotion: false).duration == 0.35)
        #expect(RescueMotion.style(reduceMotion: true).duration == 0.2)
        #expect(RescueMotion.style(reduceMotion: false).opacityOnly)
        #expect(RescueMotion.style(reduceMotion: true).opacityOnly)
        #expect(RescueMotion.style(reduceMotion: true).duration > 0)
    }

    @Test func freezeStarUnfoldsHoldsThenLeavesWithinTheCap() {
        let plan = FreezeStarPlan.make(reduceMotion: false, voiceOver: false, skipped: false)
        #expect(plan.phases.map(\.step) == [.unfold, .hold, .settle])
        #expect(plan.phases.map(\.duration) == [
            StreakMotion.freezeStar,
            StreakMotion.freezeHold,
            StreakMotion.freezeDismiss,
        ])
        #expect(plan.phases[0].duration == 0.45)
        #expect(plan.phases[1].duration == 0.70)
        #expect(plan.phases[2].duration == 0.35)
        #expect(abs(plan.duration - 1.5) < 0.000_001)
        #expect(plan.duration <= StreakMotion.freezeMaximum)
        #expect(StreakMotion.freezeMaximum == 1.5)
        #expect(plan.removesOverlay)
        #expect(!plan.opacityOnly)

        let unfold = plan.phases[0]
        #expect(unfold.starts.opacity == 0)
        #expect(unfold.starts.scale == 0.3)
        #expect(unfold.starts.rotationDegrees == -45)
        #expect(!unfold.starts.travels)
        #expect(!unfold.starts.showsGirih)
        #expect(unfold.ends.opacity == 1)
        #expect(unfold.ends.scale == 1)
        #expect(unfold.ends.rotationDegrees == 0)
        #expect(unfold.ends.showsGirih)
        #expect(!unfold.ends.travels)

        let hold = plan.phases[1]
        #expect(hold.starts == hold.ends)
        #expect(hold.ends.showsGirih)
        #expect(!hold.ends.travels)

        let settle = plan.phases[2]
        #expect(settle.ends.opacity == 0)
        #expect(settle.ends.scale < 1)
        #expect(settle.ends.girihOpacity == 0)
        #expect(settle.ends.travels)
        #expect(settle.ends.offsetTowardIcon > 0)
        #expect(settle.ends.rotationDegrees == 0)
    }

    @Test func reduceMotionFadesTheStarInHoldsThenFadesItOut() {
        let plan = FreezeStarPlan.make(reduceMotion: true, voiceOver: false, skipped: false)
        let withVoiceOver = FreezeStarPlan.make(reduceMotion: true, voiceOver: true, skipped: false)
        let movingWithVoiceOver = FreezeStarPlan.make(reduceMotion: false, voiceOver: true, skipped: false)
        #expect(plan == withVoiceOver)
        #expect(movingWithVoiceOver == FreezeStarPlan.make(reduceMotion: false, voiceOver: false, skipped: false))
        #expect(plan.phases.map(\.step) == [.fadeIn, .hold, .fadeOut])
        #expect(plan.phases.map(\.duration) == [0.2, 0.8, 0.2])
        #expect(plan.phases[0].duration == StreakMotion.freezeReduceFade)
        #expect(plan.phases[1].duration == StreakMotion.freezeReduceHold)
        #expect(plan.phases[2].duration == StreakMotion.freezeReduceFade)
        #expect(abs(plan.duration - 1.2) < 0.000_001)
        #expect(plan.duration <= StreakMotion.freezeMaximum)
        #expect(plan.opacityOnly)
        #expect(plan.removesOverlay)

        let fadeIn = plan.phases[0]
        #expect(fadeIn.starts.opacity == 0)
        #expect(fadeIn.ends.opacity == 1)
        #expect(fadeIn.ends.showsGirih)
        #expect(fadeIn.starts.isStill)
        #expect(fadeIn.ends.isStill)

        let fadeOut = plan.phases[2]
        #expect(fadeOut.starts.opacity == 1)
        #expect(fadeOut.ends.opacity == 0)
        #expect(!fadeOut.ends.showsGirih)
        #expect(fadeOut.ends.isStill)
        #expect(!fadeOut.ends.travels)
        #expect(fadeOut.ends.scale == 1)
        #expect(fadeOut.ends.rotationDegrees == 0)
    }

    @Test func skipFinishAndLeaveRemoveTheOverlayAndReentryStaysClear() {
        let skipped = FreezeStarPlan.make(reduceMotion: false, voiceOver: false, skipped: true)
        let skippedCalm = FreezeStarPlan.make(reduceMotion: true, voiceOver: true, skipped: true)
        #expect(skipped == skippedCalm)
        #expect(skipped.phases.map(\.step) == [.gone])
        #expect(skipped.duration == 0)
        #expect(skipped.removesOverlay)
        #expect(skipped.opacityOnly)
        #expect(skipped.phases[0].ends.opacity == 0)

        var playback = FreezeCelebrationPlayback()
        #expect(!playback.visible)
        playback.begin(reduceMotion: false)
        #expect(playback.visible)
        #expect(playback.plan?.removesOverlay == true)
        playback.finish()
        #expect(!playback.visible)

        playback.begin(reduceMotion: true, voiceOver: true)
        #expect(playback.visible)
        #expect(playback.plan?.opacityOnly == true)
        playback.skip()
        #expect(!playback.visible)
        #expect(playback.plan?.duration == 0)
        #expect(playback.plan?.phases.first?.step == .gone)

        playback.begin(reduceMotion: false)
        playback.leave()
        #expect(!playback.visible)
        #expect(playback.plan == nil)

        let reentry = FreezeCelebrationPlayback()
        #expect(!reentry.visible)
        #expect(reentry.plan == nil)

        var cue = StreakMotionCue()
        let earned = StreakEventID(kind: .freezeEarned, day: start.adding(days: 6))
        cue.stage([earned])
        #expect(cue.claim(.freezeEarned) == [earned])
        cue.stage([earned])
        #expect(cue.claim(.freezeEarned).isEmpty)
        #expect(!reentry.visible)
    }

    @Test func freezeStarIsLargerThanTheLessonStarAndLeavesTheCountClear() {
        #expect(FreezeCelebrationLayout.lessonStarSide == 104)
        #expect(FreezeCelebrationLayout.starSide > FreezeCelebrationLayout.lessonStarSide)
        #expect(FreezeCelebrationLayout.starFitsInCard)
        #expect(FreezeCelebrationLayout.cardHeight > FreezeCelebrationLayout.starSide)
        #expect(FreezeCelebrationLayout.streakIconSide == 28)
        #expect(!FreezeCelebrationLayout.hostsStarInStreakIcon)
        #expect(FreezeCelebrationLayout.starSide > FreezeCelebrationLayout.streakIconSide)
        #expect(!FreezeCelebrationLayout.coversStreakLabel)
        #expect(FreezeCelebrationLayout.showsGirih)
        #expect(FreezeCelebrationLayout.outlineUsesRing)
        #expect(FreezeCelebrationLayout.rescueFitsInIcon)
        #expect(FreezeCelebrationLayout.rescueGlyphSide < FreezeCelebrationLayout.rescueBadgeSide)
        #expect(FreezeCelebrationLayout.rescueBadgeSide < FreezeCelebrationLayout.streakIconSide)
    }

    @Test func snowflakeInkOnTheBadgeClearsIconContrastInBothModes() {
        #expect(RescueMark.glyph == QuizResultPalette.badgeInk)
        #expect(RescueMark.backingLight == QuizResultPalette.badgeLight)
        #expect(RescueMark.backingDark == QuizResultPalette.badgeDark)
        #expect(RescueMark.glyph == 0xFAF7F0)
        #expect(RescueMark.backingLight == 0x1E3A8A)
        #expect(RescueMark.backingDark == 0x4666D2)
        #expect(RescueMark.pairs.map(\.minimumRatio) == [3, 3])
        let light = QuizResultPalette.contrastRatio(
            foreground: RescueMark.glyph,
            background: RescueMark.backingLight
        )
        let dark = QuizResultPalette.contrastRatio(
            foreground: RescueMark.glyph,
            background: RescueMark.backingDark
        )
        #expect(light >= 3)
        #expect(dark >= 3)
        #expect(light >= 9)
        #expect(dark >= 4.5)
        for pair in RescueMark.pairs {
            let ratio = QuizResultPalette.contrastRatio(foreground: pair.foreground, background: pair.background)
            #expect(ratio >= pair.minimumRatio)
        }
        let onSaffronLight = QuizResultPalette.contrastRatio(
            foreground: RescueMark.glyph,
            background: RescueMark.saffronLight
        )
        let onSaffronDark = QuizResultPalette.contrastRatio(
            foreground: RescueMark.glyph,
            background: RescueMark.saffronDark
        )
        #expect(onSaffronLight < 3)
        #expect(onSaffronDark < 3)
        #expect(RescueMark.backingLight != RescueMark.saffronLight)
        #expect(RescueMark.backingDark != RescueMark.saffronDark)
    }

    @Test func voiceOverKeepsTheExistingStreakSentence() {
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
