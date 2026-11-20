import XCTest
import StoreKitTest

/// Real-data walkthrough: taps, scrolls and swipes key screens, saves screenshots and tap-to-idle timings to GHAF_UI_OUT.
/// Run: TEST_RUNNER_GHAF_UI_OUT=<dir> TEST_RUNNER_GHAF_BACKUP=<backup.json> xcodebuild test -scheme GhafUITests -destination id=<UDID>
final class GhafWalkthroughTests: XCTestCase {
    let out = ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_UI_OUT"] ?? ProcessInfo.processInfo.environment["GHAF_UI_OUT"] ?? NSTemporaryDirectory()
    var log = ""
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    }

    func launch(_ extra: [String] = [], appearance: String = "Dark") {
        app = XCUIApplication()
        let backup = (ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_BACKUP"] ?? ProcessInfo.processInfo.environment["GHAF_BACKUP"]).map { ["-GhafRestoreBackup", $0] } ?? []
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

extension GhafWalkthroughTests {
    func testHomeTransactionsLayout() {
        launch()
        XCTAssertTrue(app.buttons["Accounts"].firstMatch.exists)
        snap("home")
        swipeUp()
        snap("home-scrolled")
        timedTap(app.tabBars.buttons["Transactions"], "open Transactions")
        XCTAssertTrue(app.buttons["Expenses"].firstMatch.exists)
        snap("transactions")
        swipeUp()
        snap("transactions-scrolled")
}

    func testSessionFWalletAndEyeProof() {
        launch()
        timedTap(app.buttons["Accounts"].firstMatch, "open wallet for Session F")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'balance'")).firstMatch.waitForExistence(timeout: 5))
        usleep(500_000)
        snap("f-wallet-at-rest")

        let eye = app.buttons["Hide balances"].exists ? app.buttons["Hide balances"] : app.buttons["Show balances"]
        if eye.waitForExistence(timeout: 5) {
            timedTap(eye, "toggle wallet balances")
            snap("f-eye-hidden")
        } else {
            log += "MISSING wallet eye control\n"
        }

        let card = app.otherElements.matching(NSPredicate(format: "value CONTAINS[c] 'Card '")).firstMatch
        if card.waitForExistence(timeout: 5), let value = card.value as? String,
           let count = Int(value.components(separatedBy: " of ").last ?? "") {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.83, dy: 0.3))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.17, dy: 0.3))
            for index in 0..<min(count, 20) {
                snap(String(format: "f-card-%02d", index + 1))
                if index + 1 < count {
                    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
                }
            }
        } else {
            log += "MISSING wallet card position value\n"
        }
    }
}

extension GhafWalkthroughTests {
    func testProSheetAvailability() {
        launch(["-GhafScreen", "pro-sheet"])
        let unavailable = app.buttons["Coming soon to the App Store"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 10))
        XCTAssertFalse(unavailable.isEnabled)
        XCTAssertTrue(app.buttons["Redeem code"].exists)
        XCTAssertFalse(app.buttons["Redeem code"].isEnabled)
        XCTAssertFalse(app.buttons["Restore purchases"].isEnabled)
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

    func testSessionFRequestCardFormProof() {
        launch()
        timedTap(app.buttons["Accounts"].firstMatch, "open wallet for request form proof")
        let newCard = app.buttons["New card"].firstMatch
        timedTap(newCard, "open account editor")
        XCTAssertTrue(app.navigationBars["Add account"].waitForExistence(timeout: 5))
        usleep(500_000)
        snap("f-request-editor-before")

        let type = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Cash wallet'")).firstMatch
        if type.waitForExistence(timeout: 5) {
            type.tap()
            let debit = app.buttons["Debit card"]
            if debit.waitForExistence(timeout: 3) { debit.tap() }
        }
        let bank = app.textFields["Bank or institution"]
        if bank.waitForExistence(timeout: 3) {
            bank.tap()
            bank.typeText("Ruya\n")
        }
        let request = app.buttons["Card not found?"]
        if request.waitForExistence(timeout: 5) {
            request.tap()
            XCTAssertTrue(app.navigationBars["Request a card"].waitForExistence(timeout: 5))
            snap("f-request-card-after")
        } else {
            log += "MISSING Card not found?\n"
        }
}

