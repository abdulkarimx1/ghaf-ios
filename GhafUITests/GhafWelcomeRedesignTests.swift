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
            let next = app.buttons[language == "ar" ? "متابعة" : "Continue"].firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 20))
            for page in 0..<5 {
                if page > 0 { next.tap() }
                Thread.sleep(forTimeInterval: 0.25)
                try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/welcome-\(appearance)-\(language)-\(page)-a.png"))
                Thread.sleep(forTimeInterval: 1.8)
                try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/welcome-\(appearance)-\(language)-\(page)-b.png"))
            }
            app.terminate()
        }
    }
}
