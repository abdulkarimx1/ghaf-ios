import XCTest

/// Covers edits made on Home that keep the transaction count unchanged.
final class GhafLedgerRevisionTests: XCTestCase {
    func testHomeAmountEditRefreshesStatsAndTransactionTotals() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafTheme", "Graphite",
                              "-GhafAppearance", "Light", "-GhafLanguage", "en"]
        if let backup = ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_BACKUP"] {
            app.launchArguments += ["-GhafRestoreBackup", backup]
        }
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        let homeSpent = app.descendants(matching: .any)["home.period.spent"]
        let homeCount = app.descendants(matching: .any)["home.period.count"]
        XCTAssertTrue(homeSpent.waitForExistence(timeout: 10))
        XCTAssertTrue(homeCount.exists)

        app.tabBars.buttons["Stats"].tap()
        let statsSpent = app.descendants(matching: .any)["stats.period.spent"]
        XCTAssertTrue(statsSpent.waitForExistence(timeout: 10))
        let oldStatsTotal = statsSpent.label

        app.tabBars.buttons["Transactions"].tap()
        let transactionsSpent = app.descendants(matching: .any)["transactions.month.spent"]
        XCTAssertTrue(transactionsSpent.waitForExistence(timeout: 10))
        let oldTransactionsTotal = transactionsSpent.label

        app.tabBars.buttons["Home"].tap()
        homeCount.tap() // Switch the period to the rolling week; the fixture's recent item is two days old.
        let oldHomeTotal = homeSpent.label
        let oldTransactionCount = homeCount.label
        let transaction = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Local Cafe")
        ).firstMatch
        XCTAssertTrue(transaction.waitForExistence(timeout: 10), "Expected a recent transaction on Home")
        transaction.tap()

        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()

        app.buttons["Amount"].tap()
        for key in ["7", "7", "7", ".", "7", "7"] {
            let digit = app.buttons[key]
            XCTAssertTrue(digit.waitForExistence(timeout: 5), "Missing keypad key \(key)")
            digit.tap()
        }
        app.buttons["Done"].firstMatch.tap()
        app.buttons["Save changes"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        app.buttons["Done"].firstMatch.tap()

        let homeChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", oldHomeTotal), object: homeSpent
        )
        XCTAssertEqual(XCTWaiter.wait(for: [homeChanged], timeout: 10), .completed)
        XCTAssertEqual(homeCount.label, oldTransactionCount, "Editing an amount must not change transaction count")

        app.tabBars.buttons["Stats"].tap()
        let statsChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", oldStatsTotal), object: statsSpent
        )
        XCTAssertEqual(XCTWaiter.wait(for: [statsChanged], timeout: 10), .completed)

        app.tabBars.buttons["Transactions"].tap()
        let transactionsChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", oldTransactionsTotal), object: transactionsSpent
        )
        XCTAssertEqual(XCTWaiter.wait(for: [transactionsChanged], timeout: 10), .completed)
    }
}
