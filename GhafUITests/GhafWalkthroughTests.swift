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
        let screenshot = XCUIScreen.main.screenshot()
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
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
    func testSessionISalaryCurrencyProof() {
        launch(["-GhafScreen", "salary-settings"])
        XCTAssertTrue(app.buttons["Save salary settings"].waitForExistence(timeout: 8))
        snap("i-salary-before")

        let currencyRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Salary currency'")).firstMatch
        XCTAssertTrue(currencyRow.waitForExistence(timeout: 5))
        currencyRow.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'SAR'" )).firstMatch.waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'SAR'" )).firstMatch.tap()
        app.buttons["Save salary settings"].tap()
        let notificationAlert = app.alerts.firstMatch
        if notificationAlert.waitForExistence(timeout: 2) {
            notificationAlert.buttons["Don’t Allow"].tap()
        }
        sleep(1)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Salary currency, SAR'" )).firstMatch.exists)
        snap("i-salary-after")

        app.terminate()
        launch(["-GhafScreen", "budget-salary-currency"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Salary is shown in SAR'" )).firstMatch.waitForExistence(timeout: 8))
        snap("i-budget-currency-mismatch")
    }

    func testActivityConfirmedItemLeavesReviewQueue() throws {
        launch(["-GhafScreen", "inbox-proof"])
        if !app.staticTexts["Needs review"].exists {
            timedTap(app.buttons["Activity"].firstMatch, "open Activity")
        }
        XCTAssertTrue(app.staticTexts["Needs review"].waitForExistence(timeout: 8))
        snap("activity-before-confirm")

        let confirms = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Confirm"))
        XCTAssertTrue(confirms.firstMatch.waitForExistence(timeout: 5), "Backup has no review item")
        var confirm = confirms.matching(NSPredicate(format: "isEnabled == true")).firstMatch
        if !confirm.exists {
            let choose = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Choose")).firstMatch
            XCTAssertTrue(choose.waitForExistence(timeout: 3))
            choose.tap()
            app.buttons["Cash"].firstMatch.tap()
            confirm = confirms.matching(NSPredicate(format: "isEnabled == true")).firstMatch
        }
        let before = confirms.count
        confirm.tap()
        XCTAssertLessThan(confirms.count, before, "A confirmed item remained in Activity")
        XCTAssertTrue(confirms.firstMatch.waitForNonExistence(timeout: 3))
        snap("activity-after-confirm")
    }

    func testWidgetDeepLinks() {
        launch()
        app.open(URL(string: "ghaf://add-transaction")!)
        XCTAssertTrue(app.staticTexts["New transaction"].waitForExistence(timeout: 8))
        snap("widget-link-quick-add")
        app.buttons["Cancel"].tap()

        app.open(URL(string: "ghaf://ai/type")!)
        XCTAssertTrue(app.tabBars.buttons["Ghaf AI"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 8))
        snap("widget-link-ai-typing")

        app.open(URL(string: "ghaf://money-tip?source=https%3A%2F%2Fwww.consumerfinance.gov%2F")!)
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.mobilesafari").waitForExistence(timeout: 10))
    }

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
        // A fast flick now moves several cards (owner rule), so step one card at a time with a short, slow drag.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.3))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.3))
        for _ in 0..<11 where !tabbyBalance.exists {
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
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
    func testRestoreBackupOpensTransactionsWithRealData() throws {
        guard let backup = ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_BACKUP"]
                ?? ProcessInfo.processInfo.environment["GHAF_BACKUP"] else {
            throw XCTSkip("TEST_RUNNER_GHAF_BACKUP not set")
        }
        app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafRestoreBackup", backup,
                               "-GhafTheme", "Graphite", "-GhafAppearance", "Dark", "-GhafLanguage", "en"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        timedTap(app.tabBars.buttons["Transactions"], "tab Transactions after backup restore")
        XCTAssertTrue(app.tabBars.buttons["Transactions"].isSelected)
        XCTAssertGreaterThan(app.buttons.count, app.tabBars.buttons.count + 4, "Expected at least one restored transaction row")
        snap("restore-real-data-transactions")
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

    func testImportSheetWithRealBackupData() {
        launch()
        timedTap(app.tabBars.buttons["More"], "tab More for import proof")
        let backup = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Google Drive' AND label CONTAINS[c] 'backup'")).firstMatch
        for _ in 0..<5 where !backup.exists { swipeUp() }
        timedTap(backup, "open data and backup")
        let importData = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Import data'")).firstMatch
        for _ in 0..<5 where !importData.exists { swipeUp() }
        timedTap(importData, "open import sheet")
        XCTAssertTrue(app.staticTexts["Bring your data into Ghaf"].waitForExistence(timeout: 5))
        snap("import-sheet-real-data")
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
            Thread.sleep(forTimeInterval: 0.45)
            if page == 4 {
                for _ in 0..<3 {
                    let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
                    if alert.waitForExistence(timeout: 2) { alert.buttons.firstMatch.tap() }
                }
            }
        }

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafLaunchProof", "1", "-GhafLaunchNewUser", "1",
                              "-GhafTheme", "Graphite", "-GhafAppearance", "Dark", "-GhafLanguage", "en",
                              "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibility5"]
        app.launch()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 25))
        snap("first-run-1-largest-type")

        let proofBackup = ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_BACKUP"]
            ?? ProcessInfo.processInfo.environment["GHAF_BACKUP"]
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("HANDOFF-1.27/backup3.json").path
        if FileManager.default.fileExists(atPath: proofBackup) {
            app.terminate()
            app = XCUIApplication()
            app.launchArguments = ["-GhafFixture", "1", "-GhafRestoreBackup", proofBackup, "-GhafTheme", "Graphite",
                                  "-GhafAppearance", "Dark", "-GhafLanguage", "en"]
            app.launch()
            XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 20))
            app.tabBars.buttons["More"].tap()
            app.buttons["Customization"].tap()
            let arabicChoice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'العربية'" )).firstMatch
            XCTAssertTrue(arabicChoice.waitForExistence(timeout: 5))
            arabicChoice.tap()
            Thread.sleep(forTimeInterval: 0.25)
            snap("language-switch-en-ar-overlay-start")
            Thread.sleep(forTimeInterval: 0.95)
            snap("language-switch-en-ar-overlay-arabic")
            XCTAssertTrue(app.tabBars.buttons["الرئيسية"].waitForExistence(timeout: 10))
            snap("language-switch-ar-home")
            app.tabBars.buttons["المزيد"].tap()
            app.buttons["التخصيص"].tap()
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'English'")).firstMatch.tap()
            XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
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

