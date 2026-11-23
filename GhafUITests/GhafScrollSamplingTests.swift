import XCTest

/// A swipe-only workload for external `sample` capture. It intentionally avoids screenshots and
/// accessibility queries while the Home and Transactions scroll loops are running.
final class GhafScrollSamplingTests: XCTestCase {
    func testHomeAndTransactionsSwipeLoops() {
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
        mark("home")
        for _ in 0..<10 {
            app.swipeUp(velocity: .slow)
            app.swipeDown(velocity: .slow)
        }

        app.tabBars.buttons["Transactions"].tap()
        mark("transactions")
        for _ in 0..<10 {
            app.swipeUp(velocity: .slow)
            app.swipeDown(velocity: .slow)
        }
        mark("done")
        app.terminate()
    }

    private func mark(_ stage: String) {
        try? Data(stage.utf8).write(to: URL(fileURLWithPath: "/tmp/ghaf-scroll-sampling-stage.txt"), options: .atomic)
    }
}
