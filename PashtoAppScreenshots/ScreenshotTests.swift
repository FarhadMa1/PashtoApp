import XCTest

/// Opens the home, the lower Home rows, a Numbers learn list and its cards,
/// the Greetings and Travel learn lists, the Family screens, a quiz, the
/// celebration, and the word of the day. Light also opens the Greetings list
/// with Bold Text. XL is two tests, lists and then the quiz, so each stays
/// under the runner's per-test limit. The Time days list is part of XL lists.
/// The quiz test also opens the longest unit 4–8 pronunciation note.
@MainActor
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        // The workflow default is 180 seconds, and the allowance is fixed
        // before the test body runs. The two XL tests request 400.
        if name.contains("testXL") {
            executionTimeAllowance = 400
        }
    }

    func testLight() {
        capture(variant: "light")
    }

    func testDark() {
        capture(variant: "dark")
    }

    /// Home, Numbers, Greetings, Travel, and the Time days list.
    func testXLLists() {
        executionTimeAllowance = 400
        let app = XCUIApplication()
        let basics = showHome(app, variant: "xl", failure: "home did not load. buttons: \(buttonDump(app))")
        captureHomeAndNumbers(app, variant: "xl")
        app.terminate()
        showHome(app, variant: "xl", failure: "home did not return. buttons: \(buttonDump(app))")
        captureGreetingsAndTravel(app, variant: "xl", basics: basics)
        captureTimeDays(app, basics: basics)
    }

    /// Family, the learn card, the quiz, the celebration, the word of the day,
    /// and the longest unit 4–8 pronunciation note.
    func testXLQuiz() {
        executionTimeAllowance = 400
        let app = XCUIApplication()
        showHome(app, variant: "xl", failure: "home did not load. buttons: \(buttonDump(app))")
        captureFamilyLearnAndQuiz(app, variant: "xl")
        captureCelebration(app, variant: "xl")
        captureDailyWord(app, variant: "xl")
        captureLongNote(app)
    }

    private func capture(variant: String) {
        let app = XCUIApplication()
        let basics = showHome(app, variant: variant, failure: "home did not load. buttons: \(buttonDump(app))")
        captureHomeAndNumbers(app, variant: variant)
        app.terminate()
        showHome(app, variant: variant, failure: "home did not return. buttons: \(buttonDump(app))")
        captureGreetingsAndTravel(app, variant: variant, basics: basics)
        captureFamilyLearnAndQuiz(app, variant: variant)
        captureCelebration(app, variant: variant)
        captureDailyWord(app, variant: variant)
        captureBoldText(app, variant: variant, basics: basics)
    }

    /// `failure` is built only if home does not appear. The call sites include
    /// `buttonDump(app)`, which crashes if it runs before `launch`.
    @discardableResult
    private func showHome(
        _ app: XCUIApplication,
        variant: String,
        failure: @autoclosure () -> String
    ) -> XCUIElement {
        app.launchArguments = launchArguments(for: variant)
        app.launch()
        let basics = app.descendants(matching: .any)["u-basics"]
        if !basics.waitForExistence(timeout: 20), app.buttons["Start review"].exists {
            app.buttons["Start review"].tap()
        }
        XCTAssertTrue(basics.waitForExistence(timeout: 30), failure())
        return basics
    }

    private func captureHomeAndNumbers(_ app: XCUIApplication, variant: String) {
        settle()
        shot("home-\(variant)")

        revealNewCategories(in: app)
        settle()
        shot("home-new-categories-\(variant)")

        tap("u-numbers", in: app)
        tap("l-numbers-learn-one-to-five", in: app)
        XCTAssertTrue(
            app.buttons["Practice lesson"].waitForExistence(timeout: 15),
            "Numbers learn list did not open. buttons: \(buttonDump(app))"
        )
        XCTAssertTrue(app.staticTexts["yaw"].waitForExistence(timeout: 5), "Numbers list has no pronunciation")
        XCTAssertTrue(app.staticTexts["0 of 5 words"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Play"].exists, "Numbers has no bundled clip")
        settle(1.0)
        shot("learn-list-numbers-\(variant)")
        let numbersCards = app.buttons["Flashcards"]
        XCTAssertTrue(numbersCards.waitForExistence(timeout: 5), "Numbers list has no flashcards")
        numbersCards.tap()
        XCTAssertTrue(
            app.buttons["Skip to practice"].waitForExistence(timeout: 15),
            "Numbers learn card did not open. buttons: \(buttonDump(app))"
        )
        XCTAssertTrue(app.staticTexts["yaw"].waitForExistence(timeout: 5), "Numbers card has no pronunciation")
        settle(1.0)
        shot("numbers-learn-\(variant)")
    }

    private func captureGreetingsAndTravel(_ app: XCUIApplication, variant: String, basics: XCUIElement) {
        tap("u-greetings", in: app)
        tap("l-greetings-learn", in: app)
        XCTAssertTrue(
            app.buttons["Practice lesson"].waitForExistence(timeout: 15),
            "Greetings learn list did not open. buttons: \(buttonDump(app))"
        )
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5), "Greetings list has no Play button")
        XCTAssertTrue(app.staticTexts["kha"].waitForExistence(timeout: 5), "Greetings list has no pronunciation")
        XCTAssertTrue(
            storedPronunciation("ma-NA-na", in: app).waitForExistence(timeout: 5),
            "Greetings list has no stressed pronunciation"
        )
        XCTAssertTrue(app.staticTexts["0 of 4 words"].waitForExistence(timeout: 5))
        revealLabel("ma-NA-na", in: app)
        settle(1.0)
        shot("learn-list-\(variant)")
        XCTAssertTrue(app.buttons["Pashto"].waitForExistence(timeout: 5))
        app.buttons["Pashto"].tap()
        popToHome(app, basics: basics)

        tap("u-travel", in: app)
        tap("l-travel-learn-around", in: app)
        XCTAssertTrue(
            app.buttons["Practice lesson"].waitForExistence(timeout: 15),
            "Travel learn list did not open. buttons: \(buttonDump(app))"
        )
        XCTAssertTrue(
            storedPronunciation("ho-TAL", in: app).waitForExistence(timeout: 5),
            "Travel list has no stressed pronunciation"
        )
        revealLabel("ho-TAL", in: app)
        settle(1.0)
        shot("learn-list-travel-\(variant)")
        XCTAssertTrue(app.buttons["Pashto"].waitForExistence(timeout: 5))
        app.buttons["Pashto"].tap()
        popToHome(app, basics: basics)
    }

    private func captureFamilyLearnAndQuiz(_ app: XCUIApplication, variant: String) {
        tap("u-family", in: app)
        let mother = app.descendants(matching: .any)["e-mor"]
        XCTAssertTrue(mother.waitForExistence(timeout: 15), "Family word list did not load. buttons: \(buttonDump(app))")
        reveal(mother, in: app)
        settle()
        shot("family-\(variant)")

        tap("l-family-learn-members", in: app)
        XCTAssertTrue(
            app.buttons["Practice lesson"].waitForExistence(timeout: 15),
            "Family learn list did not open. buttons: \(buttonDump(app))"
        )
        XCTAssertTrue(app.buttons["Flashcards"].waitForExistence(timeout: 5))
        app.buttons["Flashcards"].tap()
        XCTAssertTrue(
            app.buttons["Skip to practice"].waitForExistence(timeout: 15),
            "Learn card did not open. buttons: \(buttonDump(app))"
        )
        XCTAssertTrue(
            storedPronunciation("mor", in: app).waitForExistence(timeout: 5),
            "Learn card has no pronunciation"
        )
        settle(1.0)
        shot("learn-\(variant)")

        XCTAssertTrue(app.buttons["Pashto"].waitForExistence(timeout: 5))
        app.buttons["Pashto"].tap()
        XCTAssertTrue(
            app.buttons["Practice lesson"].waitForExistence(timeout: 10),
            "Family learn list did not return. buttons: \(buttonDump(app))"
        )
        app.buttons["Pashto"].tap()

        let practice = app.descendants(matching: .any)["l-family-1"]
        XCTAssertTrue(practice.waitForExistence(timeout: 15), "Family page did not return. buttons: \(buttonDump(app))")
        reveal(practice, in: app)
        practice.tap()
        XCTAssertTrue(waitForQuiz(app), "quiz did not appear. buttons: \(buttonDump(app))")
        settle(1.2)
        shot("quiz-\(variant)")
    }

    private func captureCelebration(_ app: XCUIApplication, variant: String) {
        app.terminate()
        app.launchArguments = launchArguments(for: variant) + ["-PashtoScreenshotCelebration"]
        app.launch()
        let praise = storedPronunciation("DE-ra kha", in: app)
        XCTAssertTrue(
            praise.waitForExistence(timeout: 20),
            "celebration did not appear. buttons: \(buttonDump(app))"
        )
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5))
        settle(0.6)
        shot("celebration-\(variant)")
    }

    private func captureDailyWord(_ app: XCUIApplication, variant: String) {
        app.terminate()
        app.launchArguments = launchArguments(for: variant) + ["-PashtoScreenshotDailyWord"]
        app.launch()
        XCTAssertTrue(
            app.staticTexts["Word of the day"].waitForExistence(timeout: 20),
            "word of the day did not appear. buttons: \(buttonDump(app))"
        )
        let dailyPronunciation = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "ma-NA-na")
        ).firstMatch
        XCTAssertTrue(dailyPronunciation.waitForExistence(timeout: 5), "word of the day has no pronunciation")
        settle(0.6)
        shot("word-of-the-day-\(variant)")
    }

    /// The longest unit 4–8 note, on the first Food phrases card.
    ///
    /// Phrases hide the meaning until Show meaning, and the note is drawn
    /// under it. Three sound tips at the largest text size can be taller
    /// than the card, so the end is a second image only when the first
    /// does not hold the whole note.
    private func captureLongNote(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = launchArguments(for: "xl")
        app.launch()
        let basics = app.descendants(matching: .any)["u-basics"]
        if !basics.waitForExistence(timeout: 20), app.buttons["Start review"].exists {
            app.buttons["Start review"].tap()
        }
        XCTAssertTrue(
            basics.waitForExistence(timeout: 30),
            "home did not load for the long note. buttons: \(buttonDump(app))"
        )
        openInList("u-food", in: app)
        openInList("l-food-phrases-want", in: app)
        XCTAssertTrue(
            app.buttons["Skip to practice"].waitForExistence(timeout: 15),
            "Food phrases card did not open. buttons: \(buttonDump(app))"
        )
        XCTAssertTrue(
            storedPronunciation("tsa ghwaa-REY?", in: app).waitForExistence(timeout: 5),
            "Food phrases card has no pronunciation"
        )
        let showMeaning = app.buttons["Show meaning"]
        XCTAssertTrue(showMeaning.waitForExistence(timeout: 5), "Food phrases card has no Show meaning")
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5), "card has no list. buttons: \(buttonDump(app))")
        revealInScroll(showMeaning, scroll: scroll, in: app)
        showMeaning.tap()
        let note = app.staticTexts.matching(
            NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@",
                "ts as in cats",
                "voiced kh",
                "quick r"
            )
        ).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 8), "pronunciation note did not appear. buttons: \(buttonDump(app))")
        scrollNote(note, in: scroll, showingBottom: false)
        XCTAssertTrue(
            noteIsFullyVisible(note, in: scroll) || noteTopIsVisible(note, in: scroll),
            "start of the note is off the card. frame \(note.frame) scroll \(scroll.frame)"
        )
        settle(0.8)
        shot("notes-learn-xl")
        if !noteIsFullyVisible(note, in: scroll) {
            scrollNote(note, in: scroll, showingBottom: true)
            XCTAssertTrue(
                noteBottomIsVisible(note, in: scroll),
                "end of the note is off the card. frame \(note.frame) scroll \(scroll.frame)"
            )
            settle(0.6)
            shot("notes-learn-xl-2")
        }
    }

    /// Scrolls inside the list, then taps. A drag on the window misses the
    /// list when the header is tall, which is the XL home and the XL unit page.
    private func openInList(_ identifier: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 15), "missing \(identifier). buttons: \(buttonDump(app))")
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5), "list is missing. buttons: \(buttonDump(app))")
        for _ in 0..<28 {
            if element.isHittable { break }
            let frame = element.frame
            nudgeScroll(scroll, revealingLower: frame == .zero || frame.midY >= scroll.frame.midY)
        }
        XCTAssertTrue(
            element.isHittable,
            "\(identifier) is off screen. frame \(element.frame) scroll \(scroll.frame). buttons: \(buttonDump(app))"
        )
        element.tap()
    }

    private func revealInScroll(_ element: XCUIElement, scroll: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 {
            if element.isHittable { return }
            let frame = element.frame
            nudgeScroll(scroll, revealingLower: frame == .zero || frame.midY >= scroll.frame.midY)
        }
        XCTAssertTrue(element.isHittable, "control is off the card. buttons: \(buttonDump(app))")
    }

    /// Brings the start of the note onto the card, or the end when
    /// `showingBottom` is true. Stops if the list will not move.
    private func scrollNote(_ note: XCUIElement, in scroll: XCUIElement, showingBottom: Bool) {
        var lastMaxY = note.frame.maxY
        var stuck = 0
        for _ in 0..<16 {
            if showingBottom {
                if noteBottomIsVisible(note, in: scroll) { return }
            } else if noteIsFullyVisible(note, in: scroll) || noteTopIsVisible(note, in: scroll) {
                return
            }
            let frame = note.frame
            let lower: Bool
            if showingBottom {
                lower = frame == .zero || frame.maxY > scroll.frame.maxY
            } else {
                lower = frame == .zero || frame.midY >= scroll.frame.midY
            }
            nudgeScroll(scroll, revealingLower: lower)
            let next = note.frame.maxY
            if abs(next - lastMaxY) < 1 {
                stuck += 1
                if stuck >= 2 { return }
            } else {
                stuck = 0
            }
            lastMaxY = next
        }
    }

    private func noteTopIsVisible(_ note: XCUIElement, in scroll: XCUIElement) -> Bool {
        let frame = note.frame
        let window = scroll.frame
        return frame.width > 1 && frame.height > 1 && frame.minY >= window.minY - 8 && frame.minY < window.midY
    }

    private func noteBottomIsVisible(_ note: XCUIElement, in scroll: XCUIElement) -> Bool {
        let frame = note.frame
        let window = scroll.frame
        return frame.width > 1 && frame.height > 1 && frame.maxY <= window.maxY + 8 && frame.maxY > window.minY
    }

    private func noteIsFullyVisible(_ note: XCUIElement, in scroll: XCUIElement) -> Bool {
        let frame = note.frame
        guard frame.width > 1, frame.height > 1 else { return false }
        return scroll.frame.insetBy(dx: 0, dy: 8).contains(frame)
    }

    private func captureTimeDays(_ app: XCUIApplication, basics: XCUIElement) {
        app.terminate()
        app.launchArguments = launchArguments(for: "xl")
        app.launch()
        if !basics.waitForExistence(timeout: 20), app.buttons["Start review"].exists {
            app.buttons["Start review"].tap()
        }
        XCTAssertTrue(
            basics.waitForExistence(timeout: 30),
            "home did not load for the Time list. buttons: \(buttonDump(app))"
        )
        tap("u-time", in: app)
        tap("l-time-learn-days", in: app)
        XCTAssertTrue(
            app.buttons["Practice lesson"].waitForExistence(timeout: 15),
            "Time days list did not open. buttons: \(buttonDump(app))"
        )
        XCTAssertTrue(
            storedPronunciation("cha-haar-shan-BA", in: app).waitForExistence(timeout: 5),
            "Time days list has no long pronunciation"
        )
        revealLabel("cha-haar-shan-BA", in: app)
        settle(1.0)
        shot("learn-list-time-xl")
    }

    private func captureBoldText(_ app: XCUIApplication, variant: String, basics: XCUIElement) {
        guard variant == "light" else { return }
        app.terminate()
        app.launchArguments = launchArguments(for: variant) + ["-PashtoScreenshotBoldText"]
        app.launch()
        if !basics.waitForExistence(timeout: 20), app.buttons["Start review"].exists {
            app.buttons["Start review"].tap()
        }
        XCTAssertTrue(
            basics.waitForExistence(timeout: 30),
            "home did not load for Bold Text. buttons: \(buttonDump(app))"
        )
        tap("u-greetings", in: app)
        tap("l-greetings-learn", in: app)
        XCTAssertTrue(
            app.buttons["Practice lesson"].waitForExistence(timeout: 15),
            "Bold Text learn list did not open. buttons: \(buttonDump(app))"
        )
        XCTAssertTrue(
            storedPronunciation("ma-NA-na", in: app).waitForExistence(timeout: 5),
            "Bold Text list has no stressed pronunciation"
        )
        revealLabel("ma-NA-na", in: app)
        settle(1.0)
        shot("learn-list-bold-light")
    }

    private func launchArguments(for variant: String) -> [String] {
        var arguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        switch variant {
        case "dark":
            arguments.append("-PashtoScreenshotDark")
        case "xl":
            arguments.append("-PashtoScreenshotLight")
            arguments.append("-PashtoScreenshotXL")
        default:
            arguments.append("-PashtoScreenshotLight")
        }
        return arguments
    }

    /// Scrolls until Numbers, Food, Town, and Conversation are on screen together.
    /// The first Home shot stays at the top, before this scroll. At the largest
    /// text size the four cards do not fit, so the scroll stops with Numbers
    /// still tappable and as many of the next rows as the list can show.
    private func revealNewCategories(in app: XCUIApplication) {
        let rows = ["u-numbers", "u-food", "u-town", "u-conversation"].map {
            app.descendants(matching: .any)[$0]
        }
        for row in rows {
            XCTAssertTrue(row.waitForExistence(timeout: 15), "new category row is missing. buttons: \(buttonDump(app))")
        }
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5), "home list is missing. buttons: \(buttonDump(app))")
        for _ in 0..<28 {
            if newCategoriesAreVisible(rows, in: app) { return }
            let numbersWasHittable = rows[0].isHittable
            nudgeScroll(scroll, revealingLower: true)
            if numbersWasHittable && !rows[0].isHittable {
                nudgeScroll(scroll, revealingLower: false)
                XCTAssertTrue(
                    rows[0].exists,
                    "Numbers row is missing after scrolling back. buttons: \(buttonDump(app))"
                )
                XCTAssertTrue(
                    rows[0].isHittable,
                    "Numbers is not on screen after scrolling back. frame \(rows[0].frame) scroll \(scroll.frame). buttons: \(buttonDump(app))"
                )
                return
            }
        }
        XCTAssertTrue(
            rows[0].isHittable,
            "Numbers did not scroll into view. frame \(rows[0].frame) scroll \(scroll.frame) app \(app.frame). buttons: \(buttonDump(app))"
        )
    }

    /// A short drag inside the home list. The header is outside that list, so a
    /// drag on the whole window misses the list when the header is tall.
    private func nudgeScroll(_ scroll: XCUIElement, revealingLower: Bool) {
        let startY: CGFloat = revealingLower ? 0.82 : 0.38
        let endY: CGFloat = revealingLower ? 0.58 : 0.62
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func newCategoriesAreVisible(_ rows: [XCUIElement], in app: XCUIApplication) -> Bool {
        let frames = rows.map(\.frame)
        guard frames.allSatisfy({ $0.width > 1 && $0.height > 1 && app.frame.contains($0) }) else {
            return false
        }
        guard zip(frames, frames.dropFirst()).allSatisfy({ $0.minY < $1.minY }) else {
            return false
        }
        return rows.allSatisfy(\.isHittable)
    }

    /// Leaves a category page for the home. The back control is the navigation chevron.
    private func popToHome(_ app: XCUIApplication, basics: XCUIElement) {
        let back = app.navigationBars.buttons.firstMatch
        if back.waitForExistence(timeout: 5) {
            back.tap()
        }
        if basics.waitForExistence(timeout: 8) { return }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(
            basics.waitForExistence(timeout: 15),
            "home did not return from the category. buttons: \(buttonDump(app))"
        )
    }

    /// The stored pronunciation. Syllables are drawn separately in lowercase,
    /// so they are not one static text. VoiceOver's label is the stored field,
    /// on whatever element type SwiftUI gives that line.
    private func storedPronunciation(_ stored: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", stored)
        ).firstMatch
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any)[identifier]
        reveal(element, in: app)
        element.tap()
    }

    /// Scrolls a pronunciation label into the window. The label is the stored
    /// field, including capitals, because that is what VoiceOver reads.
    private func revealLabel(_ label: String, in app: XCUIApplication) {
        let element = storedPronunciation(label, in: app)
        XCTAssertTrue(element.waitForExistence(timeout: 5), "missing \(label)")
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 {
            let frame = element.frame
            if frame.width > 1, frame.minY > 64, frame.maxY < app.frame.maxY - 16 {
                return
            }
            if scroll.exists {
                nudgeScroll(scroll, revealingLower: frame == .zero || frame.midY >= app.frame.midY)
            } else if frame == .zero || frame.midY >= app.frame.midY {
                app.swipeUp(velocity: .slow)
            } else {
                app.swipeDown(velocity: .slow)
            }
        }
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "missing control. buttons: \(buttonDump(app))")
        for _ in 0..<16 {
            if element.isHittable { return }
            let frame = element.frame
            if frame == .zero || frame.midY >= app.frame.midY {
                app.swipeUp(velocity: .slow)
            } else {
                app.swipeDown(velocity: .slow)
            }
        }
        XCTAssertTrue(element.isHittable, "control is off screen. buttons: \(buttonDump(app))")
    }

    /// A quiz question is on screen when the practice row is gone and a quiz
    /// title or the Continue button is showing.
    private func waitForQuiz(_ app: XCUIApplication) -> Bool {
        let practice = app.descendants(matching: .any)["l-family-1"]
        let titles = ["Choose the meaning", "Put the words in order", "Match the pairs"]
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let titled = titles.contains { app.staticTexts[$0].exists }
            if titled || (app.buttons["Continue"].exists && !practice.exists) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    private func settle(_ seconds: TimeInterval = 0.8) {
        let settled = expectation(description: "settle")
        settled.isInverted = true
        wait(for: [settled], timeout: seconds)
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("pashto-screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }

    private func buttonDump(_ app: XCUIApplication) -> String {
        app.buttons.allElementsBoundByIndex.prefix(25).map { button in
            button.identifier.isEmpty ? button.label : "\(button.identifier) (\(button.label))"
        }.joined(separator: ", ")
    }
}
