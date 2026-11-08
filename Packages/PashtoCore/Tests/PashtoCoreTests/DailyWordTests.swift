import Foundation
import Testing
@testable import PashtoCore

struct DailyWordTests {
    private let day = LocalDay(year: 2026, month: 11, day: 8)

    @Test func theSameLocalDatePicksTheSameLearnedWord() {
        let bundle = course()
        let cards = [
            ReviewCard.introduced(itemID: itemID("e-b"), on: day),
            ReviewCard.introduced(itemID: itemID("e-a"), on: day.adding(days: -2)),
            ReviewCard.introduced(itemID: itemID("e-c"), on: day, source: .placement),
        ]
        let first = DailyWordSelection.select(
            cards: cards,
            in: bundle,
            releasedUnitIDs: [unitID("u-released")],
            on: day,
            showsPronunciation: true
        )
        let again = DailyWordSelection.select(
            cards: [cards[2], cards[0], cards[1]],
            in: bundle,
            releasedUnitIDs: [unitID("u-released")],
            on: day,
            showsPronunciation: true
        )
        let relaunch = DailyWordSelection.select(
            cards: cards,
            in: bundle,
            releasedUnitIDs: [unitID("u-released")],
            on: LocalDay(year: 2026, month: 11, day: 8),
            showsPronunciation: true
        )
        #expect(first == again)
        #expect(first == relaunch)
        #expect(first?.pronunciation != "scholar-TLIT")
        #expect(first?.pronunciation != nil)
    }

    @Test func selectionUsesOnlyLearnedReleasedVocabulary() {
        let bundle = course()
        let released = [unitID("u-released")]
        let learned = [
            ReviewCard.introduced(itemID: itemID("e-a"), on: day),
            ReviewCard.introduced(itemID: itemID("e-held"), on: day),
            ReviewCard.introduced(itemID: itemID("e-letter"), on: day),
            ReviewCard.introduced(itemID: itemID("e-blank"), on: day),
            ReviewCard.introduced(itemID: itemID("e-hidden"), on: day),
        ]
        let paused = ReviewCard(
            itemID: itemID("e-b"),
            easeFactor: ReviewCard.initialEaseFactor,
            intervalDays: 0,
            repetitions: 0,
            lapses: 0,
            dueDay: day,
            lastReviewedDay: nil,
            createdDay: day,
            state: .paused,
            source: .lesson
        )
        let picked = DailyWordSelection.select(
            cards: learned + [paused],
            in: bundle,
            releasedUnitIDs: released,
            on: day,
            showsPronunciation: true
        )
        let allowed: Set<String> = ["e-a", "e-b"]
        #expect(allowed.contains(picked?.itemID.rawValue ?? ""))
        #expect(picked?.itemID.rawValue != "e-held")
        #expect(picked?.itemID.rawValue != "e-letter")
        #expect(picked?.itemID.rawValue != "e-blank")
        #expect(picked?.itemID.rawValue != "e-hidden")
        #expect(picked?.itemID.rawValue != "e-sound")
        let dialog = DailyWordSelection.select(
            cards: [ReviewCard.introduced(itemID: itemID("e-dialog"), on: day)],
            in: bundle,
            releasedUnitIDs: released,
            on: day,
            showsPronunciation: true
        )
        #expect(dialog?.itemID.rawValue == "e-dialog")
        #expect(dialog?.meaning == "yes")
        #expect(dialog?.pronunciation == "ho")
        let phrase = DailyWordSelection.select(
            cards: [ReviewCard.introduced(itemID: itemID("e-c"), on: day)],
            in: bundle,
            releasedUnitIDs: released,
            on: day,
            showsPronunciation: true
        )
        #expect(phrase?.itemID.rawValue == "e-c")
        #expect(phrase?.meaning == "three")
        #expect(phrase?.pronunciation == "dre")

        for offset in 0..<40 {
            let word = DailyWordSelection.select(
                cards: learned + [paused],
                in: bundle,
                releasedUnitIDs: released,
                on: day.adding(days: offset),
                showsPronunciation: true
            )
            #expect(allowed.contains(word?.itemID.rawValue ?? ""))
        }
    }