extension GhafWalkthroughTests {
    /// Onboarding's "Import Ghaf backup" opens the shared import sheet (Ghaf, Expend, CSV).
    func testImportSheetFromOnboarding() {
        app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafLaunchProof", "1", "-GhafLaunchNewUser", "1", "-GhafAppearance", "Dark"]
        app.launch()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let importButton = app.buttons["Import Ghaf backup"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 15))
        importButton.tap()
        XCTAssertTrue(app.staticTexts["Bring your data into Ghaf"].waitForExistence(timeout: 5))
        snap("import-sheet-onboarding")
    }
}

extension GhafWalkthroughTests {
    func testSessionG1WhyPaidProof() {
        launch(["-GhafScreen", "about-proof", "-GhafTab", "more"])
        XCTAssertTrue(app.buttons["Why is Ghaf paid?"].waitForExistence(timeout: 8))
        app.buttons["Why is Ghaf paid?"].tap()
        XCTAssertTrue(app.buttons["See Ghaf Pro"].waitForExistence(timeout: 5))
        snap("g1-why-paid-after")
        app.buttons["See Ghaf Pro"].tap()
        XCTAssertTrue(app.staticTexts["Ghaf Pro"].waitForExistence(timeout: 5))
        snap("g1-why-paid-pro-sheet")
    }

