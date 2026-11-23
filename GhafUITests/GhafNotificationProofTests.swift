import XCTest

final class GhafNotificationProofTests: XCTestCase {
    private let ownerBackup = "/Users/abdulkarim/orca/workspaces/Ghaf budget app/HANDOFF-1.29/backup8.json"
    private var app: XCUIApplication!
    private var output: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_UI_OUT"]
            ?? "/tmp/ghaf-v30h-notify-screenshots", isDirectory: true)
    }

    func testAchievementCardRoutesToProfileAndDoesNotRepeat() throws {
        app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafFixtureOnDisk", "-GhafFixtureReset",
                               "-GhafStreakCardProof",
                               "-GhafTheme", "Graphite", "-GhafAppearance", "Light", "-GhafLanguage", "en"]
        app.launch()
        XCTAssertTrue(app.staticTexts["7-day streak!"].waitForExistence(timeout: 15))
        capture("streak-save-home-light-en")
        let action = app.buttons["ghaf.in-app-card.action"]
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        action.tap()
        XCTAssertTrue(app.staticTexts["7-day milestone"].waitForExistence(timeout: 10))
        app.terminate()

        app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafFixtureOnDisk", "-GhafTheme", "Graphite",
                               "-GhafAppearance", "Light", "-GhafLanguage", "en"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["7-day streak!"].exists, "The milestone must not appear again after relaunch.")
        app.terminate()
    }

    func testStreakCardScreenshotsOnHomeAndTransactionsInAllLocalesAndThemes() throws {
        try captureCardMatrix(kind: "streak")
    }

    func testAnnouncementCardScreenshotsInAllLocalesAndThemes() throws {
        try captureCardMatrix(kind: "announcement")
    }

    func testVoucherAnnouncementShowsCopyableCode() throws {
        app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafRestoreBackup", ownerBackup,
                               "-GhafTheme", "Graphite", "-GhafAppearance", "Light", "-GhafLanguage", "en",
                               "-GhafAnnouncementCardProof", "-GhafVoucherCardProof"]
        app.launch()
        XCTAssertTrue(app.staticTexts["ghaf.in-app-card.voucher-code"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Copy code"].exists)
        capture("announcement-voucher-code-en")
    }

    private func captureCardMatrix(kind: String) throws {
        let variants: [(String, String, String, String)] = [
            ("Light", "en", "light-en", "7-day streak!"),
            ("Dark", "en", "dark-en", "7-day streak!"),
            ("Light", "ar", "light-ar", "إنجاز ٧ أيام!"),
            ("Dark", "ar", "dark-ar", "إنجاز ٧ أيام!")
        ]
        for (appearance, language, suffix, streakTitle) in variants {
            app = XCUIApplication()
            let restore = FileManager.default.fileExists(atPath: ownerBackup) ? ["-GhafRestoreBackup", ownerBackup] : []
            app.launchArguments = ["-GhafFixture", "1"] + restore + ["-GhafTheme", "Graphite", "-GhafAppearance", appearance,
                "-GhafLanguage", language, kind == "streak" ? "-GhafStreakCardProof" : "-GhafAnnouncementCardProof"]
            app.launch()
            let expected = kind == "streak" ? streakTitle : (language == "ar" ? "يتوفر تحديث غاف" : "A Ghaf update is ready")
            XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 20), "Missing \(kind) card for \(suffix)")
            capture("\(kind)-\(suffix)-home")
            let transactions = app.tabBars.buttons[language == "ar" ? "العمليات" : "Transactions"]
            XCTAssertTrue(transactions.waitForExistence(timeout: 5))
            transactions.tap()
            XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 3))
            capture("\(kind)-\(suffix)-transactions")
            app.terminate()
        }
    }

    func testEachNotificationBannerCanBeTriggeredInTheSimulator() throws {
        let variants: [(String, String)] = [
            ("capture", "Transaction saved"), ("review", "Check a transaction"),
            ("subscription", "Payment coming up"), ("budget", "Food reached 80% of its budget"),
            ("salary", "Salary day"), ("digest", "Today in Ghaf")
        ]
        for (kind, title) in variants {
            app = XCUIApplication()
            app.launchArguments = ["-GhafFixture", "1", "-GhafTheme", "Graphite", "-GhafAppearance", "Dark",
                                  "-GhafLanguage", "en", "-GhafNotificationProof", kind]
            app.launch()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allow = springboard.alerts.buttons["Allow"]
            if allow.waitForExistence(timeout: 2) { allow.tap() }
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
            let banner = springboard.otherElements.containing(.staticText, identifier: title).firstMatch
            XCTAssertTrue(banner.waitForExistence(timeout: 5), "Missing (kind) notification banner")
            Thread.sleep(forTimeInterval: 1.5)
            capture("notification-\(kind)-banner")
            app.terminate()
        }
    }

    private func capture(_ name: String) {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: output.appendingPathComponent("\(name).png"))
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }
}
