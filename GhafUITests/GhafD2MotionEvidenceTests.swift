import XCTest

/// Captures D2's owner-data and first-run motion states without touching the simulator's saved store.
final class GhafD2MotionEvidenceTests: XCTestCase {
    private var app: XCUIApplication!
    private var simulatorBackup: String? {
        ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_BACKUP"]
            ?? ProcessInfo.processInfo.environment["GHAF_BACKUP"]
    }
    private var outputDirectory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_UI_OUT"] ?? NSTemporaryDirectory(),
            isDirectory: true)
    }

    override func setUp() {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    private func launch(_ arguments: [String]) {
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        try? screenshot.pngRepresentation.write(to: outputDirectory.appendingPathComponent("\(name).png"))
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    func testOnboardingWelcomeMotionEvidence() {
        for appearance in ["Light", "Dark"] {
            for language in ["en", "ar"] {
                launch(["-GhafFixture", "1", "-GhafLaunchProof", "1", "-GhafLaunchNewUser", "1",
                        "-GhafTheme", "Graphite", "-GhafAppearance", appearance, "-GhafLanguage", language])
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                XCTAssertTrue(app.buttons[language == "ar" ? "متابعة" : "Continue"].waitForExistence(timeout: 25))
                capture("onboarding-before-\(appearance)-\(language)")

                let heroPoint = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.33))
                heroPoint.press(forDuration: 0.6)
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: language == "ar" ? 0.22 : 0.78, dy: 0.33))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: language == "ar" ? 0.78 : 0.22, dy: 0.33))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
                let nextStep = language == "ar" ? "الخطوة 2 من 8" : "Step 2 of 8"
                let pageLabel = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS %@", nextStep)).firstMatch
                XCTAssertTrue(pageLabel.waitForExistence(timeout: 5), "The swipe should advance one onboarding page")
                Thread.sleep(forTimeInterval: 0.7)
                capture("onboarding-after-swipe-\(appearance)-\(language)")
                app.terminate()
            }
        }
    }

    func testHomeEntranceEvidence() throws {
        guard let simulatorBackup else { throw XCTSkip("Set TEST_RUNNER_GHAF_BACKUP to the private owner backup") }
        for appearance in ["Light", "Dark"] {
            for language in ["en", "ar"] {
                launch(["-GhafFixture", "1", "-GhafRestoreBackup", simulatorBackup,
                        "-GhafTheme", "Graphite", "-GhafAppearance", appearance, "-GhafLanguage", language])
                XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
                capture("home-\(appearance)-\(language)")
                app.terminate()
            }
        }
    }

    func testProHeroEvidence() throws {
        guard let simulatorBackup else { throw XCTSkip("Set TEST_RUNNER_GHAF_BACKUP to the private owner backup") }
        for appearance in ["Light", "Dark"] {
            for language in ["en", "ar"] {
                launch(["-GhafFixture", "1", "-GhafRestoreBackup", simulatorBackup,
                        "-GhafTheme", "Graphite", "-GhafAppearance", appearance, "-GhafLanguage", language,
                        "-GhafScreen", "pro-sheet"])
                XCTAssertTrue(app.buttons[language == "ar" ? "قريباً على App Store" : "Coming soon to the App Store"]
                    .waitForExistence(timeout: 20))
                capture("pro-\(appearance)-\(language)")
                app.terminate()
            }
        }
    }
}