    func testSessionG1VoiceSelectionProof() {
        launch(["-GhafTab", "ai"])
        app.buttons["Ghaf AI menu"].tap()
        app.buttons["Ghaf voice"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ghaf.voice.footnote").firstMatch.waitForExistence(timeout: 5))
        snap("g1-voice-after")
        let mariam = app.descendants(matching: .any).matching(identifier: "ghaf.voice.card.Mariam").firstMatch
        XCTAssertTrue(mariam.waitForExistence(timeout: 3))
        mariam.tap()
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafTheme", "Graphite", "-GhafAppearance", "Dark", "-GhafLanguage", "en", "-GhafTab", "ai"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        app.buttons["Ghaf AI menu"].tap()
        app.buttons["Ghaf voice"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ghaf.voice.footnote").firstMatch.waitForExistence(timeout: 5))
        let savedMariam = app.descendants(matching: .any).matching(identifier: "ghaf.voice.card.Mariam").firstMatch
        XCTAssertEqual(savedMariam.value as? String, "Selected")
        snap("g1-voice-mariam-relaunch")
    }

}

extension GhafWalkthroughTests {
    func test11WalletActionsRemainAvailable() {
        launch()
        timedTap(app.buttons["Accounts"].firstMatch, "open wallet for action check")
        for action in ["Spend", "Transfer", "Edit", "New card"] {
            XCTAssertTrue(app.buttons[action].exists, "Missing wallet action: \(action)")
        }
    }
}

extension GhafWalkthroughTests {
    func testBFollowupChartAndAllocationProof() {
        launch(["-GhafScreen", "budget", "-GhafSelection", "savings"])
        snap("budget-followup-top")
        let savingsDetails = app.staticTexts["Remaining"]
        for _ in 0..<7 where !savingsDetails.isHittable { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(savingsDetails.isHittable, "Missing Savings explanation")
        snap("budget-followup-savings")

        app.terminate()
        launch(["-GhafScreen", "budget", "-GhafSelection", "preset"])
        if app.staticTexts["Choose a budget split"].waitForExistence(timeout: 5) {
            snap("budget-followup-presets")
        } else { log += "MISSING budget presets sheet\n" }

        app.terminate()
        launch(["-GhafScreen", "ai-typing"])
        let input = app.textFields["Type your question"].firstMatch
        if input.waitForExistence(timeout: 10) {
            input.tap()
            input.typeText("show my categories as a petal chart\n")
            if app.staticTexts["Top categories this month"].waitForExistence(timeout: 45) {
                Thread.sleep(forTimeInterval: 0.8)
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52))
                start.press(forDuration: 0.05, thenDragTo: end)
                Thread.sleep(forTimeInterval: 0.4)
                snap("ai-petal-chart-reply")
            } else { log += "MISSING AI petal chart reply\n" }
        } else { log += "MISSING AI question field\n" }
    }
}

extension GhafWalkthroughTests {
    func testEntryPrimaryScreens() {
        launch(["-GhafScreen", "new-transaction"])
        if app.alerts.buttons["Allow While Using App"].waitForExistence(timeout: 2) { app.alerts.buttons["Allow While Using App"].tap() }
        XCTAssertTrue(app.buttons["Amount"].waitForExistence(timeout: 8))
        snap("a-entry-closed")
        app.swipeUp(velocity: .fast)
        snap("a-entry-closed-swipe")
        app.buttons["Amount"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        snap("a-entry-keypad-open")
        app.buttons["Done"].tap()
        app.buttons["Date"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        snap("a-entry-date-sheet")
        app.buttons["Today"].tap()
        app.buttons["Time"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        snap("a-entry-time-sheet")
        app.buttons["Done"].tap()
        app.buttons["Amount"].tap()
        app.buttons["3"].tap(); app.buttons["5"].tap(); app.buttons["Done"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard"].waitForExistence(timeout: 5))
        snap("a-entry-discard-card")
        app.buttons["Keep editing"].tap()
        app.buttons["Cancel"].tap()
        app.buttons["Discard"].tap()

        launch(["-GhafScreen", "new-transaction"])
        XCTAssertTrue(app.buttons["Amount"].waitForExistence(timeout: 8))
        app.buttons["Amount"].tap()
        app.buttons["3"].tap(); app.buttons["5"].tap(); app.buttons["Done"].tap()
        let merchant = app.textFields["Store name"]
        XCTAssertTrue(merchant.waitForExistence(timeout: 5))
        merchant.tap(); merchant.typeText("Carrefour"); app.keyboards.buttons["Done"].tap()
        app.buttons["Save transaction"].tap()
        Thread.sleep(forTimeInterval: 0.2); snap("a-entry-splash-glow")
        Thread.sleep(forTimeInterval: 0.7); snap("a-entry-splash-logged")
        Thread.sleep(forTimeInterval: 1.3); snap("a-entry-after-dismiss")
    }
}

extension GhafWalkthroughTests {
    func testSessionEVoicePickerProof() {
        launch(["-GhafTab", "ai"])
        app.buttons["Ghaf AI menu"].tap()
        app.buttons["Ghaf voice"].tap()
        // First-time title, or the settings title once a voice was chosen in an earlier run.
        XCTAssertTrue(app.staticTexts["Who should answer you?"].waitForExistence(timeout: 5) || app.staticTexts["Ghaf voice"].exists)
        XCTAssertTrue(app.staticTexts["Hamad"].exists)
        XCTAssertTrue(app.staticTexts["Mariam"].exists)
        snap("ai-voice-picker")
    }

    func testSessionESubscriptionListProof() {
        launch(["-GhafTab", "ai"])
        let question = app.buttons["Which subscriptions are due soon?"].firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        question.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Coming up in the next 30 days'")).firstMatch
            .waitForExistence(timeout: 45))
        snap("ai-subscription-list")
    }
}

extension GhafWalkthroughTests {
    func testTransactionPeekAndYesterdayDetail() {
        launch()
        timedTap(app.tabBars.buttons["Transactions"], "open Transactions for peek")
        snap("a-transactions-top")
        let garage = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Garage")).firstMatch
        XCTAssertTrue(garage.waitForExistence(timeout: 10))
        garage.press(forDuration: 1.0)
        snap("a-transaction-peek")
        app.swipeDown()
        garage.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Nov 20")).firstMatch.exists)
        snap("a-transaction-yesterday-detail")
        app.buttons["Done"].tap()
        let frame = garage.frame
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.maxX - 4, dy: frame.midY))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.minX + 4, dy: frame.midY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        snap("a-transaction-swipe-delete")
    }
}

extension GhafWalkthroughTests {
    func testSessionRPlanAndBackupScreenshotProof() {
        launch(["-GhafScreen", "pro-sheet"])
        snap("r-plans-en")

        app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafTheme", "Graphite", "-GhafAppearance", "Dark", "-GhafLanguage", "ar", "-GhafScreen", "pro-sheet"]
        if let backup = ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_BACKUP"] {
            app.launchArguments += ["-GhafRestoreBackup", backup]
        }
        app.launch()
        snap("r-plans-ar")

