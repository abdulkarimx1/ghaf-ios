import XCTest

/// Locks owner-approved 1.31 behaviours: undoable delete, stats "View transactions", per-currency wallet total.
final class GhafOwnerRules131Tests: XCTestCase {
    private func launch(_ extra: [String] = [], waitTabBar: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafTheme", "Graphite",
                               "-GhafAppearance", "Light", "-GhafLanguage", "en"] + extra
        app.launch()
        if waitTabBar { XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30)) }
        return app
    }

    private func carrefourRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Carrefour"))
    }

    func testOwnerRule_PrivacyAPIsHaveUsageDescriptionsAndCameraFallbackDoesNotCrash() throws {
        let app = launch(["-GhafTab", "more"])
        app.buttons["Profile photo options"].tap()
        XCTAssertTrue(app.staticTexts["Profile photo"].waitForExistence(timeout: 5))
        let camera = app.buttons["Take photo"]
        if camera.exists {
            camera.tap()
            XCTAssertEqual(app.state, .runningForeground, "Opening the available simulator camera must not terminate Ghaf")
            XCTAssertFalse(app.staticTexts["Profile photo"].exists, "The camera picker should replace the photo action sheet")
        } else {
            XCTAssertTrue(app.staticTexts["Profile photo"].exists, "When the source is unavailable, keep the fallback photo menu open")
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testOwnerRule_ArabicStatsPeriodsKeepAmountAtFixedHeight() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafScreen", "insights", "-GhafPeriod", "M",
                               "-GhafTheme", "Graphite", "-GhafAppearance", "Light", "-GhafLanguage", "ar"]
        app.launch()
        let amount = app.descendants(matching: .any).matching(identifier: "stats.period.spent").firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 30))
        let y = amount.frame.minY
        for index in 0..<4 {
            let period = app.buttons["stats.period.\(index)"]
            XCTAssertTrue(period.waitForExistence(timeout: 5), "Missing period identifier index \(index)")
            period.tap()
            XCTAssertEqual(amount.frame.minY, y, accuracy: 2, "The amount container moved for period index \(index)")
        }
    }

    func testWave3ActivityCountsMatchSeededLedgerAndSchedule() throws {
        let app = launch()
        let activity = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Activity")).firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 10))
        activity.tap()
        XCTAssertTrue(app.buttons["activity.count.review"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["activity.count.due-soon"].exists)
        XCTAssertTrue(app.buttons["activity.count.budget"].exists)
        XCTAssertTrue(app.buttons["0 to review"].exists, "Fixture review queue has no pending transactions")
        XCTAssertTrue(app.buttons["2 due soon"].exists, "Two seeded active subscriptions are due within seven days")
        XCTAssertTrue(app.buttons["0 budget alerts"].exists, "Fixture BudgetCalculator status is comfortable")
    }

    func testWave3BudgetThreeRowsStayVisibleWithoutRolling() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafScreen", "budget-salary-currency",
                               "-GhafTheme", "Graphite", "-GhafAppearance", "Light", "-GhafLanguage", "en"]
        app.launch()
        let rows = ["needs", "wants", "savings"].map { app.buttons["budget.allocation.\($0)"] }
        for row in rows { XCTAssertTrue(row.waitForExistence(timeout: 30)) }
        let initialY = rows.map { $0.frame.minY }
        Thread.sleep(forTimeInterval: 2.5)
        for (index, row) in rows.enumerated() {
            XCTAssertEqual(row.frame.minY, initialY[index], accuracy: 1, "A three-row budget must stay visible without rolling")
        }
    }


    func testOwnerRule_InactivityRestartRefreshesAndSkipsOpenTransactionSheet() throws {
        let app = XCUIApplication()
        let splash = app.descendants(matching: .any).matching(identifier: "ghaf.launch.splash").firstMatch
        app.launchArguments = ["-GhafFixture", "1", "-GhafLaunchProof", "1", "-GhafInactivityRestartAfter5Seconds"]
        app.launch()
        XCTAssertTrue(splash.waitForExistence(timeout: 30))
        splash.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let automationDone = app.buttons["Done"]
        if automationDone.waitForExistence(timeout: 3) { automationDone.tap() }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 6)
        app.activate()
        XCTAssertTrue(splash.waitForExistence(timeout: 2), "A long background return should show the launch splash")
        splash.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if automationDone.waitForExistence(timeout: 3) { automationDone.tap() }

        if automationDone.waitForExistence(timeout: 3) { automationDone.tap() }
        let add = app.buttons["Add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let merchant = app.textFields["home.quick-add.merchant"]
        XCTAssertTrue(merchant.waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 6)
        app.activate()
        XCTAssertTrue(merchant.waitForExistence(timeout: 5), "The transaction editor must stay open after the threshold")
        XCTAssertFalse(splash.exists, "An open transaction sheet must suppress the restart splash")
    }

    func testOwnerRule_TrendDrawRecordingEnglish() throws {
        recordTrendDraw(language: "en")
    }

    func testOwnerRule_TrendDrawRecordingArabic() throws {
        recordTrendDraw(language: "ar")
    }

    private func recordTrendDraw(language: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafScreen", "insights", "-GhafPeriod", "W",
                               "-GhafTheme", "Graphite", "-GhafAppearance", "Light", "-GhafLanguage", language]
        app.launch()
        let amount = app.descendants(matching: .any).matching(identifier: "stats.period.spent").firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 30))
        let month = app.buttons["stats.period.1"]
        XCTAssertTrue(month.waitForExistence(timeout: 10))
        if !month.isHittable { app.swipeUp() }
        XCTAssertTrue(month.isHittable, "The period control should be visible with the Stats chart")
        Thread.sleep(forTimeInterval: 1)
        month.tap()
        Thread.sleep(forTimeInterval: 1)
    }

    func testOwnerRule_FastChartScrubsKeepStatsLayoutStill() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafScreen", "insights", "-GhafPeriod", "M",
                               "-GhafTheme", "Graphite", "-GhafAppearance", "Light", "-GhafLanguage", "en"]
        app.launch()
        let amount = app.descendants(matching: .any).matching(identifier: "stats.period.spent").firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 30))
        let amountY = amount.frame.minY
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.54))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.84, dy: 0.54))
        for _ in 0..<3 {
            start.press(forDuration: 0.05, thenDragTo: right)
            right.press(forDuration: 0.05, thenDragTo: start)
        }
        XCTAssertEqual(amount.frame.minY, amountY, accuracy: 2, "Scrubbing must not move the stats card")
    }

    /// Swipe-deletes the first Carrefour row; returns the Carrefour match count before deleting.
    private func swipeDeleteCarrefour(_ app: XCUIApplication) -> Int {
        app.tabBars.buttons["Transactions"].tap()
        let row = carrefourRows(app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Carrefour row missing")
        let before = carrefourRows(app).count
        row.swipeLeft()
        let trash = app.buttons["Delete"].firstMatch
        XCTAssertTrue(trash.waitForExistence(timeout: 5), "Trash swipe action missing")
        trash.tap()
        return before
    }

    func testOwnerRule_DeleteShowsUndoAndUndoRestoresRow() throws {
        let app = launch()
        let before = swipeDeleteCarrefour(app)
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2), "Undo must appear after delete")
        XCTAssertLessThan(carrefourRows(app).count, before, "Row must disappear on delete")
        undo.tap()
        XCTAssertEqual(carrefourRows(app).count, before, "Undo must restore the row")
        sleep(6)
        XCTAssertEqual(carrefourRows(app).count, before, "Row must stay after undo timeout")
    }

    func testOwnerRule_DeleteWithoutUndoRemovesRow() throws {
        let app = launch()
        let before = swipeDeleteCarrefour(app)
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 2))
        sleep(7)
        XCTAssertFalse(app.buttons["Undo"].exists, "Undo must expire")
        XCTAssertLessThan(carrefourRows(app).count, before, "Deleted row must stay removed")
    }

    func testOwnerRule_StatsBarOffersViewTransactions() throws {
        let app = launch(["-GhafTab", "insights", "-GhafSelection", "bar"])
        let button = app.buttons["View transactions"]
        XCTAssertTrue(button.waitForExistence(timeout: 4))
        button.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Carrefour"))
            .firstMatch.waitForExistence(timeout: 5), "Sheet must list a transaction")
    }

    func testOwnerRule_WalletShowsPerCurrencyTotal() throws {
        let app = launch(["-GhafScreen", "wallet"], waitTabBar: false)
        XCTAssertTrue(app.staticTexts["Total"].waitForExistence(timeout: 10))
    }

    /// V13: Budget opens from the character sheet. V14: a locked streak tier opens an explanation card.
    func testOwnerRule_CharacterSheetOpensBudgetAndLockedStreakExplains() throws {
        let app = launch(["-GhafTab", "more"])
        let character = app.buttons["budget-character"]
        XCTAssertTrue(character.waitForExistence(timeout: 10), "Character button missing on Profile")
        character.tap()
        let changeBudget = app.buttons["Change in Budget"]
        XCTAssertTrue(changeBudget.waitForExistence(timeout: 5), "Character sheet must offer Change in Budget")
        changeBudget.tap()
        XCTAssertTrue(app.navigationBars["Budget"].waitForExistence(timeout: 5) || app.staticTexts["Budget"].waitForExistence(timeout: 3),
                      "Budget page must open")
        XCTAssertFalse(character.isHittable, "Profile must be covered by the Budget page")

        let app2 = launch(["-GhafTab", "more"])
        let locked = app2.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "90 days")).firstMatch
        for _ in 0..<5 where !(locked.exists && locked.isHittable) { app2.swipeUp() }
        locked.tap()
        XCTAssertTrue(app2.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Finish the 30-day streak")).firstMatch.waitForExistence(timeout: 5),
                      "Locked tier must explain how to unlock")
    }

    /// V17/V18: every widget is shown to free users, and the 14 widgets end on a full row (Top places beside Budget petals).
    func testOwnerRule_WidgetGalleryShowsAllAndEndsOnFullRow() throws {
        let app = launch(["-GhafScreen", "widgets", "-GhafAINonProTestAccess"], waitTabBar: false)
        let petals = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Budget petals,")).firstMatch
        for _ in 0..<8 where !(petals.exists && petals.isHittable) { app.swipeUp() }
        XCTAssertTrue(petals.isHittable, "Budget petals preview missing")
        let places = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Top places,")).firstMatch
        XCTAssertTrue(places.exists, "Top places preview missing")
        XCTAssertEqual(places.frame.minY, petals.frame.minY, accuracy: 2, "Last two widgets must share one row")
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Ghaf Pro")).count, 0,
                       "Free users must see widgets, not a Pro mask")
    }
}
