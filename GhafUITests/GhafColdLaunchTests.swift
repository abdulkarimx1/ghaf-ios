import XCTest

final class GhafColdLaunchTests: XCTestCase {
    func testColdLaunchHomeThenFirstTransactionsOpen() {
        let app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafTheme", "Graphite",
                              "-GhafAppearance", "Light", "-GhafLanguage", "en"]
        let backup = ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_BACKUP"]
            ?? "/Users/abdulkarim/orca/workspaces/Ghaf budget app/HANDOFF-1.29/backup8.json"
        if FileManager.default.fileExists(atPath: backup) {
            app.launchArguments += ["-GhafRestoreBackup", backup]
        }
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.descendants(matching: .any)["home.period.spent"].waitForExistence(timeout: 10))
        capture("cold-home-light-en")

        app.tabBars.buttons["Transactions"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["transactions.month.spent"].waitForExistence(timeout: 10))
        capture("first-transactions-light-en")
        app.terminate()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Screen capture: \(name)") { activity in
            activity.add(attachment)
        }
    }
}
