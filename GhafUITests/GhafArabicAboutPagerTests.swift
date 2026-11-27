import XCTest

final class GhafArabicAboutPagerTests: XCTestCase {
    private var outputDirectory: URL {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_UI_OUT"] ?? NSTemporaryDirectory(), isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testArabicAboutPagerFollowsFingerDirection() {
        let app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafTheme", "Graphite", "-GhafAppearance", "Light",
                               "-GhafLanguage", "ar", "-GhafScreen", "about", "-GhafAboutPage", "0"]
        app.launch()
        let privacy = app.staticTexts["خصوصيتك من أول يوم"]
        let automation = app.staticTexts["يسجّل تلقائياً"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 8))
        save(app, "about-rtl-before-swipe")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.50))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.50)))
        XCTAssertTrue(automation.waitForExistence(timeout: 5), "A right-to-left finger swipe should advance to the next card")
        save(app, "about-rtl-swipe-left")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.50))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.50)))
        XCTAssertTrue(privacy.waitForExistence(timeout: 5), "A left-to-right finger swipe should return to the previous card")
        save(app, "about-rtl-swipe-right")
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        try? screenshot.pngRepresentation.write(to: outputDirectory.appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: name) { $0.add(attachment) }
    }
}
