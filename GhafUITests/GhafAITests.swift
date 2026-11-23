import XCTest

final class GhafAITests: XCTestCase {
    private let simulator = "ACB264CF-DA9E-44A6-9A0E-23553CF7BA3A"
    private let output = ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_UI_OUT"] ?? "/private/tmp/ghaf-a2/screens/after"
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
    }

    private func launchAI(language: String = "en", appearance: String = "Dark", tab: String = "ai", extra: [String] = []) {
        app = XCUIApplication()
        let backup = ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_BACKUP"]
            ?? "/Users/abdulkarim/orca/workspaces/Ghaf budget app/HANDOFF-1.29/backup8.json"
        app.launchArguments = [
            "-GhafFixture", "1", "-GhafRestoreBackup", backup,
            "-GhafTheme", "Graphite", "-GhafAppearance", appearance,
            "-GhafLanguage", language, "-GhafTab", tab
        ] + extra
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
    }

    private func capture(_ name: String) {
        let image = XCUIScreen.main.screenshot()
        try? image.pngRepresentation.write(to: URL(fileURLWithPath: "\(output)/\(name).png"))
    }

    func testA2PaywallEnglishAndArabicLightAndDark() {
        for (language, appearance, suffix) in [
            ("en", "Light", "en-light"), ("en", "Dark", "en-dark"),
            ("ar", "Light", "ar-light"), ("ar", "Dark", "ar-dark")
        ] {
            launchAI(language: language, appearance: appearance, extra: ["-GhafAINonProTestAccess"])
            let title = language == "ar" ? "غاف AI لأعضاء Pro" : "Ghaf AI is for Pro members"
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), "Missing paywall title in \(suffix)")
            capture("paywall-\(suffix)")
            let planButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", language == "ar" ? "الأساسية" : "Essentials")).firstMatch
            XCTAssertTrue(planButton.waitForExistence(timeout: 5))
            planButton.tap()
            XCTAssertTrue(app.staticTexts["Ghaf Pro"].waitForExistence(timeout: 8))
            capture("paywall-plans-\(suffix)")
            app.terminate()
        }
    }

    func testA2UsageFollowUpAndScreenOrbLongPress() {
        launchAI(extra: ["-GhafAIProTestAccess", "-GhafAIUsageFixture"])
        XCTAssertTrue(app.staticTexts["2 of 3 voice replies left today"].waitForExistence(timeout: 8))
        capture("usage-bar-en-dark")
        app.terminate()

        launchAI(extra: ["-GhafAIProTestAccess", "-GhafScreen", "ai-conversation"])
        XCTAssertTrue(app.buttons["Top category"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["Due subscriptions"].exists)
        capture("follow-up-chips-en-dark")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Top category")).count, 1)
        app.buttons["Top category"].tap()
        XCTAssertTrue(app.staticTexts["Top category"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Top category")).count, 1,
                       "Only the latest assistant answer should show follow-up chips")

        let orb = app.descendants(matching: .any).matching(identifier: "ghaf.ai.orb").firstMatch
        XCTAssertTrue(orb.waitForExistence(timeout: 5))
        orb.press(forDuration: 0.8)
        XCTAssertTrue(app.textFields["ghaf.ai.question"].waitForExistence(timeout: 5))
        capture("typing-after-screen-orb-hold-en-dark")
    }

    func testA2TabOrbLongPressOpensTyping() {
        for (language, suffix) in [("en", "en"), ("ar", "ar")] {
            launchAI(language: language, tab: "home", extra: ["-GhafAIProTestAccess"])
            let orb = app.descendants(matching: .any).matching(identifier: "ghaf.ai.tab-orb").firstMatch
            XCTAssertTrue(orb.waitForExistence(timeout: 8), "Tab orb missing in \(suffix)")
            orb.press(forDuration: 0.8)
            XCTAssertTrue(app.textFields["ghaf.ai.question"].waitForExistence(timeout: 8), "Hold did not open typing in \(suffix)")
            capture("typing-after-tab-orb-hold-\(suffix)-dark")
            app.terminate()
        }
    }

    func testA2TabOrbTapNavigatesWithoutStartingVoiceEnglishAndArabic() {
        for (language, suffix) in [("en", "en"), ("ar", "ar")] {
            launchAI(language: language, tab: "home", extra: ["-GhafAINonProTestAccess"])
            let orb = app.descendants(matching: .any).matching(identifier: "ghaf.ai.tab-orb").firstMatch
            XCTAssertTrue(orb.waitForExistence(timeout: 8), "Tab orb missing in \(suffix)")
            orb.tap()
            let title = language == "ar" ? "غاف AI لأعضاء Pro" : "Ghaf AI is for Pro members"
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 8), "Tap did not navigate to AI in \(suffix)")
            XCTAssertFalse(app.textFields["ghaf.ai.question"].exists, "A tap should not open text entry in \(suffix)")
            capture("tab-orb-tap-paywall-\(suffix)-dark")
            app.terminate()
        }
    }

    func testA2AccessCodeEntryScreen() {
        for (language, appearance, suffix) in [
            ("en", "Light", "en-light"), ("en", "Dark", "en-dark"),
            ("ar", "Light", "ar-light"), ("ar", "Dark", "ar-dark")
        ] {
            launchAI(language: language, appearance: appearance, extra: ["-GhafAINonProTestAccess"])
            let title = language == "ar" ? "غاف AI لأعضاء Pro" : "Ghaf AI is for Pro members"
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 8))
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", language == "ar" ? "الأساسية" : "Essentials")).firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Ghaf Pro"].waitForExistence(timeout: 8))
            let haveCode = app.buttons["ghaf.pro.have-code"]
            XCTAssertTrue(haveCode.waitForExistence(timeout: 5))
            haveCode.tap()
            XCTAssertTrue(app.textFields["ghaf.pro.access-code"].waitForExistence(timeout: 5))
            capture("access-code-entry-\(suffix)")
            app.terminate()
        }
    }

    func testA2FollowUpChipsArabicAndEnglishLightAndDark() {
        for (language, appearance, suffix) in [
            ("en", "Light", "en-light"), ("en", "Dark", "en-dark"),
            ("ar", "Light", "ar-light"), ("ar", "Dark", "ar-dark")
        ] {
            launchAI(language: language, appearance: appearance, extra: ["-GhafAIProTestAccess", "-GhafScreen", "ai-conversation"])
            let question = language == "ar" ? "كم صرفت هذا الأسبوع؟" : "How much did I spend this week?"
            XCTAssertTrue(app.staticTexts[question].waitForExistence(timeout: 8), "Fixture question language mismatch in \(suffix)")
            let primaryChip = language == "ar" ? "أعلى فئة" : "Top category"
            let lastMonthChip = language == "ar" ? "هذا الشهر والماضي" : "This month vs last"
            let dueChip = language == "ar" ? "الاشتراكات القادمة" : "Due subscriptions"
            XCTAssertTrue(app.buttons[primaryChip].waitForExistence(timeout: 12), "Missing primary chip in \(suffix)")
            XCTAssertTrue(app.buttons[lastMonthChip].exists, "Missing comparison chip in \(suffix)")
            XCTAssertTrue(app.buttons[dueChip].exists, "Missing subscriptions chip in \(suffix)")
            capture("follow-up-chips-\(suffix)")
            app.terminate()
        }
    }
}
