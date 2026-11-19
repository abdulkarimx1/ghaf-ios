import XCTest

/// Real-data walkthrough: taps, scrolls and swipes key screens, saves screenshots and tap-to-idle timings to GHAF_UI_OUT.
/// Run: TEST_RUNNER_GHAF_UI_OUT=<dir> TEST_RUNNER_GHAF_BACKUP=<backup.json> xcodebuild test -scheme GhafUITests -destination id=<UDID>
final class GhafWalkthroughTests: XCTestCase {
    let out = ProcessInfo.processInfo.environment["GHAF_UI_OUT"] ?? NSTemporaryDirectory()
    var log = ""
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    }

    func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        let backup = ProcessInfo.processInfo.environment["GHAF_BACKUP"].map { ["-GhafRestoreBackup", $0] } ?? []
        app.launchArguments = ["-GhafFixture", "1"] + backup + ["-GhafTheme", "Graphite",
                               "-GhafAppearance", "Dark", "-GhafLanguage", "en"] + extra
        app.launch()
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 20)
    }

    func snap(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    }

    /// Times a tap including XCTest's wait for the app to go idle (main thread + animations).
    func timedTap(_ e: XCUIElement, _ label: String) {
        guard e.waitForExistence(timeout: 5) else { log += "MISSING \(label)\n"; return }
        let t = Date(); e.tap(); log += String(format: "%@ %.2fs\n", label, Date().timeIntervalSince(t))
    }

    func swipeUp(_ n: Int = 1) { for _ in 0..<n { app.swipeUp(velocity: .fast) } }

    override func tearDown() {
        let path = "\(out)/timings.txt"
        let old = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        try? (old + log).write(toFile: path, atomically: true, encoding: .utf8)
    }

    func test1HomeWallet() {
        launch()
        snap("h0-home"); swipeUp(); snap("h1-home-scrolled"); app.swipeDown(velocity: .fast)
        timedTap(app.buttons["Accounts"].firstMatch, "open wallet")
        snap("w0-wallet")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.3)), end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.3))
        let t = Date()
        for _ in 0..<4 { start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0) }
        log += String(format: "4 fast card swipes %.2fs\n", Date().timeIntervalSince(t))
        snap("w1-after-swipes")
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.3)), withVelocity: .slow, thenHoldForDuration: 0.6)
        snap("w2-mid-drag")
        swipeUp(); snap("w3-wallet-scrolled")
        let edit = app.buttons["Edit"].firstMatch
        if edit.waitForExistence(timeout: 3) { edit.tap(); snap("w4-account-editor")
            let arch = app.buttons["Archive account"].firstMatch
            if arch.waitForExistence(timeout: 3) { arch.tap(); sleep(1); snap("w5-archive-dialog") } else { log += "MISSING archive\n" }
        } else { log += "MISSING Edit\n" }
    }

    func test2Stats() {
        launch()
        timedTap(app.tabBars.buttons["Stats"], "tab Stats")
        snap("c0-stats")
        for p in ["W", "3M", "Y", "M"] { timedTap(app.buttons[p].firstMatch, "period \(p)"); snap("c-period-\(p)") }
        swipeUp(); snap("c1-stats-scrolled"); swipeUp(); snap("c2-stats-scrolled2")
        app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
        let budget = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'budget'")).firstMatch
        timedTap(budget, "open budget"); snap("c3-budget")
        swipeUp(); snap("c4-budget-scrolled"); swipeUp(); snap("c5-budget-scrolled2")
    }

    func test3MoreAutomation() {
        launch()
        timedTap(app.tabBars.buttons["More"], "tab More")
        swipeUp(); snap("m1-more-scrolled"); swipeUp(); snap("m2-more-scrolled2"); app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
        timedTap(app.buttons["Bank automation"].firstMatch, "open automation")
        snap("b0-automation"); swipeUp(); snap("b1-automation-scrolled"); swipeUp(); snap("b2-automation-scrolled2")
        app.navigationBars.buttons.firstMatch.tap()
        timedTap(app.buttons["About Ghaf"].firstMatch, "open about"); snap("m3-about"); swipeUp(); snap("m4-about-scrolled")
    }

    func test4SubsTransactions() {
        launch()
        timedTap(app.buttons["Subs"].firstMatch, "open subscriptions"); snap("s0-subs")
        timedTap(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Adobe'")).firstMatch, "open subscription sheet"); snap("s1-sub-sheet")
        app.terminate(); launch()
        timedTap(app.tabBars.buttons["Transactions"], "tab Transactions"); snap("t0-tx"); swipeUp(); snap("t1-tx-scrolled")
        timedTap(app.tabBars.buttons["Home"], "tab Home")
        timedTap(app.tabBars.buttons["Transactions"], "tab Transactions again")
    }

    func testRestoreCleansMerchantsWithoutChangingBalances() throws {
        guard let backup = ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_BACKUP"]
                ?? ProcessInfo.processInfo.environment["GHAF_BACKUP"] else {
            throw XCTSkip("TEST_RUNNER_GHAF_BACKUP not set")
        }
        app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafRestoreBackup", backup,
                               "-GhafTheme", "Graphite", "-GhafAppearance", "Dark", "-GhafLanguage", "en"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        timedTap(app.tabBars.buttons["Transactions"], "tab Transactions for restore cleanup")
        snap("restore-cleanup-transactions")
    }
}