    @Test func anUnlearnedWordNeverBecomesTheDailyWord() {
        let bundle = course()
        let onlyUnlearnedNeighbor = [
            ReviewCard.introduced(itemID: itemID("e-a"), on: day),
        ]
        for offset in 0..<12 {
            let word = DailyWordSelection.select(
                cards: onlyUnlearnedNeighbor,
                in: bundle,
                releasedUnitIDs: [unitID("u-released")],
                on: day.adding(days: offset),
                showsPronunciation: true
            )
            #expect(word?.itemID.rawValue == "e-a")
        }
        let none = DailyWordSelection.select(
            cards: [],
            in: bundle,
            releasedUnitIDs: [unitID("u-released")],
            on: day,
            showsPronunciation: true
        )
        #expect(none == nil)
    }

    @Test func noEligibleWordOmitsTheCard() {
        let bundle = course()
        let released = [unitID("u-released")]
        #expect(DailyWordSelection.select(
            cards: [],
            in: bundle,
            releasedUnitIDs: released,
            on: day,
            showsPronunciation: true
        ) == nil)
        #expect(DailyWordSelection.select(
            cards: [ReviewCard.introduced(itemID: itemID("e-letter"), on: day)],
            in: bundle,
            releasedUnitIDs: released,
            on: day,
            showsPronunciation: true
        ) == nil)
        #expect(DailyWordSelection.select(
            cards: [ReviewCard.introduced(itemID: itemID("e-blank"), on: day)],
            in: bundle,
            releasedUnitIDs: released,
            on: day,
            showsPronunciation: true
        ) == nil)
        #expect(DailyWordSelection.select(
            cards: [ReviewCard.introduced(itemID: itemID("e-hidden"), on: day)],
            in: bundle,
            releasedUnitIDs: released,
            on: day,
            showsPronunciation: true
        ) == nil)
        #expect(DailyWordSelection.select(
            cards: [ReviewCard.introduced(itemID: itemID("e-a"), on: day)],
            in: bundle,
            releasedUnitIDs: [],
            on: day,
            showsPronunciation: true
        ) == nil)
        #expect(DailyWordSelection.select(
            cards: [ReviewCard.introduced(itemID: itemID("e-a"), on: day)],
            in: bundle,
            releasedUnitIDs: [unitID("u-draft")],
            on: day,
            showsPronunciation: true
        ) == nil)
    }

    @Test func localCalendarBoundariesStayOnTheCivilDate() {
        let bundle = manyWords(count: 24)
        let cards = (1...24).map { ReviewCard.introduced(itemID: itemID("e-w\($0)"), on: day) }
        let released = [unitID("u-words")]

        let yearEnd = LocalDay(year: 2026, month: 12, day: 31)
        let yearStart = LocalDay(year: 2027, month: 1, day: 1)
        let monthEnd = LocalDay(year: 2026, month: 1, day: 31)
        let monthStart = LocalDay(year: 2026, month: 2, day: 1)
        let leapEve = LocalDay(year: 2024, month: 2, day: 28)
        let leapDay = LocalDay(year: 2024, month: 2, day: 29)
        let afterLeap = LocalDay(year: 2024, month: 3, day: 1)
        let commonEve = LocalDay(year: 2025, month: 2, day: 28)
        let afterCommon = LocalDay(year: 2025, month: 3, day: 1)

        #expect(DailyWordSelection.dayKey(yearEnd) != DailyWordSelection.dayKey(yearStart))
        #expect(DailyWordSelection.dayKey(monthEnd) != DailyWordSelection.dayKey(monthStart))
        #expect(DailyWordSelection.dayKey(leapEve) != DailyWordSelection.dayKey(leapDay))
        #expect(DailyWordSelection.dayKey(leapDay) != DailyWordSelection.dayKey(afterLeap))
        #expect(DailyWordSelection.dayKey(commonEve) != DailyWordSelection.dayKey(afterCommon))
        #expect(DailyWordSelection.index(on: yearEnd, count: 24) != DailyWordSelection.index(on: yearStart, count: 24))
        #expect(DailyWordSelection.index(on: leapEve, count: 24) != DailyWordSelection.index(on: leapDay, count: 24))

        let endWord = select(cards, bundle, released, yearEnd)
        let startWord = select(cards, bundle, released, yearStart)
        #expect(endWord != startWord)
        #expect(select(cards, bundle, released, yearEnd) == endWord)
        #expect(select(cards, bundle, released, yearStart) == startWord)

        var oslo = Calendar(identifier: .gregorian)
        oslo.timeZone = TimeZone(secondsFromGMT: 3600)!
        oslo.locale = Locale(identifier: "en_US_POSIX")
        let morning = oslo.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 0, minute: 30))!
        let evening = oslo.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 23, minute: 30))!
        let osloMorning = LocalDay(date: morning, timeZone: oslo.timeZone)
        let osloEvening = LocalDay(date: evening, timeZone: oslo.timeZone)
        let losAngeles = LocalDay(date: morning, timeZone: TimeZone(secondsFromGMT: -8 * 3600)!)
        #expect(osloMorning == osloEvening)
        #expect(osloMorning == day)
        #expect(losAngeles == LocalDay(year: 2026, month: 11, day: 7))
        #expect(select(cards, bundle, released, osloMorning) == select(cards, bundle, released, osloEvening))
        #expect(select(cards, bundle, released, osloMorning) != select(cards, bundle, released, losAngeles))
    }

    @Test func pronunciationFollowsTheExistingPreferenceAndNeverUsesTranslit() throws {
        let bundle = course()
        let cards = [ReviewCard.introduced(itemID: itemID("e-a"), on: day)]
        let shown = try #require(DailyWordSelection.select(
            cards: cards,
            in: bundle,
            releasedUnitIDs: [unitID("u-released")],
            on: day,
            showsPronunciation: true
        ))
        let hidden = try #require(DailyWordSelection.select(
            cards: cards,
            in: bundle,
            releasedUnitIDs: [unitID("u-released")],
            on: day,
            showsPronunciation: false
        ))
        #expect(shown.itemID == hidden.itemID)
        #expect(shown.pronunciation == "aa")
        #expect(shown.pronunciation != "scholar-TLIT")
        #expect(hidden.pronunciation == nil)
        let item = try #require(bundle.items.first { $0.id == itemID("e-a") })
        #expect(QuizPresentation.spokenPronunciation(text: item.pashto, item: item, showsPronunciation: true) == "aa")
        #expect(QuizPresentation.spokenPronunciation(text: item.pashto, item: item, showsPronunciation: false) == nil)
        #expect(QuizPresentation.spokenPronunciation(text: item.pashto, item: item, showsPronunciation: true) != item.translit)
        #expect(QuizPresentation.tilePronunciation("aa", showsPronunciation: false) == nil)
        #expect(QuizPresentation.tilePronunciation("aa", showsPronunciation: true) == "aa")
        #expect(UserSettings.initial.showTransliteration == true)
    }

    @Test func facesKeepPronunciationUnderPashtoAndSpeakOnlyTheActiveSide() throws {
        let word = DailyWord(itemID: itemID("e-a"), pashto: "ا", pronunciation: "aa", meaning: "one")
        let hidden = DailyWord(itemID: itemID("e-a"), pashto: "ا", pronunciation: nil, meaning: "one")
        let sides = DailyWordFaces.sides(of: word)
        let quiet = DailyWordFaces.sides(of: hidden)
        #expect(sides.front.pashto == "ا")
        #expect(sides.front.pronunciation == "aa")
        #expect(sides.front.meaning == nil)
        #expect(sides.back.pashto == nil)
        #expect(sides.back.pronunciation == nil)
        #expect(sides.back.meaning == "one")
        #expect(sides.front.keepsPronunciationWithPashto)
        #expect(sides.back.keepsPronunciationWithPashto)
        #expect(quiet.front.pronunciation == nil)
        #expect(quiet.back.pronunciation == nil)
        #expect(DailyWordSpeech.active(word: word, face: .front) == "ا, aa")
        #expect(DailyWordSpeech.active(word: hidden, face: .front) == "ا")
        #expect(DailyWordSpeech.active(word: word, face: .back) == "one")
        #expect(!DailyWordSpeech.active(word: word, face: .back).contains("ا"))
        #expect(!DailyWordSpeech.active(word: word, face: .front).contains("one"))
        #expect(DailyWordSpeech.postsAnnouncement == false)
    }

    @Test func flipIsPointFourSecondsAndReduceMotionDoesNotMove() {
        #expect(DailyWordFlip.rotationDuration == 0.4)
        #expect(DailyWordFlip.crossfadeDuration == 0.2)
        #expect(DailyWordFlip.crossfadeDuration == QuizMotion.reduceMotionFade)
        #expect(QuizMotion.cardFlip == 0.4)
        #expect(CardFlip.style(reduceMotion: false) == .rotation)
        #expect(CardFlip.style(reduceMotion: true) == .fade)

        let turning = DailyWordPresentation(face: .front, reduceMotion: false)
        #expect(turning.flip == .rotation)
        #expect(turning.flip.duration == 0.4)
        #expect(turning.flip.rotates)
        #expect(!turning.flip.scales)
        #expect(!turning.flip.travels)
        #expect(turning.frontAngle == 0)
        #expect(turning.backAngle == -180)
        #expect(turning.accessibleFace == .front)
        #expect(turning.hidesInactiveFace)
        #expect(!turning.postsAnnouncement)
        #expect(!turning.blocksInput)
        #expect(DailyWordFlipVisibility.showsFace(angle: turning.frontAngle))
        #expect(!DailyWordFlipVisibility.showsFace(angle: turning.backAngle))
        #expect(!DailyWordFlipVisibility.showsFace(angle: 180))
        #expect(!DailyWordFlipVisibility.showsFace(angle: 90))
        #expect(!DailyWordFlipVisibility.showsFace(angle: 270))

        let meaning = DailyWordPresentation(face: .back, reduceMotion: false)
        #expect(meaning.backAngle == 0)
        #expect(meaning.frontAngle == 180)
        #expect(DailyWordFlipVisibility.showsFace(angle: meaning.backAngle))
        #expect(!DailyWordFlipVisibility.showsFace(angle: meaning.frontAngle))
        #expect(meaning.accessibleFace == .back)

        let calm = DailyWordPresentation(face: .back, reduceMotion: true)
        #expect(calm.flip == .crossfade)
        #expect(calm.flip.duration == 0.2)
        #expect(!calm.flip.rotates)
        #expect(!calm.flip.scales)
        #expect(!calm.flip.travels)
        #expect(calm.frontAngle == 0)
        #expect(calm.backAngle == 0)
        #expect(calm.showsBack)
        #expect(!calm.showsFront)
        #expect(calm.accessibleFace == .back)
        #expect(!calm.postsAnnouncement)
        #expect(!calm.blocksInput)

        let calmFront = DailyWordPresentation(face: .front, reduceMotion: true)
        #expect(calmFront.frontAngle == 0)
        #expect(calmFront.backAngle == 0)
        #expect(calmFront.showsFront)
        #expect(!calmFront.showsBack)
    }

    @Test func layoutUsesAOnePointPrimaryBorderAndBodyTextForPronunciation() {
        #expect(DailyWordLayout.borderWidth == 1)
        #expect(DailyWordLayout.pronunciationUsesBodyText)
        #expect(!DailyWordLayout.pronunciationUsesMuted)
        #expect(DailyWordCopy.title == "Word of the day")
        #expect(DailyWordCopy.showMeaning == "Show meaning")
        let mutedOnPage = QuizResultPalette.contrastRatio(
            foreground: QuizResultPalette.muted,
            background: QuizResultPalette.pageLight
        )
        #expect(mutedOnPage < 4.5)
        let textOnPage = QuizResultPalette.contrastRatio(
            foreground: 0x111827,
            background: QuizResultPalette.pageLight
        )
        let textOnDark = QuizResultPalette.contrastRatio(
            foreground: 0xF1F5F9,
            background: QuizResultPalette.pageDark
        )
        #expect(textOnPage >= 4.5)
        #expect(textOnDark >= 4.5)
    }

    @Test func theHomeKeepsTheApprovedFreezeAndDailyWordCopy() throws {
        let root = repoRoot()
        let screen = try String(contentsOf: root.appendingPathComponent("PashtoApp/ContentView.swift"), encoding: .utf8)
        let quiz = try String(contentsOf: root.appendingPathComponent("PashtoApp/Quiz/QuizScreen.swift"), encoding: .utf8)
        let model = try String(contentsOf: root.appendingPathComponent("PashtoApp/Launch/AppModel.swift"), encoding: .utf8)
        let lapis = try String(contentsOf: root.appendingPathComponent("PashtoApp/Design/LapisStyle.swift"), encoding: .utf8)

        let celebration = try section("private struct FreezeEarnedCelebration", until: "private struct StreakStarPulse", in: screen)
        #expect(celebration.contains("ApprovedCopy.streakFreezeEarned"))
        #expect(celebration.contains("FreezeStarSpeech.label"))
        #expect(celebration.contains("didFocusFreeze"))
        #expect(celebration.contains("accessibilityFocused"))
        #expect(celebration.contains("guard plan.removesOverlay else { return }"))
        #expect(screen.contains("onDisappear { freezeCelebration = false }"))
        #expect(!celebration.contains("sensoryFeedback"))
        #expect(!celebration.contains("AccessibilityNotification"))
        #expect(!celebration.contains(".disabled("))
        #expect(celebration.contains("Lapis.badgeInk"))
        #expect(screen.contains("CelebrationCopy.streakSpoken(count, label: ApprovedCopy.dayStreak)"))
        #expect(screen.contains("if let dailyWord"))
        #expect(!screen.contains("No words"))
        #expect(!screen.contains("Nothing learned"))

        let card = try section("private struct DailyWordCard", until: "private struct DailyWordSpin", in: screen)
        #expect(card.contains("ApprovedCopy.wordOfTheDay"))
        #expect(card.contains("ApprovedCopy.showMeaning"))
        #expect(card.contains("Lapis.primary"))
        #expect(card.contains("DailyWordLayout.borderWidth"))
        #expect(card.contains("pronunciationColor: Lapis.text"))
        #expect(card.contains("Lapis.background"))
        #expect(!card.contains("Lapis.muted"))
        #expect(!card.contains("Lapis.secondaryText"))
        #expect(card.contains("allowsHitTesting(presentation.showsBack)"))
        #expect(card.contains("DailyWordSpeech.active"))
        #expect(!card.contains(".disabled("))

        let spin = try section("private struct DailyWordSpin", until: "/// Catalog strings for the celebration", in: screen)
        #expect(spin.contains("rotation3DEffect"))
        #expect(spin.contains("DailyWordFlipVisibility.showsFace"))
        #expect(spin.contains("accessibilityHidden(!visible)"))
        #expect(!spin.contains(".scaleEffect"))
        #expect(!spin.contains(".offset"))

        #expect(quiz.contains("if session.isComplete {\n            onFinish(session)"))
        #expect(quiz.contains("onAnswer(session)"))
        #expect(screen.contains("onFinish: { celebration = $0; finishSession($0) }"))
        #expect(screen.contains("LessonFinishedView(session: celebration) {\n                self.celebration = nil\n            }"))
        #expect(model.contains("Called when the last answer is given. Continue does not call this"))
        #expect(model.contains("showsPronunciation: progress.settings.showTransliteration"))
        #expect(model.contains("showsPronunciation: snapshot.settings.showTransliteration"))

        #expect(lapis.contains("static let heroTop = color(0x2747A6)"))
        #expect(lapis.contains("static let heroMiddle = color(0x1E3A8A)"))
        #expect(lapis.contains("static let heroBottom = color(0x152B6B)"))
        for background in [UInt32(0x2747A6), 0x1E3A8A, 0x152B6B] {
            let ratio = QuizResultPalette.contrastRatio(
                foreground: QuizResultPalette.badgeInk,
                background: background
            )
            #expect(ratio >= 4.5)
        }
    }

    private func select(
        _ cards: [ReviewCard],
        _ bundle: ContentBundle,
        _ released: [UnitID],
        _ day: LocalDay
    ) -> ItemID? {
        DailyWordSelection.select(
            cards: cards,
            in: bundle,
            releasedUnitIDs: released,
            on: day,
            showsPronunciation: true
        )?.itemID
    }

    private func course() -> ContentBundle {
        let items = [
            makeItem("e-a", pashto: "ا", translit: "scholar-TLIT", pronunciation: "aa", en: "one"),
            makeItem("e-b", pashto: "ب", translit: "scholar-B", pronunciation: "ba", en: "two"),
            makeItem("e-c", kind: .phrase, pashto: "درې", translit: "scholar-C", pronunciation: "dre", en: "three"),
            makeItem("e-held", pashto: "څلور", translit: "scholar-D", pronunciation: "tsa-LOOR", en: "four"),
            makeItem("e-letter", kind: .letter, pashto: "د", translit: "d", pronunciation: "d", en: "dal"),
            makeItem("e-blank", pashto: "ه", translit: "h", pronunciation: "h", en: "   "),
            makeItem("e-sound", pashto: "و", translit: "w", pronunciation: "w", en: "and"),
            makeItem("e-dialog", kind: .dialogLine, pashto: "هو", translit: "scholar-H", pronunciation: "ho", en: "yes"),
        ]
        let releasedLesson = Lesson(
            id: lessonID("l-one"),
            title: "One",
            items: [
                LessonItemRef(item: itemID("e-a"), role: .introduce),
                LessonItemRef(item: itemID("e-b"), role: .introduce),
                LessonItemRef(item: itemID("e-c"), role: .introduce),
                LessonItemRef(item: itemID("e-letter"), role: .introduce),
                LessonItemRef(item: itemID("e-blank"), role: .introduce),
                LessonItemRef(item: itemID("e-sound"), role: .soundExample, sound: "w"),
                LessonItemRef(item: itemID("e-dialog"), role: .introduce),
            ],
            letters: [itemID("e-letter")]
        )
        let draftLesson = Lesson(
            id: lessonID("l-draft"),
            title: "Draft",
            items: [
                LessonItemRef(item: itemID("e-held"), role: .introduce),
            ]
        )
        return makeBundle(
            items: items,
            units: [
                CourseUnit(id: unitID("u-released"), track: "main", title: "Released", lessons: [releasedLesson]),
                CourseUnit(id: unitID("u-draft"), track: "main", title: "Draft", lessons: [draftLesson]),
            ]
        )
    }

    private func manyWords(count: Int) -> ContentBundle {
        var items: [ContentItem] = []
        var refs: [LessonItemRef] = []
        for number in 1...count {
            let id = "e-w\(number)"
            items.append(makeItem(id, pashto: "و", translit: "w\(number)", pronunciation: "w\(number)", en: "word \(number)"))
            refs.append(LessonItemRef(item: itemID(id), role: .introduce))
        }
        let lesson = Lesson(id: lessonID("l-words"), title: "Words", items: refs)
        return makeBundle(
            items: items,
            units: [CourseUnit(id: unitID("u-words"), track: "main", title: "Words", lessons: [lesson])]
        )
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func section(_ start: String, until end: String, in source: String) throws -> String {
        let lower = try #require(source.range(of: start))
        let upper = try #require(source.range(of: end, range: lower.upperBound..<source.endIndex))
        return String(source[lower.lowerBound..<upper.lowerBound])
    }
}
