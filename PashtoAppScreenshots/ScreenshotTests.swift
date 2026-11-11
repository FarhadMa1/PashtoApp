import XCTest

/// Opens the home, the lower Home rows, a Numbers learn card, the Family
/// screens, a quiz, and the celebration. The workflow runs this once per
/// variant: light, dark, and the largest accessibility text size.
@MainActor
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLight() {
        capture(variant: "light")
    }

    func testDark() {
        capture(variant: "dark")
    }

    func testXL() {
        capture(variant: "xl")
    }

    private func capture(variant: String) {
        let app = XCUIApplication()
        app.launchArguments = launchArguments(for: variant)
        app.launch()

        let basics = app.descendants(matching: .any)["u-basics"]
        if !basics.waitForExistence(timeout: 20), app.buttons["Start review"].exists {
            app.buttons["Start review"].tap()
        }
        XCTAssertTrue(
            basics.waitForExistence(timeout: 30),
            "home did not load. buttons: \(buttonDump(app))"
        )
        settle()
        shot("home-\(variant)")

        revealNewCategories(in: app)
        settle()
        shot("home-new-categories-\(variant)")

        tap("u-numbers", in: app)
        tap("l-numbers-learn-one-to-five", in: app)
        XCTAssertTrue(
            app.buttons["Skip to practice"].waitForExistence(timeout: 15),
            "Numbers learn card did not open. buttons: \(buttonDump(app))"
        )
        XCTAssertTrue(app.staticTexts["yaw"].waitForExistence(timeout: 5), "Numbers card has no pronunciation")
        settle(1.0)
        shot("numbers-learn-\(variant)")

        app.terminate()
        app.launchArguments = launchArguments(for: variant)
        app.launch()
        if !basics.waitForExistence(timeout: 20), app.buttons["Start review"].exists {
            app.buttons["Start review"].tap()
        }
        XCTAssertTrue(
            basics.waitForExistence(timeout: 30),
            "home did not return. buttons: \(buttonDump(app))"
        )

        tap("u-family", in: app)
        let mother = app.descendants(matching: .any)["e-mor"]
        XCTAssertTrue(mother.waitForExistence(timeout: 15), "Family word list did not load. buttons: \(buttonDump(app))")
        reveal(mother, in: app)
        settle()
        shot("family-\(variant)")

        tap("l-family-learn-members", in: app)
        XCTAssertTrue(
            app.buttons["Skip to practice"].waitForExistence(timeout: 15),
            "Learn card did not open. buttons: \(buttonDump(app))"
        )
        XCTAssertTrue(app.staticTexts["mor"].waitForExistence(timeout: 5), "Learn card has no pronunciation")
        settle(1.0)
        shot("learn-\(variant)")

        XCTAssertTrue(app.buttons["Pashto"].waitForExistence(timeout: 5))
        app.buttons["Pashto"].tap()

        let practice = app.descendants(matching: .any)["l-family-1"]
        XCTAssertTrue(practice.waitForExistence(timeout: 15), "Family page did not return. buttons: \(buttonDump(app))")
        reveal(practice, in: app)
        practice.tap()
        XCTAssertTrue(waitForQuiz(app), "quiz did not appear. buttons: \(buttonDump(app))")
        settle(1.2)
        shot("quiz-\(variant)")

        app.terminate()
        app.launchArguments = launchArguments(for: variant) + ["-PashtoScreenshotCelebration"]
        app.launch()
        let praise = app.staticTexts["DE-ra kha"]
        XCTAssertTrue(
            praise.waitForExistence(timeout: 20),
            "celebration did not appear. buttons: \(buttonDump(app))"
        )
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5))
        settle(0.6)
        shot("celebration-\(variant)")
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
    /// The first Home shot stays at the top, before this scroll.
    private func revealNewCategories(in app: XCUIApplication) {
        let rows = ["u-numbers", "u-food", "u-town", "u-conversation"].map {
            app.descendants(matching: .any)[$0]
        }
        for row in rows {
            XCTAssertTrue(row.waitForExistence(timeout: 15), "new category row is missing. buttons: \(buttonDump(app))")
        }
        for _ in 0..<24 {
            if newCategoriesAreVisible(rows, in: app) { return }
            let numbers = rows[0].frame
            let conversation = rows[3].frame
            if conversation == .zero || conversation.maxY > app.frame.maxY - 8 {
                drag(in: app, from: 0.72, to: 0.48)
            } else if numbers.minY < 8 || !rows[0].isHittable {
                drag(in: app, from: 0.42, to: 0.62)
            } else {
                drag(in: app, from: 0.68, to: 0.50)
            }
        }
        // The largest text size cannot fit four full cards under the header.
        // Park Numbers at the top of the list so the new rows fill the screen.
        parkNewCategories(rows, in: app)
    }

    private func parkNewCategories(_ rows: [XCUIElement], in app: XCUIApplication) {
        let time = app.descendants(matching: .any)["u-time"]
        for _ in 0..<6 {
            drag(in: app, from: 0.40, to: 0.78)
        }
        for _ in 0..<18 {
            if newCategoriesAreVisible(rows, in: app) { return }
            let numbers = rows[0].frame
            let numbersInside = numbers.height > 1 && app.frame.contains(numbers)
            let timeAbove = visibleHeight(time.frame, in: app) < 12 && time.frame.maxY <= numbers.minY + 4
            if numbersInside && timeAbove { return }
            if numbers.minY < 24 && visibleHeight(numbers, in: app) < numbers.height * 0.85 {
                drag(in: app, from: 0.48, to: 0.60)
                return
            }
            drag(in: app, from: 0.66, to: 0.52)
        }
        XCTAssertGreaterThan(
            visibleHeight(rows[0].frame, in: app), 36,
            "Numbers did not scroll into view. buttons: \(buttonDump(app))"
        )
        XCTAssertGreaterThan(
            visibleHeight(rows[1].frame, in: app), 20,
            "Food did not scroll into view. buttons: \(buttonDump(app))"
        )
    }

    private func visibleHeight(_ frame: CGRect, in app: XCUIApplication) -> CGFloat {
        let intersection = frame.intersection(app.frame)
        guard !intersection.isNull else { return 0 }
        return intersection.height
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

    private func drag(in app: XCUIApplication, from startY: CGFloat, to endY: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any)[identifier]
        reveal(element, in: app)
        element.tap()
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