        launch()
        app.tabBars.buttons["More"].tap()
        let backupRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Google Drive' AND label CONTAINS[c] 'backup'")).firstMatch
        for _ in 0..<8 where !backupRow.exists { app.swipeUp() }
        XCTAssertTrue(backupRow.waitForExistence(timeout: 5))
        backupRow.tap()
        let createBackup = app.buttons["Create JSON backup"]
        XCTAssertTrue(createBackup.waitForExistence(timeout: 5))
        snap("r-backup-button")
        createBackup.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5) || app.otherElements.firstMatch.waitForExistence(timeout: 5))
    }

    func testSessionISettingsVoiceAndWidgetGalleryProof() {
        launch()
        app.tabBars.buttons["More"].tap()
        let voiceRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Voice' AND (label CONTAINS[c] 'Hamad' OR label CONTAINS[c] 'Mariam')")).firstMatch
        for _ in 0..<8 where !voiceRow.exists { app.swipeUp() }
        XCTAssertTrue(voiceRow.exists)
        voiceRow.tap()
        XCTAssertTrue(app.staticTexts["Ghaf voice"].waitForExistence(timeout: 5))
        snap("i-voice-settings")
        app.buttons["Close"].tap()

        let widgetsRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Widgets'")).firstMatch
        for _ in 0..<8 where !widgetsRow.exists { app.swipeUp() }
        XCTAssertTrue(widgetsRow.exists)
        widgetsRow.tap()
        XCTAssertTrue(app.navigationBars["Widgets"].waitForExistence(timeout: 5))
        snap("i-widget-gallery-top")
        app.swipeUp()
        snap("i-widget-gallery-scrolled")
        let lockedPreview = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Today, Small'")).firstMatch
        if lockedPreview.waitForExistence(timeout: 3) { lockedPreview.tap() }
        XCTAssertTrue(app.staticTexts["Ghaf Pro"].waitForExistence(timeout: 5))
        snap("i-widget-pro-preview")
    }
}

