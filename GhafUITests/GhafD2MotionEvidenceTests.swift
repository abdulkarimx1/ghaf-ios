import XCTest

/// Captures D2's owner-data and first-run motion states without touching the simulator's saved store.
final class GhafD2MotionEvidenceTests: XCTestCase {
    private var app: XCUIApplication!
    private var simulatorBackup: String? {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["TEST_RUNNER_GHAF_BACKUP"] ?? environment["GHAF_BACKUP"],
           FileManager.default.fileExists(atPath: path) { return path }
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent("HANDOFF-1.29/backup8.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate.path }
            directory.deleteLastPathComponent()
        }
        return nil
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
                let start = app.buttons[language == "ar" ? "ابدأ" : "Get started"]
                XCTAssertTrue(start.waitForExistence(timeout: 25))
                capture("onboarding-before-\(appearance)-\(language)")
                start.tap()
                XCTAssertTrue(app.buttons[language == "ar" ? "متابعة" : "Continue"].waitForExistence(timeout: 5), "Get started should open the first feature card")
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
