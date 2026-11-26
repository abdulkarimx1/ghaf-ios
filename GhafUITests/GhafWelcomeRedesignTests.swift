import XCTest

/// Captures each redesigned welcome page early (mid-entrance) and settled, light/dark, EN/AR.
final class GhafWelcomeRedesignTests: XCTestCase {
    func testWelcomePagesCapture() {
        let out = ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_UI_OUT"] ?? NSTemporaryDirectory()
        for (appearance, language) in [("Dark", "en"), ("Light", "ar")] {
            let app = XCUIApplication()
            app.launchArguments = ["-GhafFixture", "1", "-GhafLaunchProof", "1", "-GhafLaunchNewUser", "1",
                                   "-GhafAppearance", appearance, "-GhafLanguage", language, "-GhafTheme", "Graphite"]
            app.launch()
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() // dismiss the cold-launch cover
            let start = app.buttons[language == "ar" ? "ابدأ" : "Get started"].firstMatch
            XCTAssertTrue(start.waitForExistence(timeout: 20))
            let next = app.buttons[language == "ar" ? "متابعة" : "Continue"].firstMatch
            for page in 0..<4 {
                if page == 1 { start.tap(); XCTAssertTrue(next.waitForExistence(timeout: 5)) }
                if page > 1 { next.tap() }
                Thread.sleep(forTimeInterval: 0.25)
                try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/welcome-\(appearance)-\(language)-\(page)-a.png"))
                Thread.sleep(forTimeInterval: 1.8)
                try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/welcome-\(appearance)-\(language)-\(page)-b.png"))
            }
            app.terminate()
        }
    }
}