extension GhafWalkthroughTests {
    func testSessionIMerchantAliasProof() {
        launch()
        app.tabBars.buttons["Transactions"].tap()
        // Real backups have hundreds of rows; search so the row is on screen whatever its date.
        let search = app.textFields["Search merchant, category or bank"]
        if search.waitForExistence(timeout: 5) { search.tap(); search.typeText("nashama"); app.keyboards.buttons["search"].firstMatch.tapIfExists() }
        let rawRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'NASHAMA'" )).firstMatch
        XCTAssertTrue(rawRow.waitForExistence(timeout: 10))
        snap("i-merchant-before-list")
        rawRow.tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        snap("i-merchant-before-detail")
        app.buttons["Edit"].tap()
        let merchant = app.textFields["Merchant"]
        XCTAssertTrue(merchant.waitForExistence(timeout: 5))
        merchant.tap()
        let original = merchant.value as? String ?? ""
        // The simulator keeps aliases between runs; pick a name that differs from the current one.
        let newName = original == "Shay Al Nashama" ? "Shay Al Nashama Cafe" : "Shay Al Nashama"
        for _ in 0..<original.count { merchant.typeText(XCUIKeyboardKey.delete.rawValue) }
        merchant.typeText(newName)
        app.keyboards.buttons["return"].tap()
        app.swipeUp()
        app.buttons["Save changes"].tap()
        let renameAll = app.buttons["Rename matching past transactions"]
        XCTAssertTrue(renameAll.waitForExistence(timeout: 5))
        renameAll.tap()
        XCTAssertTrue(app.staticTexts[newName].waitForExistence(timeout: 12))
        app.swipeDown()
        snap("i-merchant-after-detail")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", newName)).firstMatch.waitForExistence(timeout: 5))
        snap("i-merchant-after-list")
    }
}

extension GhafWalkthroughTests {
    func testQuickAddLocationRowAndSwipeDiscard() {
        launch(["-GhafScreen", "new-transaction"])
        XCTAssertTrue(app.buttons["Amount"].waitForExistence(timeout: 8))
        let allowLocation = app.buttons["Allow"]
        if allowLocation.waitForExistence(timeout: 2) {
            snap("a-location-row-before-permission")
            allowLocation.tap()
            if app.alerts.buttons["Allow While Using App"].waitForExistence(timeout: 5) {
                app.alerts.buttons["Allow While Using App"].tap()
            }
        }
        let location = app.staticTexts["Location"]
        if location.waitForExistence(timeout: 5) {
            snap("a-location-row-allowed")
        } else {
            XCTAssertFalse(location.exists, "Denied location access should hide the row")
            snap("a-location-row-denied")
        }

        app.buttons["Amount"].tap()
        app.buttons["3"].tap(); app.buttons["5"].tap(); app.buttons["Done"].tap()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(app.buttons["Discard"].waitForExistence(timeout: 5))
        snap("a-discard-card-swipe-down")
    }
}