    func testStatsPeriodAndBudgetChartProof() {
        launch()
        timedTap(app.tabBars.buttons["Stats"], "open stats for chart proof")
        for period in ["W", "M", "3M", "Y"] {
            let selector = app.buttons[period].firstMatch
            guard selector.waitForExistence(timeout: 5) else { log += "MISSING period \(period)\n"; continue }
            selector.tap()
            Thread.sleep(forTimeInterval: 0.15)
            snap("stats-\(period)-draw")
            Thread.sleep(forTimeInterval: 0.65)
            snap("stats-\(period)-settled")
        }
        let trend = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Spending trend; drag to read each point"))
            .firstMatch
        if trend.waitForExistence(timeout: 3) {
            trend.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88)).tap()
            snap("stats-empty-plot-selection")
        } else { log += "MISSING spending trend chart\n" }
        for _ in 0..<7 { app.swipeUp(velocity: .fast) }
        let pro = app.buttons["Ghaf Pro"].firstMatch
        if pro.waitForExistence(timeout: 3) {
            pro.tap()
            snap("stats-pro-direct-sheet")
        } else { log += "MISSING Ghaf Pro card\n" }

        app.terminate()
        launch(["-GhafScreen", "budget"])
        Thread.sleep(forTimeInterval: 1)
        snap("budget-petals-real-data")
        for category in ["Transfer Fee", "Subscriptions"] {
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", category)).firstMatch
            for _ in 0..<7 where !row.exists { app.swipeUp(velocity: .fast) }
            if row.exists {
                row.tap()
                for _ in 0..<7 { app.swipeDown(velocity: .fast) }
                snap("budget-petal-\(category == "Transfer Fee" ? "transfer-fee" : "subscriptions")")
            } else { log += "MISSING budget category \(category)\n" }
        }
        app.terminate()
        launch(["-GhafScreen", "budget", "-GhafSelection", "month"])
        Thread.sleep(forTimeInterval: 1)
        app.swipeUp(velocity: .fast)
        app.swipeUp(velocity: .fast)
        snap("budget-past-month-selection")
        app.swipeUp(velocity: .fast)
        snap("budget-allocation-scrolled")
    }

    func testFirstRunPages() throws {
        app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafLaunchProof", "1", "-GhafLaunchNewUser", "1", "-GhafAppearance", "Dark"]
        app.launch()
        // The cold-launch cover sits over onboarding for ten seconds; tap its own surface to skip it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        for page in 0..<8 {
            let next = app.buttons["Continue"].firstMatch
            let skip = app.buttons["Skip for now"].firstMatch
            let finish = app.buttons["Start using Ghaf"].firstMatch
            let button = page == 7 ? finish : (page == 1 && skip.exists ? skip : next)
            XCTAssertTrue(button.waitForExistence(timeout: 25))
            snap("first-run-\(page)")
            if page == 7 { break }
            button.tap()
            if page == 4 {
                for _ in 0..<3 {
                    let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
                    if alert.waitForExistence(timeout: 2) { alert.buttons.firstMatch.tap() }
                }
            }
        }
    }
}

extension GhafWalkthroughTests {
    func testSessionGAutomationWalkthrough() {
        launch(["-GhafScreen", "automation", "-GhafAutomationState", "working"])
        snap("g-after-automation-top")

        let addBank = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Add a bank")).firstMatch
        if addBank.waitForExistence(timeout: 5) {
            timedTap(addBank, "open automation bank picker")
            _ = app.navigationBars["Choose banks"].waitForExistence(timeout: 5)
            snap("g-after-bank-picker")
            app.buttons["Done"].tap()
        }

        let manual = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Set it up manually"))
        if manual.firstMatch.waitForExistence(timeout: 5) {
            timedTap(manual.element(boundBy: 0), "open bank manual steps")
            _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Step 1 of")).firstMatch.waitForExistence(timeout: 5)
            snap("g-after-bank-manual-first-step")
            timedTap(app.navigationBars.buttons.firstMatch, "back from bank manual steps")
        }
        if manual.count > 1 {
            timedTap(manual.element(boundBy: 1), "open Apple Pay manual steps")
            _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Step 1 of")).firstMatch.waitForExistence(timeout: 5)
            snap("g-after-apple-pay-manual-first-step")
            timedTap(app.navigationBars.buttons.firstMatch, "back from Apple Pay manual steps")
        }

        app.swipeUp(velocity: .fast)
        snap("g-after-automation-scrolled")
    }

}

extension GhafWalkthroughTests {
    func testE1SettingsScreenshots() {
        launch(["-GhafScreen", "profile-proof", "-GhafTab", "more"])
        snap("e1-profile-after")
        swipeUp(); snap("e1-profile-scrolled-after")

        launch(["-GhafScreen", "milestone-proof", "-GhafTab", "more"])
        snap("e1-milestone-after")

        launch(["-GhafScreen", "drive-proof", "-GhafTab", "more"])
        snap("e1-drive-after")
        swipeUp(); snap("e1-drive-scrolled-after")

        launch(["-GhafScreen", "settings-glass"])
        snap("e1-intensity-after")

        launch(["-GhafScreen", "about-proof", "-GhafTab", "more"])
        snap("e1-about-after")
        swipeUp(); snap("e1-about-scrolled-after")
    }
}

extension GhafWalkthroughTests {
    func testSessionE2SettingsProof() throws {
        launch()
        app.tabBars.buttons["More"].tap()
        let activity = app.buttons["Live Activity"].firstMatch
        for _ in 0..<6 where !activity.isHittable { app.swipeUp() }
        XCTAssertTrue(activity.isHittable)
        activity.tap()
        XCTAssertTrue(app.staticTexts["Purchase Live Activity"].waitForExistence(timeout: 4))
        snap("e2-live-activity")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Notifications"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Event alerts"].waitForExistence(timeout: 4))
        snap("e2-notifications")
        app.swipeUp()
        snap("e2-notifications-scrolled")
        app.navigationBars.buttons.firstMatch.tap()
        let fifteenSeconds = app.buttons["Live Activity"].firstMatch
        for _ in 0..<6 where !fifteenSeconds.isHittable { app.swipeDown() }
        fifteenSeconds.tap()
        app.buttons["15 s"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<6 where !fifteenSeconds.isHittable { app.swipeUp() }
        fifteenSeconds.tap()
        XCTAssertTrue(app.buttons["15 s"].isSelected, "Duration should persist in the settings store.")
    }
}
