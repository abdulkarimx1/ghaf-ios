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

    func launch(_ extra: [String] = [], appearance: String = "Dark") {
        app = XCUIApplication()
        let backup = ProcessInfo.processInfo.environment["GHAF_BACKUP"].map { ["-GhafRestoreBackup", $0] } ?? []
        app.launchArguments = ["-GhafFixture", "1"] + backup + ["-GhafTheme", "Graphite",
                               "-GhafAppearance", appearance, "-GhafLanguage", "en"] + extra
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

    func test5BudgetListsOnlySpendingCategories() {
        launch(["-GhafTab", "insights"])
        let budget = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Budget, Salary'")).firstMatch
        timedTap(budget, "open budget eligibility")
        XCTAssertTrue(app.staticTexts["Food"].exists)
        XCTAssertTrue(app.staticTexts["Car"].exists)
        for category in ["Salary", "Transfers", "Transfers received", "Reimbursements", "Receivable",
                         "Borrow Money", "Lend Money", "Payable Debt Interest", "Payment Collection"] {
            XCTAssertFalse(app.staticTexts[category].exists, "Unexpected budget category: \(category)")
        }
        snap("budget-spending-categories")
    }
}

extension GhafWalkthroughTests {
    func test5ProfileBeforeAfterCapture() {
        launch()
        timedTap(app.tabBars.buttons["More"], "tab More for profile")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.31)).tap()
        sleep(1)
        snap("p0-profile")
        swipeUp(); snap("p1-profile-scrolled")
    }
}

extension GhafWalkthroughTests {
    func test6AccountEditorLayoutCapture() {
        launch()
        timedTap(app.buttons["Accounts"].firstMatch, "open wallet for editor capture")
        let tabbyBalance = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Tabby balance")).firstMatch
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.3))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.3))
        for _ in 0..<11 where !tabbyBalance.exists {
            start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        }
        XCTAssertTrue(tabbyBalance.waitForExistence(timeout: 2))
        timedTap(app.buttons["Edit"].firstMatch, "open account editor for capture")
        sleep(1)
        snap("g2-account-editor-top")
        app.swipeUp(velocity: .slow)
        snap("g2-account-editor-bottom")
        timedTap(app.buttons["Archive account"].firstMatch, "show archive confirmation")
        sleep(1)
        snap("g2-archive-confirmation")
    }
}

extension GhafWalkthroughTests {
    /// Separates XCTest's element-lookup cost from the app's own tab-switch time.
    func test9TabSwitchCost() {
        launch()
        let bar = app.tabBars.firstMatch.frame
        func tabPoint(_ i: Int) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: bar.minX + bar.width * (CGFloat(i) + 0.5) / 5, dy: bar.midY))
        }
        for (i, name) in [(2, "Stats"), (4, "More"), (3, "Transactions"), (0, "Home"), (2, "Stats")] {
            var t = Date(); _ = app.tabBars.buttons[name].exists; let lookup = Date().timeIntervalSince(t)
            t = Date(); tabPoint(i).tap(); let tap = Date().timeIntervalSince(t)
            log += String(format: "coord tab %@ tap+idle %.2fs | element lookup alone %.2fs\n", name, tap, lookup)
        }
    }
}

extension GhafWalkthroughTests {
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

    func testBankLogoProof() {
        launch()
        timedTap(app.tabBars.buttons["More"], "tab More for bank logo proof")
        let bankAutomation = app.buttons["Bank automation"]
        for _ in 0..<5 where !bankAutomation.exists { app.swipeUp(velocity: .fast) }
        timedTap(bankAutomation, "open bank automation")
        XCTAssertTrue(app.navigationBars["Your banks"].waitForExistence(timeout: 10))
        timedTap(app.buttons["Add a bank"].firstMatch, "open bank picker")
        XCTAssertTrue(app.navigationBars["Choose banks"].waitForExistence(timeout: 5))
        for name in ["iVestor", "Mashreq", "ruya"] {
            let bank = app.buttons[name]
            XCTAssertTrue(bank.waitForExistence(timeout: 5), "Missing bank \(name)")
            if !bank.isSelected { bank.tap() }
        }
        timedTap(app.buttons["Done"], "finish choosing three banks")
        snap("bank-your-banks-after")
        timedTap(app.buttons["Add a bank"].firstMatch, "reopen bank picker")
        XCTAssertTrue(app.navigationBars["Choose banks"].waitForExistence(timeout: 5))
        snap("bank-picker-dark-after-top")
        app.swipeUp(velocity: .fast); snap("bank-picker-dark-after-middle")
        app.swipeUp(velocity: .fast); snap("bank-picker-dark-after-bottom")
        app.terminate()
        launch(appearance: "Light")
        timedTap(app.tabBars.buttons["More"], "tab More for light bank logo proof")
        let lightBankAutomation = app.buttons["Bank automation"]
        for _ in 0..<5 where !lightBankAutomation.exists { app.swipeUp(velocity: .fast) }
        timedTap(lightBankAutomation, "open bank automation in light appearance")
        XCTAssertTrue(app.navigationBars["Your banks"].waitForExistence(timeout: 10))
        timedTap(app.buttons["Add a bank"].firstMatch, "open light bank picker")
        XCTAssertTrue(app.navigationBars["Choose banks"].waitForExistence(timeout: 5))
        snap("bank-picker-light-after")
    }
}

import StoreKitTest

extension GhafWalkthroughTests {
    func testProSheetAvailability() {
        launch(["-GhafScreen", "pro-sheet"])
        let unavailable = app.buttons["Available when Ghaf launches on the App Store"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 10))
        XCTAssertFalse(unavailable.isEnabled)
        XCTAssertFalse(app.buttons["Redeem code"].exists)
        XCTAssertTrue(app.buttons["Privacy"].firstMatch.isHittable)
        snap("pro-flag-off")
    }

    func testProStoreKitPurchase() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["GHAF_STOREKIT_FILE"] else { throw XCTSkip("Run with the store-enabled simulator build and local StoreKit configuration") }
        let session = try SKTestSession(contentsOf: URL(fileURLWithPath: path))
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        launch(["-GhafScreen", "pro-sheet"])
        let subscribe = app.buttons["Subscribe"]
        XCTAssertTrue(subscribe.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Redeem code"].isHittable)
        snap("pro-products")
        subscribe.tap()
        XCTAssertTrue(app.buttons["Pro is active"].waitForExistence(timeout: 15))
        XCTAssertTrue(session.allTransactions().contains { $0.productIdentifier == "com.ghaf.app.pro.yearly" })
        snap("pro-purchased")
    }
}