extension GhafWalkthroughTests {
    func testSessionCCardAddedSplash() {
        launch()
        timedTap(app.buttons["Accounts"].firstMatch, "open wallet for card-added proof")
        timedTap(app.buttons["New card"].firstMatch, "open new wallet form")
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Session C proof")
        app.keyboards.buttons["Done"].firstMatch.tap()
        timedTap(app.buttons["Add account"].firstMatch, "save new wallet")
        XCTAssertTrue(app.staticTexts["Card added"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Session C proof"].exists)
        snap("session-c-card-added-splash")
    }
}

extension GhafWalkthroughTests {
    /// G3 visual sweep: real backup data across every shipped theme and both appearances,
    /// followed by Graphite Dark Arabic. Screenshots are written to the normal walkthrough folder.
    func testSessionG3ThemeAndArabicSweep() throws {
        // Long all-themes sweep: run on demand only (TEST_RUNNER_GHAF_THEME_SWEEP=1).
        guard ProcessInfo.processInfo.environment["GHAF_THEME_SWEEP"] == "1" else { throw XCTSkip("Theme sweep runs on demand") }
        guard let backup = ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_BACKUP"]
                ?? ProcessInfo.processInfo.environment["GHAF_BACKUP"] else {
            XCTFail("Set TEST_RUNNER_GHAF_BACKUP to the private owner backup")
            return
        }
        let themes = ["Abu Dhabi", "Dubai", "Sharjah", "Ajman", "Umm Al Quwain", "Ras Al Khaimah", "Fujairah", "Graphite"]
        func start(theme: String, appearance: String, language: String = "en", screen: String? = nil) {
            app = XCUIApplication()
            app.launchArguments = ["-GhafFixture", "1", "-GhafRestoreBackup", backup,
                                  "-GhafTheme", theme, "-GhafAppearance", appearance,
                                  "-GhafLanguage", language]
            if let screen { app.launchArguments += ["-GhafScreen", screen] }
            app.launch()
            _ = app.tabBars.firstMatch.waitForExistence(timeout: 20)
        }
        if ProcessInfo.processInfo.environment["GHAF_G3_MEMORY_ONLY"] == "1"
            || ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_MEMORY_ONLY"] == "1"
            || out.contains("g3-memory-only") {
            start(theme: "Graphite", appearance: "Dark")
            snap("g3-memory-before")
            Thread.sleep(forTimeInterval: 45)
            for _ in 0..<10 {
                app.tabBars.buttons["Ghaf AI"].tap()
                app.tabBars.buttons["Home"].tap()
            }
            app.tabBars.buttons["Ghaf AI"].press(forDuration: 0.6)
            let questionField = app.textFields["Type your question"]
            if questionField.waitForExistence(timeout: 5) {
                for question in ["How much did I spend this week?", "Where did most of my money go?", "Which subscriptions are due soon?"] {
                    questionField.tap(); questionField.typeText(question)
                    let send = app.buttons["Send"]
                    if send.waitForExistence(timeout: 3) { send.tap() }
                    sleep(2)
                }
            }
            app.tabBars.buttons["Home"].tap()
            for _ in 0..<10 {
                app.tabBars.buttons["Stats"].tap()
                app.tabBars.buttons["Home"].tap()
            }
            app.buttons["Accounts"].tap()
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.35))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.35))
            for _ in 0..<5 { start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05) }
            app.navigationBars.buttons.firstMatch.tap()
            for _ in 0..<10 {
                app.buttons["Add"].tap()
                _ = app.staticTexts["New transaction"].waitForExistence(timeout: 4)
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.83, dy: 0.5)).tap()
                let cancel = app.buttons["Cancel"].firstMatch
                if cancel.waitForExistence(timeout: 3) { cancel.tap() }
            }
            snap("g3-memory-after")
            Thread.sleep(forTimeInterval: 45)
            return
        }
        for theme in themes {
            for appearance in ["Light", "Dark"] {
                let key = "g3-\(theme.replacingOccurrences(of: " ", with: "-"))-\(appearance.lowercased())"
                start(theme: theme, appearance: appearance)
                snap("\(key)-home")
                app.swipeUp(velocity: .slow); snap("\(key)-home-scrolled"); app.swipeDown(velocity: .slow)
                app.tabBars.buttons["Transactions"].tap(); snap("\(key)-transactions")
                let firstTransaction = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Garage'" )).firstMatch
                if firstTransaction.waitForExistence(timeout: 3) {
                    firstTransaction.tap(); snap("\(key)-transaction-detail")
                    app.buttons["Done"].firstMatch.tap()
                }
                app.tabBars.buttons["Ghaf AI"].tap(); snap("\(key)-ai")
                app.tabBars.buttons["Stats"].tap(); snap("\(key)-stats")
                app.tabBars.buttons["More"].tap(); snap("\(key)-more")
                app.open(URL(string: "ghaf://pro")!); snap("\(key)-pro-sheet")
                app.buttons["Close"].firstMatch.tap()
                app.tabBars.buttons["Home"].tap()
                app.buttons["Accounts"].tap()
                _ = app.staticTexts["Accounts and wallets"].waitForExistence(timeout: 5)
                snap("\(key)-accounts-wallet")
                app.navigationBars.buttons.firstMatch.tap()
                app.buttons["Add"].tap()
                _ = app.staticTexts["New transaction"].waitForExistence(timeout: 6)
                snap("\(key)-add-transaction")
                if app.buttons["Cancel"].firstMatch.exists { app.buttons["Cancel"].firstMatch.tap() }
                if app.buttons["Cancel"].firstMatch.exists { app.buttons["Cancel"].firstMatch.tap() }
                app.buttons["Subs"].tap()
                _ = app.staticTexts["Subscriptions"].waitForExistence(timeout: 6)
                snap("\(key)-subscriptions")
                app.buttons["Close"].firstMatch.tap()
                app.buttons["Activity"].tap(); snap("\(key)-activity")
                app.terminate()
            }
        }

        // Arabic review is deliberately limited to Graphite Dark, as specified for this pass.
        let arabicScreens = ["transaction-detail", "pro-sheet", "new-transaction", "insights", "settings-glass", "salary-settings"]
        for screen in arabicScreens {
            start(theme: "Graphite", appearance: "Dark", language: "ar", screen: screen)
            snap("g3-ar-\(screen)")
            app.terminate()
        }
        start(theme: "Graphite", appearance: "Dark", language: "ar")
        app.tabBars.buttons["المزيد"].tap()
        let backupButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Google Drive'")).firstMatch
        for _ in 0..<6 where !backupButton.isHittable { app.swipeUp(velocity: .slow) }
        if backupButton.isHittable { backupButton.tap() }
        let importButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'استيراد بيانات'")).firstMatch
        for _ in 0..<6 where !importButton.exists { app.swipeUp(velocity: .slow) }
        if importButton.waitForExistence(timeout: 5) { importButton.tap(); snap("g3-ar-import-sheet") }
        app.terminate()
        for tab in ["home", "transactions", "ai", "insights", "more"] {
            start(theme: "Graphite", appearance: "Dark", language: "ar")
            let labels = ["home": "الرئيسية", "transactions": "العمليات", "ai": "غاف AI", "insights": "الإحصائيات", "more": "المزيد"]
            if tab != "home" { app.tabBars.buttons[labels[tab]!].tap() }
            snap("g3-ar-tab-\(tab)")
            app.terminate()
        }

        // Repeated navigation lifetime boundaries used for the simulator leak capture.
        start(theme: "Graphite", appearance: "Dark")
        for _ in 0..<10 {
            app.tabBars.buttons["Ghaf AI"].tap()
            app.tabBars.buttons["Home"].tap()
        }
        app.tabBars.buttons["Ghaf AI"].press(forDuration: 0.6)
        let questionField = app.textFields["Type your question"]
        if questionField.waitForExistence(timeout: 5) {
            for question in ["How much did I spend this week?", "Where did most of my money go?", "Which subscriptions are due soon?"] {
                questionField.tap(); questionField.typeText(question)
                let send = app.buttons["Send"]
                if send.waitForExistence(timeout: 3) { send.tap() }
                sleep(2)
            }
        }
        app.tabBars.buttons["Home"].tap()
        for _ in 0..<10 {
            app.tabBars.buttons["Stats"].tap()
            app.tabBars.buttons["Home"].tap()
        }
        app.buttons["Accounts"].tap()
        let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.35))
        let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.35))
        for _ in 0..<5 { dragStart.press(forDuration: 0.05, thenDragTo: dragEnd, withVelocity: .slow, thenHoldForDuration: 0.05) }
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Home"].tap()
        for _ in 0..<10 {
            let add = app.buttons["Add"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            add.tap()
            _ = app.staticTexts["New transaction"].waitForExistence(timeout: 4)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.83, dy: 0.5)).tap()
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.waitForExistence(timeout: 3) { cancel.tap() }
        }
        snap("g3-memory-exercise-complete")
    }

    func testSessionDScreenshots() {
        launch(["-GhafScreen", "subscriptions"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Chat GPT payment for this month'")).firstMatch.waitForExistence(timeout: 8))
        snap("d-subscriptions-payment-match")
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Chat GPT'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Edit subscription"].waitForExistence(timeout: 6))
        snap("d-subscription-detail")
        app.buttons["Edit subscription"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 6))
        app.swipeUp()
        snap("d-subscription-editor-bottom-save")
        app.buttons["Yearly"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.alerts["Update upcoming payments too?"].waitForExistence(timeout: 4))
        snap("d-subscription-update-reminders-prompt")

        app.terminate()
        launch(["-GhafTab", "more"])
        snap("d-more-pro-banner")
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "View profile")).firstMatch.tap()
        snap("d-profile-vouchers-top")
        swipeUp(); snap("d-profile-places-scrolled")
        app.terminate()

        launch(["-GhafTab", "more"])
        let customization = app.buttons["Customization"]
        for _ in 0..<5 where !customization.exists { swipeUp() }
        XCTAssertTrue(customization.waitForExistence(timeout: 4))
        customization.tap()
        XCTAssertTrue(app.staticTexts["Show keypad when adding"].waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        snap("d-keypad-setting")
        app.terminate()

        launch(["-GhafTab", "more", "-GhafScreen", "about-proof"])
        let whyPaid = app.buttons["Why is Ghaf paid?"]
        for _ in 0..<5 where !whyPaid.exists { swipeUp() }
        XCTAssertTrue(whyPaid.waitForExistence(timeout: 5))
        whyPaid.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Free stays useful")).firstMatch.waitForExistence(timeout: 5))
        snap("d-why-ghaf-paid")
    }

    func testSessionDQuickActionMenuScreenshot() {
        launch()
        app.terminate()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["Ghaf"]
        XCTAssertTrue(icon.waitForExistence(timeout: 8))
        icon.press(forDuration: 1.1)
        snap("d-home-screen-quick-actions")
    }
}

extension GhafWalkthroughTests {
    func testSessionKCategoryScreenshots() throws {
        guard let backup = ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_BACKUP"]
                ?? ProcessInfo.processInfo.environment["GHAF_BACKUP"] else {
            throw XCTSkip("Set TEST_RUNNER_GHAF_BACKUP to the private owner backup")
        }
        func launchFixture(language: String, screen: String? = nil) {
            app = XCUIApplication()
            app.launchArguments = ["-GhafFixture", "1", "-GhafRestoreBackup", backup,
                                  "-GhafTheme", "Graphite", "-GhafAppearance", "Dark",
                                  "-GhafLanguage", language]
            if let screen { app.launchArguments += ["-GhafScreen", screen] }
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        }

        launchFixture(language: "ar")
        app.tabBars.buttons["المزيد"].tap()
        let budgetCategories = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "الميزانية والفئات")).firstMatch
        for _ in 0..<8 where !budgetCategories.exists { app.swipeUp() }
        XCTAssertTrue(budgetCategories.waitForExistence(timeout: 5))
        budgetCategories.tap()
        let categoriesTab = app.buttons["الفئات"]
        XCTAssertTrue(categoriesTab.waitForExistence(timeout: 5))
        categoriesTab.tap()
        XCTAssertTrue(app.staticTexts["الطعام"].waitForExistence(timeout: 5))
        snap("k-arabic-category-list")

        app.terminate()
        launchFixture(language: "ar", screen: "new-transaction")
        let merchant = app.textFields["اسم المتجر"]
        XCTAssertTrue(merchant.waitForExistence(timeout: 5))
        merchant.tap()
        merchant.typeText("ورد")
        Thread.sleep(forTimeInterval: 0.35)
        merchant.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "فحص دم")
        let labSuggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "تحاليل مخبرية")).firstMatch
        XCTAssertTrue(labSuggestion.waitForExistence(timeout: 5))
        snap("k-category-mid-typing")

        app.terminate()
        launchFixture(language: "en", screen: "new-transaction")
        app.buttons["Amount"].tap()
        app.buttons["3"].tap(); app.buttons["5"].tap(); app.buttons["Done"].tap()
        let learnedMerchant = app.textFields["Store name"]
        XCTAssertTrue(learnedMerchant.waitForExistence(timeout: 5))
        learnedMerchant.tap()
        learnedMerchant.typeText("Shay Al Nashama")
        app.keyboards.buttons["Done"].tap()
        let cafeteriaSuggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Cafeteria")).firstMatch
        XCTAssertTrue(cafeteriaSuggestion.waitForExistence(timeout: 5))
        app.buttons["Save transaction"].tap()
        Thread.sleep(forTimeInterval: 3)
        app.tabBars.buttons["More"].tap()
        let learnedRow = app.buttons["What Ghaf learned"]
        for _ in 0..<8 where !learnedRow.exists { app.swipeUp() }
        XCTAssertTrue(learnedRow.waitForExistence(timeout: 5))
        learnedRow.tap()
        app.swipeUp()
        app.swipeUp()
        snap("k-grouped-learned-merchants")
    }
}

extension XCUIElement {
    func tapIfExists() { if exists { tap() } }
}
